#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Pruebas offline del protocolo fiable del lado Python.
No hace falta conectar la Basys3.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("cnc_rapido", ROOT / "cnc-python.py")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules["cnc_rapido"] = MODULE
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class FakeSerial:
    def __init__(self, mode: str = "drop_done_once") -> None:
        self.timeout = 0.002
        self.is_open = True
        self.mode = mode
        self.buffer = bytearray()
        self.counts: dict[int, int] = {}

    @property
    def in_waiting(self) -> int:
        return len(self.buffer)

    def reset_input_buffer(self) -> None:
        self.buffer.clear()

    def reset_output_buffer(self) -> None:
        pass

    def flush(self) -> None:
        pass

    def close(self) -> None:
        self.is_open = False

    def read(self, size: int = 1) -> bytes:
        if not self.buffer:
            time.sleep(min(self.timeout, 0.001))
            return b""
        result = bytes(self.buffer[:size])
        del self.buffer[:size]
        return result

    @staticmethod
    def response(status: int, sequence: int) -> bytes:
        body = bytes([0x55, status, sequence >> 8, sequence & 0xFF])
        return body + bytes([MODULE.ReliableCNCLink._xor_checksum(body)])

    def write(self, payload: bytes) -> int:
        assert len(payload) == 9
        assert payload[0] == 0xAA
        assert MODULE.ReliableCNCLink._xor_checksum(payload[:8]) == payload[8]
        sequence = (payload[6] << 8) | payload[7]
        attempt = self.counts.get(sequence, 0)
        self.counts[sequence] = attempt + 1

        if self.mode == "drop_done_once":
            if attempt == 0:
                self.buffer += self.response(ord("A"), sequence)
            else:
                self.buffer += self.response(ord("K"), sequence)
        elif self.mode == "crc_then_done":
            if attempt == 0:
                self.buffer += self.response(ord("C"), sequence)
            else:
                self.buffer += self.response(ord("A"), sequence)
                self.buffer += self.response(ord("K"), sequence)
        elif self.mode == "delayed_old_response":
            # Respuesta antigua con otra secuencia; debe ignorarse.
            old_sequence = (sequence - 1) & 0xFFFF
            self.buffer += self.response(ord("K"), old_sequence)
            self.buffer += self.response(ord("A"), sequence)
            self.buffer += self.response(ord("K"), sequence)
        else:
            self.buffer += self.response(ord("A"), sequence)
            self.buffer += self.response(ord("K"), sequence)
        return len(payload)


def run() -> None:
    fake = FakeSerial("drop_done_once")
    link = MODULE.ReliableCNCLink(fake, motor_hz=3000, initial_retry_s=0.005, poll_interval_s=0.005)
    sequence = link.execute_command(10, 0, True, True, False, quiet=True)
    assert fake.counts[sequence] >= 2, "la pérdida de K no provocó reconsulta segura"

    fake = FakeSerial("crc_then_done")
    link = MODULE.ReliableCNCLink(fake, motor_hz=3000, initial_retry_s=0.005, poll_interval_s=0.005)
    sequence = link.execute_command(0, 0, True, True, False, quiet=True)
    assert fake.counts[sequence] >= 2, "el error CRC no provocó reintento"
    assert link.total_link_errors >= 1

    fake = FakeSerial("delayed_old_response")
    link = MODULE.ReliableCNCLink(fake, motor_hz=3000, initial_retry_s=0.005, poll_interval_s=0.005)
    link.execute_command(0, 0, True, True, False, quiet=True)

    print("Pruebas Python del protocolo rápido: PASS")


if __name__ == "__main__":
    run()
