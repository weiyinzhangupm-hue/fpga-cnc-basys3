# Controlador CNC FPGA — Basys3, VHDL y Vivado

**[English](README.md) · [Demostraciones](media/README.md) · [Comparación](docs/VERSION_COMPARISON.md) · [Validación](docs/VALIDATION.md)**

Proyecto académico de control coordinado de dos ejes para un plotter CNC. Un programa Python interpreta un subconjunto de G-code y envía órdenes por UART. La Basys3 realiza la interpolación de Bresenham, genera pulsos y señales de dirección, controla el servomotor del bolígrafo y procesa las entradas de los finales de carrera.

Se conservan **dos demostraciones complementarias**, cada una como proyecto independiente:

| Variante | Objetivo | Código |
|---|---|---|
| **Hardware y homing** | Conectar drivers, motores, servo y finales de carrera para observar el movimiento físico y la búsqueda del origen. | [`variants/hardware-homing`](variants/hardware-homing) |
| **Simulación de trayectoria VGA** | Mostrar en un monitor VGA la trayectoria simulada del movimiento sincronizado X/Y. Incorpora números de secuencia en UART y homing virtual para las demostraciones. | [`variants/vga-simulation`](variants/vga-simulation) |

«Simulación VGA» describe el objetivo de la demostración: se ejecuta en la FPGA y representa los pasos ordenados. No es un simulador exclusivamente de PC ni una medición de la posición real de los motores. **El homing virtual solo modifica G28; no desactiva las salidas de los motores durante otros movimientos.**

## Tecnologías y arquitectura

- **Placa:** Digilent Basys3, Artix-7 `xc7a35tcpg236-1`.
- **Diseño:** VHDL y AMD/Xilinx Vivado; preparación del proyecto comprobada con Vivado 2025.2.
- **Host:** Python 3 y `pyserial`; UART a **115200 baudios, 8N1**.
- **Movimiento:** interpolación Bresenham bidimensional y drivers TB6600 independientes para X e Y.
- **Periféricos:** servo tipo SG90/MG90S, finales de carrera X/Y y salida VGA en la variante de visualización.
- **Competencias:** integración hardware/software, máquinas de estados, generación coordinada de pulsos, comunicación serie e integración de periféricos FPGA.

El flujo es: **Python/G-code → UART → FSM → Bresenham → drivers X/Y**. La FSM también controla el servo y procesa los límites. En la variante VGA, los pasos calculados alimentan la representación de la trayectoria. El [README en inglés](README.md) incluye un diagrama.

## Vídeos del proyecto

| Montaje físico | Motores | Trayectoria VGA |
|---|---|---|
| [![Montaje](media/demo-01-preview.jpg)](media/demo-01.mp4) | [![Motores](media/demo-02-preview.jpg)](media/demo-02.mp4) | [![VGA](media/demo-03-preview.jpg)](media/demo-03.mp4) |
| [Vídeo · 6 s](media/demo-01.mp4) | [Vídeo · 23 s](media/demo-02.mp4) | [Vídeo · 33 s](media/demo-03.mp4) |

Los tres vídeos originales se incluyen sin modificaciones. No se ha identificado la revisión exacta del bitstream de cada grabación. GitHub puede ofrecer su descarga en lugar de reproducirlos. También se conserva el [póster original](media/project-poster.jpg); para las interfaces y el estado actual de validación, consultar el código y esta documentación.

## Organización del repositorio

```text
variants/
  hardware-homing/       Demostración original con periféricos físicos
  vga-simulation/        Demostración VGA original rapido_es_v3
scripts/                Creación portable de proyectos Vivado
docs/                   Comparación, hashes y estado de validación
media/                  Vídeos, fotogramas de vista previa y póster
```

Se mantienen sin cambios los **64 archivos originales de código, proyectos, ejemplos y documentación**. Se excluyen cachés, ejecuciones, checkpoints y resultados de simulación generados por Vivado. Hay 14 archivos idénticos entre las dos variantes: se conservan en ambas para que cada proyecto sea independiente. Los clientes Python y las implementaciones UART/FSM de distintas variantes no deben mezclarse. Consultar la [comparación detallada](docs/VERSION_COMPARISON.md).

## Crear el proyecto en Vivado

Desde la raíz del repositorio clonado, en una terminal con Vivado en `PATH`:

```powershell
vivado -mode batch -source scripts/create_project.tcl -tclargs hardware-homing
# O bien
vivado -mode batch -source scripts/create_project.tcl -tclargs vga-simulation
```

