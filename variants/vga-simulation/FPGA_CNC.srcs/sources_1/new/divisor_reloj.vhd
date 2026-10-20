----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 29.04.2026 21:29:48
-- Design Name: 
-- Module Name: divisor_reloj - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL; -- Usamos numeric_std para contadores matemáticos

entity divisor_reloj is
    Generic (
        CLK_FREQ    : integer := 100000000; -- Frecuencia de la Basys 3 (100 MHz)
        BAUD_RATE   : integer := 115200;    -- Velocidad del puerto Serial
        MOTOR_FREQ  : integer := 50000      -- Frecuencia de actualización motores (50 kHz)
    );
    Port ( 
        clk         : in  STD_LOGIC;
        reset       : in  STD_LOGIC;
        tick_uart   : out STD_LOGIC;        -- Pulso para leer/escribir serial
        tick_motor  : out STD_LOGIC         -- Pulso para la máquina de motores
    );
end divisor_reloj;

architecture Behavioral of divisor_reloj is

    -- Constantes calculadas automáticamente por VHDL al compilar
    constant LIMIT_UART  : integer := CLK_FREQ / BAUD_RATE;
    constant LIMIT_MOTOR : integer := CLK_FREQ / MOTOR_FREQ;

    -- Señales internas para los contadores
    signal counter_uart  : integer range 0 to LIMIT_UART - 1 := 0;
    signal counter_motor : integer range 0 to LIMIT_MOTOR - 1 := 0;

begin

    -- Proceso para generar el pulso del UART
    process(clk, reset)
    begin
        if reset = '1' then
            counter_uart <= 0;
            tick_uart <= '0';
        elsif rising_edge(clk) then
            if counter_uart = LIMIT_UART - 1 then
                counter_uart <= 0;
                tick_uart <= '1'; -- Lanzamos el pulso de 1 ciclo
            else
                counter_uart <= counter_uart + 1;
                tick_uart <= '0'; -- Lo mantenemos a 0 el resto del tiempo
            end if;
        end if;
    end process;

    -- Proceso para generar el pulso de los Motores
    process(clk, reset)
    begin
        if reset = '1' then
            counter_motor <= 0;
            tick_motor <= '0';
        elsif rising_edge(clk) then
            if counter_motor = LIMIT_MOTOR - 1 then
                counter_motor <= 0;
                tick_motor <= '1'; -- Lanzamos el pulso de 1 ciclo
            else
                counter_motor <= counter_motor + 1;
                tick_motor <= '0'; -- Lo mantenemos a 0 el resto del tiempo
            end if;
        end if;
    end process;

end Behavioral;
