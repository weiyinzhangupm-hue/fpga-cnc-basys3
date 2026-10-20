; --- INICIO DEL CÍRCULO DE PRUEBA ---
; Diametro: 40mm | Centro: X=50, Y=50

; 1. PREPARACIÓN
G28
G0 Z10      ; Levantar el bolígrafo por seguridad
G0 X70 Y50  ; Moverse rápidamente al punto de inicio (X centro + Radio)
G1 Z0       ; Bajar el bolígrafo al papel

; 2. TRAZADO DEL CÍRCULO (Aproximación por segmentos pequeños)
G1 X69.70 Y53.47
G1 X68.79 Y56.84
G1 X67.32 Y60.00
G1 X65.32 Y62.86
G1 X62.86 Y65.32
G1 X60.00 Y67.32
G1 X56.84 Y68.79
G1 X53.47 Y69.70
G1 X50.00 Y70.00
G1 X46.53 Y69.70
G1 X43.16 Y68.79
G1 X40.00 Y67.32
G1 X37.14 Y65.32
G1 X34.68 Y62.86
G1 X32.68 Y60.00
G1 X31.21 Y56.84
G1 X30.30 Y53.47
G1 X30.00 Y50.00
G1 X30.30 Y46.53
G1 X31.21 Y43.16
G1 X32.68 Y40.00
G1 X34.68 Y37.14
G1 X37.14 Y34.68
G1 X40.00 Y32.68
G1 X43.16 Y31.21
G1 X46.53 Y30.30
G1 X50.00 Y30.00
G1 X53.47 Y30.30
G1 X56.84 Y31.21
G1 X60.00 Y32.68
G1 X62.86 Y34.68
G1 X65.32 Y37.14
G1 X67.32 Y40.00
G1 X68.79 Y43.16
G1 X69.70 Y46.53
G1 X70.00 Y50.00

; 3. RETIRADA
G0 Z10      ; Levantar el bolígrafo al terminar
G0 X0 Y0    ; Volver suavemente al punto de origen (Home)

; --- FIN DEL TRABAJO ---