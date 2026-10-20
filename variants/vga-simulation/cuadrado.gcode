; --- INICIO TEST DE CALIBRACIÓN: CUADRADO CON DIAGONALES ---
; Tamaño: 40x40mm | Inicio: X=10, Y=10

; 1. PREPARACIÓN Y HOMING
G28         ; Buscar el cero físico exacto de la máquina
G0 Z10      ; Levantar el bolígrafo por seguridad
G0 X10 Y10  ; Moverse rápidamente al punto de inicio (esquina inferior izquierda)

; 2. DIBUJAR EL CONTORNO (Líneas rectas)
G1 Z0       ; Bajar el bolígrafo al papel
G1 X50 Y10  ; Dibujar línea inferior (hacia la derecha)
G1 X50 Y50  ; Dibujar línea derecha (hacia arriba)
G1 X10 Y50  ; Dibujar línea superior (hacia la izquierda)
G1 X10 Y10  ; Dibujar línea izquierda (hacia abajo, cerrando el cuadrado)

; 3. PRIMERA DIAGONAL
G1 X50 Y50  ; Dibujar diagonal desde abajo-izquierda hasta arriba-derecha

; 4. REPOSICIONAMIENTO PARA LA SEGUNDA DIAGONAL
G0 Z10      ; Levantar el bolígrafo
G0 X10 Y50  ; Mover el cabezal por el aire hasta la esquina arriba-izquierda
G1 Z0       ; Bajar el bolígrafo
G1 X50 Y10  ; Dibujar diagonal hacia abajo-derecha

; 5. RETIRADA FINAL
G0 Z10      ; Levantar el bolígrafo
G0 X0 Y0    ; Volver suavemente al origen para despejar el papel

; --- FIN DEL TRABAJO ---