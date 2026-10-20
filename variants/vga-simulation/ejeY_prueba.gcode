; ==========================================
; TEST DE CALIBRACIÓN - SOLO EJE Y
; ==========================================
; Preparación: Pon el carro Y en su posición inicial (Y=0) a mano.

; 1. Pequeño toque adelante (10 mm)
G0 Y10

; 2. Volver al origen
G0 Y0

; 3. Recorrido medio (50 mm)
G0 Y50

; 4. Volver al origen
G0 Y0

; 5. Recorrido largo y retorno (100 mm)
G0 Y100
G0 Y0

; Fin del test