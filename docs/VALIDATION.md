# Validation / Validación

## English

Publication checks performed on 20 October 2026. These are bounded checks, not certification of a finished CNC machine.

| Check | Result and scope |
|---|---|
| Original sources | 38 files from rapido_es_v3 and 26 from homing retained byte for byte; SHA-256 values are recorded in `source-manifest.json`. |
| Python protocol | `variants/vga-simulation/test_protocol_python.py` passed all three existing offline FakeSerial scenarios. No board or serial port was involved. |
| VHDL analysis | Vivado 2025.2 `xvhdl --2008` accepted all nine VGA design RTL files. Parsing is not elaboration, simulation, synthesis or timing closure. |
| Original testbenches | The compilation then failed in `tb_fsm_main.vhd`: the parameter `sequence` conflicts with a VHDL-2008 reserved word. The integration testbench also retains single-byte K expectations despite the newer 5-byte response protocol. No complete simulation pass is claimed. |
| Portable project helper | Both variants were recreated with Vivado 2025.2 using `scripts/create_project.tcl`; see publication verification records for the resulting status. |
| Hardware demonstrations | Original supplied videos show the physical setup/motors and a VGA trajectory. The exact bitstream revisions are not identified. No new hardware test was performed during publication. |

### Limitations visible in the retained code

- **Physical host:** the timeout path exits the reply-wait loop without propagating failure to the motion caller, so host coordinates can advance even when completion was not confirmed. A pen-state change also adds a one-step X movement that is not included in the tracked coordinates.
- **VGA host/RTL pairing:** sequence-aware commands and framed replies require the matching VGA bitstream. The physical host's single-byte completion protocol is a different interface.
- **Virtual homing:** only the G28 behavior changes. Ordinary motion still produces axis commands, so display-only use must not assume motors are disabled by this flag.
- **Position feedback:** VGA represents calculated steps, not an encoder or a measurement. A K reply does not establish actual mechanical position. Driver fault/drop indications are not exposed as a complete host diagnostic interface.
- **Motion profile:** the checked pipeline uses configured step timing rather than an acceleration planner; 20 steps/mm is an original calibration assumption. Host `--motor-hz` affects timeout estimates, not the RTL frequency.
- **G-code:** this is a limited interpreter, not a full CNC/G-code implementation. The VGA client does not implement arc interpolation or feed-rate control.

Original RTL and host files were deliberately preserved. These issues are documented rather than silently repaired during a publishing task. The original poster's simulation/hardware claims are historical presentation content, not independent evidence that all current files pass.

## Español

Comprobaciones de publicación realizadas el 20 de octubre de 2026. Su alcance es limitado y no certifica una máquina CNC terminada.

| Comprobación | Resultado y alcance |
|---|---|
| Fuentes originales | Se conservan 38 archivos de rapido_es_v3 y 26 de homing sin cambiar sus bytes. `source-manifest.json` contiene sus hashes SHA-256. |
| Protocolo Python | Pasaron los tres casos offline existentes de `test_protocol_python.py` mediante FakeSerial. No se utilizó una placa ni un puerto serie real. |
| Análisis VHDL | Vivado 2025.2 aceptó los nueve archivos RTL VGA con `xvhdl --2008`. El análisis no equivale a elaboración, simulación, síntesis o cierre de tiempos. |
| Testbenches originales | La compilación falló después en `tb_fsm_main.vhd`: `sequence` es una palabra reservada de VHDL-2008. El testbench de integración también espera la respuesta K de un byte, aunque el protocolo nuevo responde con cinco bytes. No se afirma que haya pasado una simulación completa. |
| Script portable | Se recrearon ambas variantes mediante Vivado 2025.2 y `scripts/create_project.tcl`; el estado se recoge en la verificación de publicación. |
| Hardware | Los vídeos suministrados muestran el montaje/motores y una trayectoria VGA. No se identifica la revisión exacta de los bitstreams y no se realizó una nueva prueba física durante la publicación. |

### Limitaciones del código conservado

- El host físico no propaga el fallo por timeout al planificador y puede actualizar sus coordenadas sin una confirmación de finalización. El cambio de estado del bolígrafo añade además un paso X que no registra en sus coordenadas.
- Cada cliente Python requiere el RTL de su variante: la respuesta K de un byte y el protocolo con secuencia/respuesta de cinco bytes no son la misma interfaz.
- El homing virtual modifica G28; no desactiva las órdenes de movimiento normales.
- VGA representa pasos calculados, no posiciones medidas. Una respuesta K tampoco acredita la posición mecánica. Las señales de fallo/pasos descartados del driver no constituyen una interfaz completa de diagnóstico para el host.
- No hay un planificador de aceleración en el flujo comprobado. Los 20 pasos/mm son un supuesto de calibración original. `--motor-hz` solo cambia las estimaciones de timeout.
- El intérprete G-code es limitado. El cliente VGA no implementa interpolación de arcos ni control de avance F.

Se han conservado los archivos originales del RTL y del host. Estos puntos se documentan sin introducir reparaciones funcionales silenciosas durante la publicación. Las afirmaciones del póster pertenecen a la presentación original y no demuestran que todos los archivos actuales superen las pruebas.
