# Informe de cambios: versión rápida en español

## Problema observado

El sistema ya dibujaba correctamente desde Python, pero algunos ACK `K` no llegaban o llegaban tarde. El protocolo fiable anterior solucionaba la pérdida de paquetes, pero aún tenía esperas demasiado largas para uso interactivo.

## Causa principal de la lentitud

- Intervalo de reconsulta demasiado alto.
- Esperas fijas de servo innecesarias para previsualización VGA.
- `G28` físico al inicio de los archivos, que podía esperar finales de carrera aunque solo se quisiera limpiar la pantalla.
- Frecuencia de movimiento de 1000 Hz, correcta pero lenta para mostrar trayectorias.

## Solución aplicada

### 1. Reintento rápido sin duplicar movimientos

El PC reenvía la misma secuencia cada 30 ms hasta recibir `A` o `R`. Como la FPGA reconoce secuencias repetidas, el movimiento no se ejecuta dos veces.

### 2. Consulta corta si se pierde `K`

Tras recibir `A`/`R`, el PC espera el `K` automático. Si se pierde, reconsulta con la misma secuencia cada 50-200 ms.

### 3. Homing virtual por defecto

`G28` ahora puede limpiar la VGA con un homing de cero pasos. Esto dispara `trace_clear`, reinicia coordenadas y evita la espera de los finales de carrera. El homing físico sigue disponible con `--homing fisico`.

### 4. Velocidad de interpolación aumentada

`SYS_MOT_FREQ` cambió de 1000 Hz a 3000 Hz. El dibujo VGA se acelera unas 3 veces sin cambiar la resolución de 20 pasos/mm.

### 5. Versión española

Mensajes de Python, documentación y comentarios importantes están en español.

## Parámetros recomendados

Para VGA solamente:

```powershell
py -3 .\cnc-python.py --port COM14 --homing virtual --servo-settle 0 .\rectangulo_vga_rapido.gcode
```

Para CNC físico:

```powershell
py -3 .\cnc-python.py --port COM14 --homing fisico --servo-settle 0.6 .\rectangulo_cnc_trace.gcode
```

## Límites

El protocolo protege contra duplicación por retransmisión y contra ACK atrasados. La precisión física absoluta de una máquina real sigue dependiendo de motores, drivers, alimentación, aceleración y mecánica. Si el motor pierde pasos por exceso de velocidad, baja `SYS_MOT_FREQ` y `--motor-hz` al mismo valor.
