# Basys3 CNC / VGA - versión rápida en español

Esta versión está pensada para reducir la espera inicial y acelerar el dibujo VGA sin sacrificar la seguridad del protocolo UART.

## Cambios principales

1. **Frecuencia de movimiento aumentada**
   - `top_level.vhd`: `SYS_MOT_FREQ = 3000` Hz.
   - `cnc-python.py`: `--motor-hz 3000` por defecto.
   - Una línea de 1200 pasos pasa de aproximadamente 1.2 s a 0.4 s.

2. **Reintento UART mucho más corto**
   - Antes: consultas separadas por cientos de ms.
   - Ahora: reintento inicial cada 30 ms y consulta de estado cada 50-200 ms.
   - La retransmisión usa la misma secuencia, por lo que no duplica movimientos.

3. **Homing virtual por defecto**
   - El `G28` limpia la pantalla VGA y pone X/Y a cero sin mover los motores.
   - Esto elimina la espera larga de búsqueda de finales de carrera cuando solo quieres ver el dibujo en VGA.
   - Para CNC físico real usa `--homing fisico`.

4. **Espera de servo reducida**
   - Por defecto `--servo-settle 0.05`.
   - Para solo VGA puedes usar `--servo-settle 0`.
   - Para un servo real usa `--servo-settle 0.5` a `0.8` según tu mecánica.

5. **Salida y comentarios en español**
   - Mensajes de Python, README, protocolo y comentarios importantes están en español.

## Uso rápido en Windows

```powershell
cd "C:\ruta\FPGA_CNC_rapido_es_v3"
py -3 -m pip install pyserial
py -3 .\cnc-python.py --port COM14 --link-test 100
py -3 .\cnc-python.py --port COM14 .\rectangulo_cnc_trace.gcode
```

Cambia `COM14` por el puerto real de la Basys3.

## Comando más rápido para previsualización VGA

```powershell
py -3 .\cnc-python.py --port COM14 --homing virtual --servo-settle 0 .\rectangulo_vga_rapido.gcode
```

También puedes escalar cualquier G-code sin editarlo:

```powershell
py -3 .\cnc-python.py --port COM14 --homing virtual --servo-settle 0 --scale 0.70 .\rectangulo_cnc_trace.gcode
```

## Uso con homing físico real

```powershell
py -3 .\cnc-python.py --port COM14 --homing fisico --servo-settle 0.6 .\rectangulo_cnc_trace.gcode
```

En modo físico, asegúrate de que los finales de carrera estén conectados y que la dirección de homing sea correcta.

## Generar bitstream

En Vivado Tcl Shell:

```tcl
cd {C:/ruta/FPGA_CNC_rapido_es_v3}
source build_bitstream.tcl
source program_basys3.tcl
```

Salida:

```text
build/rapido_es_v3/top_level_cnc_rapido_es_v3.bit
```

## Pruebas recomendadas

1. Generar y programar el bitstream nuevo.
2. Ejecutar:

```powershell
py -3 .\cnc-python.py --port COM14 --link-test 100
```

3. Ejecutar el rectángulo rápido:

```powershell
py -3 .\cnc-python.py --port COM14 --homing virtual --servo-settle 0 .\rectangulo_vga_rapido.gcode
```

4. Ejecutar el triángulo rápido:

```powershell
py -3 .\cnc-python.py --port COM14 --homing virtual --servo-settle 0 .\triangulo_vga_rapido.gcode
```

## Nota de seguridad

El protocolo evita que una retransmisión ejecute dos veces el mismo movimiento. Sin embargo, la precisión física de motores reales también depende de alimentación, aceleración, carga mecánica, microstepping y finales de carrera. Para solo VGA, el modo rápido es seguro. Para máquina física real, sube la velocidad gradualmente y baja `SYS_MOT_FREQ` si notas pérdida de pasos.
