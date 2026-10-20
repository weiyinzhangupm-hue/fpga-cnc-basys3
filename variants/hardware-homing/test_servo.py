import serial
import time

# ==========================================
# CONFIGURACIÓN
# ==========================================
PUERTO_SERIAL = 'COM8'  # Asegúrate de que es tu puerto
BAUDIOS = 115200

print(f"Conectando a {PUERTO_SERIAL}...")
ser = serial.Serial(PUERTO_SERIAL, BAUDIOS, timeout=5)
time.sleep(2) # Tiempo vital para que la FPGA respire tras conectar
print("¡Conectado!")

def enviar_servo(bajar_boli):
    # Trama manual: Solo enviamos el bit del Servo, 0 pasos.
    byte1 = (1 << 2) if bajar_boli else 0
    trama = [0xAA, byte1, 0, 0, 0, 0, 0, 0]
    
    # Checksum manual
    checksum = 0
    for b in trama: 
        checksum ^= b
    trama.append(checksum)
    
    # Enviar un micropaso invisible en X para desbloquear Bresenham
    trama[3] = 1 
    trama[8] ^= 1 
    
    ser.write(bytes(trama))
    ser.read(1) # Esperar la 'K' de la placa

try:
    print("\n[ FASE 1 ] BOLI ARRIBA (Centro)")
    print("Multímetro debería estabilizarse en ~165 mV (o 250 mV si cambiaste a 1500us)")
    enviar_servo(False)
    time.sleep(4) # 4 SEGUNDOS DE ESPERA FÍSICA

    print("\n[ FASE 2 ] BOLI ABAJO (Giro a la derecha)")
    print("Multímetro debería subir y estabilizarse en ~330 mV")
    enviar_servo(True)
    time.sleep(4)

    print("\n[ FASE 3 ] VOLVER ARRIBA")
    enviar_servo(False)
    time.sleep(2)

    print("\nTest superado.")

except Exception as e:
    print(f"Error: {e}")
finally:
    ser.close()