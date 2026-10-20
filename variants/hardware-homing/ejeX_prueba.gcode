; ==========================================
; TEST DE CALIBRACIÓN - SOLO EJE X
; ==========================================
; Preparación: Pon el carro X a la izquierda del todo a mano.
; Ese punto donde lo dejes será considerado el X=0.

; 1. Pequeño toque (10 mm a la derecha)
G0 X10

; 2. Volver al origen
G0 X0

; 3. Recorrido medio (50 mm a la derecha)
G0 X50

; 4. Volver al origen
G0 X0

; 5. Recorrido largo y retorno (100 mm)
G0 X100
G0 X0

; Fin del test