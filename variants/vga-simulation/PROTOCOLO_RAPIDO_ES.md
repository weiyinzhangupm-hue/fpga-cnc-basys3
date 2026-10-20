# Protocolo UART fiable rapido_es_v3

## Comando PC -> FPGA, 9 bytes

| Byte | Campo | Significado |
|---:|---|---|
| 0 | SYNC | `0xAA` |
| 1 | Flags | bit0 `dir_x`, bit1 `dir_y`, bit2 `pen`, bit3 `homing` |
| 2 | X MSB | pasos X, 16 bits big-endian |
| 3 | X LSB | pasos X |
| 4 | Y MSB | pasos Y, 16 bits big-endian |
| 5 | Y LSB | pasos Y |
| 6 | Seq MSB | secuencia de 16 bits |
| 7 | Seq LSB | secuencia de 16 bits |
| 8 | XOR | XOR de bytes 0..7 |

## Respuesta FPGA -> PC, 5 bytes

| Byte | Campo | Significado |
|---:|---|---|
| 0 | SYNC | `0x55` |
| 1 | Estado | `A`, `R`, `K`, `B`, `C`, `F`, `T` |
| 2 | Seq MSB | secuencia respondida |
| 3 | Seq LSB | secuencia respondida |
| 4 | XOR | XOR de bytes 0..3 |

## Estados

- `A`: comando aceptado.
- `R`: comando en ejecución; reenviar la misma secuencia solo consulta estado.
- `K`: comando completado.
- `B`: FPGA ocupada con otra secuencia.
- `C`: checksum de comando incorrecto.
- `F`: error de framing UART.
- `T`: trama incompleta o separación excesiva entre bytes.

## Regla de seguridad

La FPGA guarda la secuencia activa y la última secuencia completada. Si el PC retransmite la misma secuencia, la FPGA responde con el estado actual o con el `K` en caché, pero no vuelve a iniciar el movimiento.