Abrir `build/<variante>/FPGA_CNC.xpr` y ejecutar síntesis, implementación y Generate Bitstream. El script importa el RTL, el XDC y los testbenches originales y selecciona `top_level` como módulo principal. Solo prepara el proyecto: no sintetiza ni programa la placa. Los testbenches tienen las limitaciones indicadas más abajo.

Los `.xpr` originales se conservan dentro de cada variante y pueden incluir rutas o referencias a cachés de la máquina de desarrollo. El script crea proyectos con rutas locales después de clonar. La asignación de pines está en `FPGA_CNC.srcs/constrs_1/imports/Tutorial/Basys3_Master.xdc` de cada variante.

La variante VGA también conserva su script de construcción original:

```powershell
cd variants/vga-simulation
vivado -mode batch -source build_bitstream.tcl
```

Su salida es `build/rapido_es_v3/top_level_cnc_rapido_es_v3.bit`. Programar el bitstream correspondiente mediante Hardware Manager. No se ha regenerado el bitstream ni programado hardware durante la publicación del repositorio.

## Demostración con motores físicos

1. Generar y programar el diseño **hardware-homing**.
2. Conectar los periféricos según su XDC y los requisitos eléctricos de los drivers utilizados. Comprobar masa común, sentido de giro y finales de carrera antes del homing.
3. Ajustar `PUERTO_SERIAL` en `variants/hardware-homing/cnc-python.py` (valor original: `COM8`) y calibrar `PASOS_POR_MM` (supuesto original: 20).
4. Ejecutar el menú interactivo:

```powershell
py -3 -m pip install -r requirements.txt
cd variants/hardware-homing
py -3 cnc-python.py
```

El menú ofrece pruebas de motores, servo y círculo, además del homing físico. El cliente espera una respuesta de finalización de un solo byte `K`. El homing solicita hasta 60.000 pasos negativos por eje: requiere finales de carrera funcionales y direcciones correctas. Es un prototipo académico; se conservan las limitaciones del host original.

## Demostración de trayectoria VGA

Programar el diseño **vga-simulation**, conectar un monitor VGA y usar el cliente Python de esa misma carpeta. Sustituir `COM14` por el puerto de la placa:

```powershell
py -3 -m pip install -r requirements.txt
cd variants/vga-simulation
py -3 cnc-python.py --port COM14 --link-test 100
py -3 cnc-python.py --port COM14 --homing virtual --servo-settle 0 rectangulo_vga_rapido.gcode
py -3 cnc-python.py --port COM14 --homing virtual --servo-settle 0 triangulo_vga_rapido.gcode
```

La lógica de movimiento sigue activa en la FPGA. Para una demostración exclusivamente visual, mantener desconectada la alimentación externa de los motores. Esta variante también ofrece homing físico, aunque aquí se presenta como demostración VGA.

El cliente VGA admite movimientos lineales G0/G1, G28, G90/G91 y subida/bajada del bolígrafo mediante Z. No implementa la velocidad F ni arcos G2/G3. `--motor-hz` estima los tiempos de espera del host; **no** cambia el reloj de la FPGA. Los 3000 Hz configurados frente a los 1000 Hz de la variante física son una diferencia de parámetros, no una medición del rendimiento global.

## Validación y limitaciones

- Pasaron las tres pruebas offline existentes del protocolo Python VGA: pérdida de respuesta final, reintento tras checksum erróneo y respuesta de una secuencia anterior.
- Los nueve archivos RTL de la variante VGA pasaron el análisis VHDL-2008 de Vivado.
- **No ha pasado una simulación completa:** `tb_fsm_main.vhd` usa `sequence`, palabra reservada, como parámetro; el testbench de integración todavía espera el formato antiguo de respuesta. Se conservan los originales para mantener la trazabilidad.
- Esta publicación no acredita una nueva síntesis, cierre de tiempos, programación de placa ni medición de precisión mecánica.
- El host físico puede actualizar su posición interna tras un timeout; el cambio de estado del bolígrafo introduce un paso X adicional. Una confirmación de finalización no mide la posición física. Véanse las [notas de validación](docs/VALIDATION.md).

El póster refleja la presentación original y sus afirmaciones históricas de validación; no es un informe de pruebas nuevo. La etiqueta «9-bit frame» debe contrastarse con el código: **órdenes de aplicación de 9 bytes transmitidas mediante UART 8N1**.

## Procedencia

Repositorio preparado para un portafolio de ingeniería a partir de las carpetas suministradas `FPGA_CNC - homing` y `FPGA_CNC_rapido_es_v3`. Se conserva el código y la documentación española original. Se añaden navegación bilingüe, comparación, vistas previas y un script de preparación de proyectos. No se añade una licencia nueva ni se atribuye autoría exclusiva.
