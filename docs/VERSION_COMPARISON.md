# Version comparison / Comparación de variantes

## English

The project owner identifies the two folders by their demonstration purpose:

- `hardware-homing` comes from **FPGA_CNC - homing**: connected peripherals, actual motor movement and physical homing.
- `vga-simulation` comes from **FPGA_CNC_rapido_es_v3**: VGA visualization of synchronized two-axis motion.

They are complementary demonstrations, not an assumed obsolete/new production release pair. Both are retained as independently browsable source trees. Duplicate files are intentional to preserve the original project layouts; do not combine hosts, UART/FSM files or pin constraints across variants without adapting and validating the interfaces.

## Español

El responsable del proyecto distingue las carpetas según la demostración:

- `hardware-homing`, procedente de **FPGA_CNC - homing**: periféricos conectados, movimiento real de motores y homing físico.
- `vga-simulation`, procedente de **FPGA_CNC_rapido_es_v3**: visualización VGA del movimiento sincronizado de dos ejes.

Son demostraciones complementarias; no se supone que una sea una versión de producción obsoleta de la otra. Ambas se conservan como árboles de código independientes. Los duplicados mantienen la estructura original. No mezclar clientes, UART/FSM o restricciones de pines entre variantes sin adaptar y validar sus interfaces.

## Functional differences / Diferencias funcionales

| Aspect / Aspecto | Hardware + homing | VGA trajectory / Trayectoria VGA |
|---|---|---|
| Host interface / Interfaz | Interactive menu, configured COM8 / Menú interactivo, COM8 configurable | CLI arguments (`--port`, `--homing`, `--link-test`, etc.) / Argumentos CLI |
| Command / Orden | 9 bytes; bytes 6–7 are padding / 9 bytes; bytes 6–7 de relleno | 9 bytes; bytes 6–7 carry the sequence / 9 bytes; bytes 6–7 contienen la secuencia |
| Response / Respuesta | Single-byte completion K / K de un byte | 5-byte status frame with sequence and XOR / Trama de 5 bytes con estado, secuencia y XOR |
| Step-frequency parameter / Frecuencia configurada | 1000 Hz | 3000 Hz |
| Homing | Physical / Físico | Virtual by default; physical option / Virtual por defecto; opción física |
| VGA | No `vga_shapes.vhd` module / Sin módulo `vga_shapes.vhd` | VGA trajectory module and drawing examples / Módulo VGA y ejemplos |
| FPGA host pairing / Correspondencia | Use this folder's Python and RTL / Python y RTL de esta carpeta | Use this folder's Python and RTL / Python y RTL de esta carpeta |

Both use UART 115200 / 8N1. A 9-byte application packet is not 9-bit UART. Step-frequency settings are not an overall performance benchmark.

Ambas usan UART 115200 / 8N1. Una orden de 9 bytes no significa UART de 9 bits. La frecuencia configurada no es una medición de rendimiento global.

## File comparison / Comparación de archivos

Only source, project, example and original documentation files are compared. Vivado-generated caches, runs, checkpoints and simulator output are excluded. Counts: **38 VGA files**, **26 hardware files**, **14 identical**, **11 differing at the same relative path**, **13 VGA-only** and **1 hardware-only**. Paths below are relative to each variant root. Comparison uses raw file bytes, not merely matching names.

Se comparan fuentes, proyectos, ejemplos y documentación original; se excluyen resultados y cachés generados por Vivado. Hay **38 archivos VGA**, **26 de hardware**, **14 idénticos**, **11 distintos con la misma ruta**, **13 exclusivos VGA** y **1 exclusivo hardware**. Las rutas siguientes son relativas a cada variante. La comparación se basa en los bytes, no solo en los nombres.

### Identical / Idénticos (14)

- `FPGA_CNC.srcs/sim_1/new/tb_bresenham_2d.vhd`
- `FPGA_CNC.srcs/sim_1/new/tb_divisor_reloj.vhd`
- `FPGA_CNC.srcs/sim_1/new/tb_pen_controler.vhd`
- `FPGA_CNC.srcs/sim_1/new/tb_uart_tx.vhd`
- `FPGA_CNC.srcs/sources_1/imports/Proyecto FPGA/pen_controller.vhd`
- `FPGA_CNC.srcs/sources_1/new/bresenham_3d.vhd`
- `FPGA_CNC.srcs/sources_1/new/divisor_reloj.vhd`
- `FPGA_CNC.srcs/sources_1/new/tb6600_axis_driver.vhd`
- `circulo.gcode`
- `cuadrado.gcode`
- `ejeXY_prueba.gcode`
- `ejeX_prueba.gcode`
- `ejeY_prueba.gcode`
- `test_servo.gcode`

### Different contents / Contenido diferente (11)

- `FPGA_CNC.srcs/constrs_1/imports/Tutorial/Basys3_Master.xdc`
- `FPGA_CNC.srcs/sim_1/new/tb_fsm_main.vhd`
- `FPGA_CNC.srcs/sim_1/new/tb_top_level.vhd`
- `FPGA_CNC.srcs/sim_1/new/tb_uart_rx.vhd`
- `FPGA_CNC.srcs/sources_1/new/FSM_Main.vhd`
- `FPGA_CNC.srcs/sources_1/new/top_level.vhd`
- `FPGA_CNC.srcs/sources_1/new/uart_rx.vhd`
- `FPGA_CNC.srcs/sources_1/new/uart_tx.vhd`
- `FPGA_CNC.xpr`
- `cnc-python.py`
- `test_servo.py`

### VGA only / Solo VGA (13)

- `BUILD_REQUIRED.txt`
- `FPGA_CNC.srcs/sources_1/new/vga_shapes.vhd`
- `INFORME_CAMBIOS_ES.md`
- `PROTOCOLO_RAPIDO_ES.md`
- `README_RAPIDO_ES.md`
- `build_bitstream.tcl`
- `diagnose_hw_targets.tcl`
- `program_basys3.tcl`
- `rectangulo_cnc_trace.gcode`
- `rectangulo_vga_rapido.gcode`
- `test_protocol_python.py`
- `triangulo_cnc_trace.gcode`
- `triangulo_vga_rapido.gcode`

### Hardware only / Solo hardware (1)

- `test_completo.gcode`

This is an empty original placeholder, not an additional executable demonstration.

Es un archivo original vacío, no una demostración ejecutable adicional.

Machine-readable comparison / Comparación procesable: [version-comparison.json](version-comparison.json). Original hashes / Hashes originales: [source-manifest.json](source-manifest.json).
