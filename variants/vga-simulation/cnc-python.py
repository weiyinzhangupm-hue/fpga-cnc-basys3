#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Control CNC/VGA para Basys3 con protocolo UART fiable y modo rápido.

Esta versión debe usarse con el bitstream generado desde este mismo proyecto.
La trama de comando sigue teniendo 9 bytes, pero los bytes 6-7 contienen un
número de secuencia de 16 bits. La FPGA responde con una trama de 5 bytes:
0x55, estado, secuencia MSB, secuencia LSB, checksum XOR.

La retransmisión es idempotente: reenviar la misma secuencia sirve como
consulta de estado y nunca repite el movimiento físico. Por eso se puede
reintentar rápido sin perder precisión ni duplicar trayectorias.
"""

from __future__ import annotations

import argparse
import glob
import math
import os
from pathlib import Path
import re
import secrets
import sys
import time
from dataclasses import dataclass
from typing import Optional

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    serial = None
    list_ports = None


# -----------------------------------------------------------------------------
# Constantes del protocolo
# -----------------------------------------------------------------------------
CMD_SYNC = 0xAA
RESP_SYNC = 0x55
STATUS_ACCEPTED = ord("A")       # comando aceptado
STATUS_RUNNING = ord("R")        # comando aún en ejecución
STATUS_DONE = ord("K")           # comando terminado correctamente
STATUS_BUSY = ord("B")           # FPGA ocupada con otra secuencia
STATUS_CRC_ERROR = ord("C")      # checksum de comando incorrecto
STATUS_FRAME_ERROR = ord("F")    # error UART de framing
STATUS_FRAME_TIMEOUT = ord("T")  # trama incompleta / separación excesiva
UNKNOWN_SEQUENCE = 0xFFFF

# -----------------------------------------------------------------------------
# Ajustes rápidos. Deben coincidir con top_level.vhd para los tiempos calculados.
# -----------------------------------------------------------------------------
DEFAULT_BAUD = 115200
DEFAULT_STEPS_PER_MM = 20.0
DEFAULT_MOTOR_HZ = 3000.0          # top_level.vhd usa SYS_MOT_FREQ = 3000
DEFAULT_INITIAL_RETRY_S = 0.03     # reintento antes de que la FPGA acepte
DEFAULT_POLL_INTERVAL_S = 0.05     # reconsulta si se pierde una respuesta
DEFAULT_SERVO_SETTLE_S = 0.05      # para previsualización VGA; usar 0.5-0.8 con servo real
DEFAULT_DONE_MARGIN_S = 1.25       # margen global para timeout no-homing
DEFAULT_VIRTUAL_HOME_CLEAR_S = 0.005
DEFAULT_HOMING_TIMEOUT_S = 75.0
MAX_AXIS_STEPS_PER_FRAME = 65535

BASE_DIR = Path(__file__).resolve().parent


class CNCProtocolError(RuntimeError):
    """Error general de protocolo o sincronización."""


class LegacyBitstreamError(CNCProtocolError):
    """La FPGA parece tener cargado el protocolo antiguo de un solo byte 'K'."""


class LinuxSerial:
    """Pequeño reemplazo compatible con pyserial para Linux sin pyserial."""

    def __init__(self, port: str, baudrate: int, timeout: float = 0.02):
        import select
        import termios

        baud_map = {
            9600: termios.B9600,
            19200: termios.B19200,
            38400: termios.B38400,
            57600: termios.B57600,
            115200: termios.B115200,
        }
        if baudrate not in baud_map:
            raise ValueError(f"Baudrate no soportado sin pyserial: {baudrate}")

        self._select = select
        self._termios = termios
        self.timeout = timeout
        self.fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_SYNC)
        attrs = termios.tcgetattr(self.fd)
        attrs[0] = 0
        attrs[1] = 0
        attrs[2] &= ~(termios.PARENB | termios.CSTOPB | termios.CSIZE)
        if hasattr(termios, "CRTSCTS"):
            attrs[2] &= ~termios.CRTSCTS
        attrs[2] |= termios.CS8 | termios.CLOCAL | termios.CREAD
        attrs[3] = 0
        attrs[4] = baud_map[baudrate]
        attrs[5] = baud_map[baudrate]
        attrs[6][termios.VMIN] = 0
        attrs[6][termios.VTIME] = 0
        termios.tcsetattr(self.fd, termios.TCSANOW, attrs)
        self.is_open = True

    @property
    def in_waiting(self) -> int:
        return 0

    def write(self, data: bytes) -> int:
        return os.write(self.fd, data)

    def flush(self) -> None:
        self._termios.tcdrain(self.fd)

    def reset_input_buffer(self) -> None:
        self._termios.tcflush(self.fd, self._termios.TCIFLUSH)

    def reset_output_buffer(self) -> None:
        self._termios.tcflush(self.fd, self._termios.TCOFLUSH)

    def read(self, size: int = 1) -> bytes:
        ready, _, _ = self._select.select([self.fd], [], [], self.timeout)
        if not ready:
            return b""
        return os.read(self.fd, size)

    def close(self) -> None:
        if self.is_open:
            os.close(self.fd)
            self.is_open = False


@dataclass(frozen=True)
class Response:
    status: int
    sequence: int

    @property
    def status_text(self) -> str:
        return chr(self.status) if 32 <= self.status <= 126 else f"0x{self.status:02X}"


class ReliableCNCLink:
    """Enlace UART fiable con secuencia, checksum y reintento idempotente."""

    def __init__(
        self,
        serial_port,
        motor_hz: float,
        initial_retry_s: float = DEFAULT_INITIAL_RETRY_S,
        poll_interval_s: float = DEFAULT_POLL_INTERVAL_S,
        done_margin_s: float = DEFAULT_DONE_MARGIN_S,
        homing_timeout_s: float = DEFAULT_HOMING_TIMEOUT_S,
    ) -> None:
        if motor_hz <= 0:
            raise ValueError("motor_hz debe ser mayor que 0")
        if initial_retry_s <= 0:
            raise ValueError("initial_retry_s debe ser mayor que 0")
        if poll_interval_s <= 0:
            raise ValueError("poll_interval_s debe ser mayor que 0")

        self.ser = serial_port
        self.motor_hz = motor_hz
        self.initial_retry_s = initial_retry_s
        self.poll_interval_s = poll_interval_s
        self.done_margin_s = max(0.20, done_margin_s)
        self.homing_timeout_s = homing_timeout_s
        self._rx_buffer = bytearray()

        # Secuencia inicial aleatoria para evitar confundir un ACK antiguo al reiniciar solo Python.
        self._next_sequence = secrets.randbelow(0xFFFE)
        self.total_tx_frames = 0
        self.total_rx_frames = 0
        self.total_link_errors = 0
        self.legacy_k_bytes = 0

    def _allocate_sequence(self) -> int:
        sequence = self._next_sequence
        self._next_sequence = (self._next_sequence + 1) & 0xFFFF
        if self._next_sequence == UNKNOWN_SEQUENCE:
            self._next_sequence = 0
        return sequence

    @staticmethod
    def _xor_checksum(data: bytes) -> int:
        value = 0
        for byte in data:
            value ^= byte
        return value

    @classmethod
    def _build_command_frame(
        cls,
        sequence: int,
        steps_x: int,
        steps_y: int,
        dir_x: bool,
        dir_y: bool,
        pen_down: bool,
        is_homing: bool,
    ) -> bytes:
        if not 0 <= sequence <= 0xFFFF:
            raise ValueError("sequence fuera de rango de 16 bits")
        if not 0 <= steps_x <= MAX_AXIS_STEPS_PER_FRAME:
            raise ValueError("steps_x fuera de rango de 16 bits")
        if not 0 <= steps_y <= MAX_AXIS_STEPS_PER_FRAME:
            raise ValueError("steps_y fuera de rango de 16 bits")

        flags = (
            (1 if dir_x else 0)
            | ((1 if dir_y else 0) << 1)
            | ((1 if pen_down else 0) << 2)
            | ((1 if is_homing else 0) << 3)
        )
        body = bytes(
            [
                CMD_SYNC,
                flags,
                (steps_x >> 8) & 0xFF,
                steps_x & 0xFF,
                (steps_y >> 8) & 0xFF,
                steps_y & 0xFF,
                (sequence >> 8) & 0xFF,
                sequence & 0xFF,
            ]
        )
        return body + bytes([cls._xor_checksum(body)])

    def _write_all(self, payload: bytes) -> None:
        total = 0
        while total < len(payload):
            written = self.ser.write(payload[total:])
            if written is None:
                total = len(payload)
            elif written <= 0:
                raise CNCProtocolError("La escritura serie devolvió 0 bytes")
            else:
                total += written
        self.ser.flush()
        self.total_tx_frames += 1

    def _extract_response_from_buffer(self) -> Optional[Response]:
        while True:
            try:
                sync_index = self._rx_buffer.index(RESP_SYNC)
            except ValueError:
                # Un 'K' suelto indica que quizá sigue cargado el bitstream antiguo.
                self.legacy_k_bytes += self._rx_buffer.count(STATUS_DONE)
                self._rx_buffer.clear()
                return None

            if sync_index > 0:
                prefix = self._rx_buffer[:sync_index]
                self.legacy_k_bytes += prefix.count(STATUS_DONE)
                del self._rx_buffer[:sync_index]

            if len(self._rx_buffer) < 5:
                return None

            candidate = bytes(self._rx_buffer[:5])
            if self._xor_checksum(candidate[:4]) == candidate[4]:
                del self._rx_buffer[:5]
                self.total_rx_frames += 1
                return Response(status=candidate[1], sequence=(candidate[2] << 8) | candidate[3])

            # Checksum de respuesta incorrecto: descartar solo este 0x55 y seguir buscando.
            del self._rx_buffer[0]
            self.total_link_errors += 1

    def read_response(self, timeout_s: float) -> Optional[Response]:
        deadline = time.monotonic() + max(0.0, timeout_s)
        while True:
            parsed = self._extract_response_from_buffer()
            if parsed is not None:
                return parsed

            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None

            if hasattr(self.ser, "timeout"):
                self.ser.timeout = min(0.02, max(0.002, remaining))

            waiting = getattr(self.ser, "in_waiting", 0)
            chunk_size = min(max(int(waiting), 1), 64)
            chunk = self.ser.read(chunk_size)
            if chunk:
                self._rx_buffer.extend(chunk)

    def execute_command(
        self,
        steps_x: int,
        steps_y: int,
        dir_x: bool,
        dir_y: bool,
        pen_down: bool,
        is_homing: bool = False,
        label: str = "Movimiento",
        quiet: bool = False,
    ) -> int:
        """Ejecuta un comando y espera K.

        La espera se acorta con dos fases:
        1. Antes de recibir A/R, se reenvía la misma secuencia cada 30 ms.
        2. Tras recibir A/R, se espera K y solo se consulta periódicamente por si
           el K automático se perdió. Nunca se cambia de secuencia durante el reintento.
        """
        sequence = self._allocate_sequence()
        payload = self._build_command_frame(sequence, steps_x, steps_y, dir_x, dir_y, pen_down, is_homing)

        estimated_motion_s = max(steps_x, steps_y) / self.motor_hz
        if is_homing and max(steps_x, steps_y) > 0:
            overall_timeout_s = max(self.homing_timeout_s, estimated_motion_s + 5.0)
        else:
            overall_timeout_s = max(0.80, estimated_motion_s + self.done_margin_s)

        if not quiet:
            print(
                f"   -> {label}: seq={sequence:04X}, X={steps_x}, Y={steps_y}, "
                f"pen={'ABAJO' if pen_down else 'ARRIBA'}, "
                f"homing={'SI' if is_homing else 'NO'}"
            )

        start_time = time.monotonic()
        deadline = start_time + overall_timeout_s
        next_tx_time = start_time
        accepted = False
        tx_count = 0
        last_progress_print = start_time

        while True:
            now = time.monotonic()
            if now >= deadline:
                elapsed = now - start_time
                raise TimeoutError(
                    f"El comando seq={sequence:04X} no terminó en {elapsed:.2f}s. "
                    "La FPGA puede estar en movimiento/homing, o la línea UART sigue fallando."
                )

            if now >= next_tx_time:
                self._write_all(payload)
                tx_count += 1

                if accepted:
                    # Si el movimiento ya fue aceptado, consultar con frecuencia moderada.
                    # En movimientos largos evita saturar la cola, y si se perdió K recupera rápido.
                    if is_homing:
                        interval = min(0.25, max(self.poll_interval_s, 0.05))
                    else:
                        interval = min(0.20, max(self.poll_interval_s, 0.03))
                    next_tx_time = now + interval
                else:
                    # Aún no sabemos si la FPGA recibió el comando: reintento rápido y seguro.
                    next_tx_time = now + self.initial_retry_s

            wait_until = min(next_tx_time, deadline)
            response = self.read_response(max(0.0, wait_until - time.monotonic()))
            if response is None:
                continue

            if response.sequence == UNKNOWN_SEQUENCE and response.status in {STATUS_FRAME_ERROR, STATUS_FRAME_TIMEOUT}:
                self.total_link_errors += 1
                next_tx_time = time.monotonic() + 0.005
                if not quiet:
                    print(f"      Error de enlace {response.status_text}; reenviando la misma seq")
                continue

            if response.sequence != sequence:
                # Respuesta retrasada de otro comando. La secuencia evita falsos positivos.
                if not quiet:
                    print(
                        f"      Respuesta antigua ignorada: estado={response.status_text}, "
                        f"seq={response.sequence:04X}"
                    )
                continue

            if response.status == STATUS_DONE:
                if not quiet:
                    elapsed = time.monotonic() - start_time
                    print(f"      OK K: seq={sequence:04X}, tiempo={elapsed:.3f}s, envios={tx_count}")
                return sequence

            if response.status == STATUS_ACCEPTED:
                accepted = True
                # Para comando cero o cambio de lápiz, K debe llegar casi inmediato.
                next_tx_time = min(next_tx_time, time.monotonic() + max(0.01, self.poll_interval_s))
                if not quiet:
                    print(f"      FPGA aceptó A: seq={sequence:04X}")
                continue

            if response.status == STATUS_RUNNING:
                accepted = True
                now = time.monotonic()
                if not quiet and now - last_progress_print >= 1.0:
                    print(f"      FPGA ejecutando R: seq={sequence:04X}")
                    last_progress_print = now
                continue

            if response.status in {STATUS_CRC_ERROR, STATUS_FRAME_ERROR, STATUS_FRAME_TIMEOUT}:
                self.total_link_errors += 1
                next_tx_time = time.monotonic() + 0.005
                if not quiet:
                    print(f"      FPGA devolvió {response.status_text}; reenviando la misma seq")
                continue

            if response.status == STATUS_BUSY:
                raise CNCProtocolError(
                    f"La FPGA está ocupada con otra secuencia y rechazó seq={sequence:04X}. "
                    "Pulsa reset en la Basys3 para resincronizar."
                )

            if not quiet:
                print(f"      Estado desconocido 0x{response.status:02X}; ignorado")

    def handshake(self) -> None:
        """Comprueba que la FPGA usa el protocolo fiable de 5 bytes."""
        print("Comprobando protocolo fiable de la FPGA...")
        legacy_before = self.legacy_k_bytes
        try:
            # Dos secuencias distintas evitan que un ACK en caché parezca un handshake válido.
            for _ in range(2):
                self.execute_command(0, 0, True, True, False, False, label="Handshake", quiet=True)
        except TimeoutError as exc:
            if self.legacy_k_bytes > legacy_before:
                raise LegacyBitstreamError(
                    "Se detectó una respuesta antigua de un solo byte 'K'. "
                    "Genera y programa el bitstream rapido_es_v3 antes de usar este script."
                ) from exc
            raise
        print("Handshake correcto: secuencia, checksum y reintento funcionan.")

    def link_test(self, count: int) -> None:
        if count <= 0:
            raise ValueError("El número de pruebas debe ser mayor que 0")
        print(f"Iniciando prueba de enlace: {count} comandos de cero pasos...")
        latencies = []
        tx_before = self.total_tx_frames
        err_before = self.total_link_errors
        for index in range(1, count + 1):
            started = time.monotonic()
            self.execute_command(0, 0, True, True, False, quiet=True, label="Prueba de enlace")
            latencies.append(time.monotonic() - started)
            if index % max(1, count // 10) == 0 or index == count:
                print(f"  {index}/{count}")

        print(
            "Prueba terminada: "
            f"media={sum(latencies) / len(latencies) * 1000:.1f} ms, "
            f"max={max(latencies) * 1000:.1f} ms, "
            f"tramas TX={self.total_tx_frames - tx_before}, "
            f"errores de enlace={self.total_link_errors - err_before}"
        )


class CNCController:
    """Planificador G-code: mm -> pasos -> comandos fiables."""

    def __init__(
        self,
        link: ReliableCNCLink,
        steps_per_mm: float,
        servo_settle_s: float,
        homing_mode: str,
        scale_xy: float,
    ) -> None:
        if steps_per_mm <= 0:
            raise ValueError("steps_per_mm debe ser mayor que 0")
        if scale_xy <= 0:
            raise ValueError("scale_xy debe ser mayor que 0")
        self.link = link
        self.steps_per_mm = steps_per_mm
        self.servo_settle_s = max(0.0, servo_settle_s)
        self.homing_mode = homing_mode
        self.scale_xy = scale_xy
        self.pos_x_steps = 0
        self.pos_y_steps = 0
        self.pen_down = False
        self.absolute_mode = True

    def mm_to_steps(self, millimetres: float) -> int:
        return int(round(millimetres * self.steps_per_mm))

    def steps_to_mm(self, steps: int) -> float:
        return steps / self.steps_per_mm

    def set_pen(self, down: bool) -> None:
        if down == self.pen_down:
            return

        # Cambio de lápiz sin desplazamiento. El antiguo micropaso artificial fue eliminado.
        self.link.execute_command(0, 0, True, True, down, False, label="Bajar lápiz" if down else "Subir lápiz")
        self.pen_down = down
        if self.servo_settle_s:
            time.sleep(self.servo_settle_s)

    def _move_segment(self, target_x_steps: int, target_y_steps: int) -> None:
        delta_x = target_x_steps - self.pos_x_steps
        delta_y = target_y_steps - self.pos_y_steps
        steps_x = abs(delta_x)
        steps_y = abs(delta_y)

        if steps_x == 0 and steps_y == 0:
            return

        self.link.execute_command(
            steps_x,
            steps_y,
            delta_x >= 0,
            delta_y >= 0,
            self.pen_down,
            False,
            label="Movimiento lineal",
        )
        self.pos_x_steps = target_x_steps
        self.pos_y_steps = target_y_steps

    def move_to_mm(self, target_x_mm: float, target_y_mm: float, pen_down: bool) -> None:
        self.set_pen(pen_down)

        target_x_steps = self.mm_to_steps(target_x_mm)
        target_y_steps = self.mm_to_steps(target_y_mm)
        start_x = self.pos_x_steps
        start_y = self.pos_y_steps
        delta_x = target_x_steps - start_x
        delta_y = target_y_steps - start_y
        max_steps = max(abs(delta_x), abs(delta_y))

        if max_steps == 0:
            return

        segment_count = max(1, math.ceil(max_steps / MAX_AXIS_STEPS_PER_FRAME))
        for segment in range(1, segment_count + 1):
            intermediate_x = start_x + round(delta_x * segment / segment_count)
            intermediate_y = start_y + round(delta_y * segment / segment_count)
            self._move_segment(intermediate_x, intermediate_y)

    def home_physical(self) -> None:
        print("\nHoming físico: buscando finales de carrera X/Y...")
        self.set_pen(False)
        self.link.execute_command(60000, 60000, False, False, False, True, label="Homing físico")
        self.pos_x_steps = 0
        self.pos_y_steps = 0
        print("Homing físico completado. Coordenadas del PC: X=0, Y=0.")

    def home_virtual(self) -> None:
        print("\nHoming virtual rápido: limpiar VGA y poner coordenadas en X=0, Y=0...")
        self.set_pen(False)
        # Homing con cero pasos: dispara trace_clear en la FPGA sin esperar finales de carrera.
        self.link.execute_command(0, 0, False, False, False, True, label="Homing virtual")
        self.pos_x_steps = 0
        self.pos_y_steps = 0
        # La RAM VGA tarda aprox. 0.704 ms en limpiarse; 5 ms deja margen amplio.
        time.sleep(DEFAULT_VIRTUAL_HOME_CLEAR_S)
        print("Homing virtual completado.")

    def home(self) -> None:
        if self.homing_mode == "fisico":
            self.home_physical()
        elif self.homing_mode == "virtual":
            self.home_virtual()
        elif self.homing_mode == "ninguno":
            print("\nG28 ignorado por configuración (--homing ninguno). Coordenadas del PC = 0,0.")
            self.set_pen(False)
            self.pos_x_steps = 0
            self.pos_y_steps = 0
        else:
            raise ValueError(f"Modo de homing no válido: {self.homing_mode}")

    @staticmethod
    def _remove_comments(line: str) -> str:
        line = line.split(";", 1)[0]
        line = re.sub(r"\([^)]*\)", "", line)
        return line.strip().upper()

    @staticmethod
    def _parse_words(line: str) -> list[tuple[str, float]]:
        words = re.findall(r"([A-Z])\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+))", line)
        return [(letter, float(value)) for letter, value in words]

    def process_gcode(self, filename: str) -> None:
        path = Path(filename)
        if not path.is_absolute() and not path.exists():
            path = BASE_DIR / path
        if not path.exists():
            raise FileNotFoundError(f"No se encuentra el archivo G-code: {filename}")

        print(f"\nIniciando trabajo: {path.name}")
        if self.scale_xy != 1.0:
            print(f"   Escala XY aplicada: {self.scale_xy:.3f}")

        with path.open("r", encoding="utf-8-sig") as handle:
            for line_number, raw_line in enumerate(handle, start=1):
                line = self._remove_comments(raw_line)
                if not line:
                    continue

                words = self._parse_words(line)
                if not words:
                    continue

                g_codes = [int(round(value)) for letter, value in words if letter == "G"]
                if 90 in g_codes:
                    self.absolute_mode = True
                if 91 in g_codes:
                    self.absolute_mode = False
                if 28 in g_codes:
                    self.home()
                    continue

                motion_code: Optional[int] = None
                for code in g_codes:
                    if code in (0, 1):
                        motion_code = code
                        break
                if motion_code is None:
                    continue

                current_x_mm = self.steps_to_mm(self.pos_x_steps)
                current_y_mm = self.steps_to_mm(self.pos_y_steps)
                target_x_mm = current_x_mm
                target_y_mm = current_y_mm
                requested_pen = motion_code == 1

                for letter, value in words:
                    if letter == "X":
                        scaled = value * self.scale_xy
                        target_x_mm = scaled if self.absolute_mode else current_x_mm + scaled
                    elif letter == "Y":
                        scaled = value * self.scale_xy
                        target_y_mm = scaled if self.absolute_mode else current_y_mm + scaled
                    elif letter == "Z":
                        requested_pen = value <= 0

                try:
                    self.move_to_mm(target_x_mm, target_y_mm, requested_pen)
                except Exception as exc:
                    raise CNCProtocolError(f"Fallo en línea {line_number}: {line}\n{exc}") from exc

        print(f"Trabajo finalizado: {path.name}")


def detect_serial_port(explicit_port: Optional[str]) -> str:
    if explicit_port:
        return explicit_port

    for variable in ("CNC_PORT", "PUERTO_SERIAL"):
        value = os.environ.get(variable)
        if value:
            return value

    if serial is not None and list_ports is not None:
        ports = list(list_ports.comports())
        preferred = []
        for port in ports:
            text = " ".join(str(item or "") for item in (port.description, port.manufacturer, port.hwid)).lower()
            if any(key in text for key in ("digilent", "ftdi", "usb serial")):
                preferred.append(port.device)

        if len(preferred) == 1:
            return preferred[0]
        if len(ports) == 1:
            return ports[0].device
        if ports:
            devices = ", ".join(port.device for port in ports)
            raise RuntimeError(f"Se detectaron varios puertos: {devices}. Usa --port COM14 o CNC_PORT.")

    if os.name != "nt":
        candidates = []
        for pattern in ("/dev/serial/by-id/*", "/dev/ttyUSB*", "/dev/ttyACM*"):
            candidates.extend(glob.glob(pattern))
        if len(candidates) == 1:
            return sorted(candidates)[0]

    raise RuntimeError("No se encontró el puerto serie. Usa --port COM14 o define CNC_PORT.")


def open_serial(port: str, baud: int):
    print(f"Abriendo puerto {port} a {baud} baud, 8N1, sin control de flujo...")
    if serial is not None:
        connection = serial.Serial(
            port=port,
            baudrate=baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0.02,
            write_timeout=2.0,
            xonxoff=False,
            rtscts=False,
            dsrdtr=False,
        )
        try:
            connection.dtr = False
            connection.rts = False
        except (AttributeError, OSError):
            pass
    elif os.name != "nt":
        connection = LinuxSerial(port, baud, timeout=0.02)
    else:
        raise ImportError("En Windows instala pyserial: py -3 -m pip install pyserial")

    connection.reset_input_buffer()
    connection.reset_output_buffer()
    time.sleep(0.05)
    return connection


def print_menu() -> None:
    print("\n" + "=" * 60)
    print(" Basys3 CNC / VGA - Control rápido y fiable")
    print("=" * 60)
    print("1. Prueba X/Y                  (ejeXY_prueba.gcode)")
    print("2. Prueba de servo             (test_servo.gcode)")
    print("3. Círculo                     (circulo.gcode)")
    print("4. Rectángulo                  (rectangulo_cnc_trace.gcode)")
    print("5. Triángulo                   (triangulo_cnc_trace.gcode)")
    print("6. Rectángulo rápido reducido  (rectangulo_vga_rapido.gcode)")
    print("7. Triángulo rápido reducido   (triangulo_vga_rapido.gcode)")
    print("8. Homing según configuración")
    print("9. Salir")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Control rápido y fiable para CNC/VGA en Basys3")
    parser.add_argument("files", nargs="*", help="Archivos G-code a ejecutar en orden")
    parser.add_argument("--port", help="Puerto serie, por ejemplo COM14")
    parser.add_argument("--baud", type=int, default=DEFAULT_BAUD)
    parser.add_argument("--steps-per-mm", type=float, default=DEFAULT_STEPS_PER_MM)
    parser.add_argument("--motor-hz", type=float, default=DEFAULT_MOTOR_HZ,
                        help="Debe coincidir con SYS_MOT_FREQ del bitstream")
    parser.add_argument("--initial-retry", type=float, default=DEFAULT_INITIAL_RETRY_S,
                        help="Segundos entre reintentos antes de recibir A/R")
    parser.add_argument("--poll", type=float, default=DEFAULT_POLL_INTERVAL_S,
                        help="Segundos entre consultas de estado si se pierde K")
    parser.add_argument("--servo-settle", type=float, default=DEFAULT_SERVO_SETTLE_S,
                        help="Espera tras subir/bajar lápiz; usa 0 para solo VGA")
    parser.add_argument("--homing", choices=("virtual", "fisico", "ninguno"), default="virtual",
                        help="virtual limpia VGA sin mover motores; fisico usa finales de carrera")
    parser.add_argument("--homing-timeout", type=float, default=DEFAULT_HOMING_TIMEOUT_S)
    parser.add_argument("--scale", type=float, default=1.0,
                        help="Escala X/Y del G-code para dibujar más pequeño y más rápido")
    parser.add_argument("--link-test", type=int, metavar="N", help="Ejecuta N comandos de cero pasos")
    parser.add_argument("--no-handshake", action="store_true",
                        help="No recomendado: omite la comprobación inicial de protocolo")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    connection = None

    try:
        port = detect_serial_port(args.port)
        connection = open_serial(port, args.baud)
        link = ReliableCNCLink(
            connection,
            motor_hz=args.motor_hz,
            initial_retry_s=args.initial_retry,
            poll_interval_s=args.poll,
            homing_timeout_s=args.homing_timeout,
        )
        controller = CNCController(
            link,
            steps_per_mm=args.steps_per_mm,
            servo_settle_s=args.servo_settle,
            homing_mode=args.homing,
            scale_xy=args.scale,
        )

        if not args.no_handshake:
            link.handshake()

        if args.link_test is not None:
            link.link_test(args.link_test)
            return 0

        if args.files:
            for filename in args.files:
                controller.process_gcode(filename)
            return 0

        while True:
            print_menu()
            option = input("Elige una opción (1-9): ").strip()
            if option == "1":
                controller.process_gcode("ejeXY_prueba.gcode")
            elif option == "2":
                controller.process_gcode("test_servo.gcode")
            elif option == "3":
                controller.process_gcode("circulo.gcode")
            elif option == "4":
                controller.process_gcode("rectangulo_cnc_trace.gcode")
            elif option == "5":
                controller.process_gcode("triangulo_cnc_trace.gcode")
            elif option == "6":
                controller.process_gcode("rectangulo_vga_rapido.gcode")
            elif option == "7":
                controller.process_gcode("triangulo_vga_rapido.gcode")
            elif option == "8":
                controller.home()
            elif option == "9":
                return 0
            else:
                print("Opción no válida.")

    except KeyboardInterrupt:
        print("\nAbortado por el usuario. No se envió ningún movimiento adicional.")
        return 130
    except (TimeoutError, CNCProtocolError, LegacyBitstreamError) as exc:
        print(f"\nError de comunicación/protocolo: {exc}")
        return 2
    except Exception as exc:
        print(f"\nError: {exc}")
        return 1
    finally:
        if connection is not None and getattr(connection, "is_open", False):
            connection.close()
            print("Puerto serie cerrado.")


if __name__ == "__main__":
    raise SystemExit(main())
