; ==========================================
; TEST DE BRESENHAM - MOVIMIENTO SIMULTÁNEO
; ==========================================
; Preparación: Pon ambos carros en X=0, Y=0.
; Asegúrate de tener al menos 100mm libres en cada eje.

; 1. Dibujar el contorno de un cuadrado de 100x100
G0 X100 Y0
G0 X100 Y100
G0 X0 Y100
G0 X0 Y0

; 2. Dibujar la primera diagonal (Arriba-Derecha)
G0 X100 Y100

; 3. Bajar por el lateral para posicionarse para la segunda diagonal
G0 X100 Y0

; 4. Dibujar la segunda diagonal (Arriba-Izquierda)
G0 X0 Y100

; 5. Volver al origen directo (Abajo-Izquierda)
G0 X0 Y0

; Fin del test