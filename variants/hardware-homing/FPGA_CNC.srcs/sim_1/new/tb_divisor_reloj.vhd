----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 05.05.2026 20:46:06
-- Design Name: 
-- Module Name: tb_divisor_reloj - Behavioral
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


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_divisor_reloj is
end entity;

architecture sim of tb_divisor_reloj is
    constant SYS_CLK  : integer := 100000000; -- 100 MHz
    constant BAUD     : integer := 115200;
    constant MOTOR_HZ : integer := 50000;

    -- Tiempos esperados
    constant CLK_PER  : time := 10 ns;
    constant PER_MOT  : time := 20 us;
    constant PER_UART : time := 8680 ns; -- 868 ciclos de reloj exactos

    signal clk        : std_logic := '0';
    signal reset      : std_logic := '1';
    signal tick_uart  : std_logic;
    signal tick_motor : std_logic;

    -- Monitores espias para comprobar la independencia
    signal count_u    : integer := 0;
    signal count_m    : integer := 0;

    procedure check(condition : boolean; message : string; variable errors : inout integer) is
    begin
        if not condition then 
            report "FAIL: " & message severity error; 
            errors := errors + 1; 
        end if;
    end procedure;

begin
    -- Generador principal a 100 MHz
    clk <= not clk after 5 ns;

    dut : entity work.divisor_reloj
        generic map ( CLK_FREQ => SYS_CLK, BAUD_RATE => BAUD, MOTOR_FREQ => MOTOR_HZ )
        port map ( clk => clk, reset => reset, tick_uart => tick_uart, tick_motor => tick_motor );

    -- ========================================================
    -- PROCESO ESPÍA: Cuenta pulsos en paralelo
    -- ========================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                count_u <= 0;
                count_m <= 0;
            else
                if tick_uart = '1' then count_u <= count_u + 1; end if;
                if tick_motor = '1' then count_m <= count_m + 1; end if;
            end if;
        end if;
    end process;

    -- ========================================================
    -- PROCESO PRINCIPAL: Bateria de pruebas
    -- ========================================================
    process
        variable errors : integer := 0;
        variable t_start, t_end : time;
        variable pulse_width : time;
        variable snap_u, snap_m : integer;
    begin
        report "========================================";
        report "tb_divisor_reloj: Iniciando Bateria";
        report "========================================";

        -- TEST 1: Comportamiento del Reset
        report "--> Test 1: El reset mantiene todo a cero";
        reset <= '1';
        wait for 100 ns;
        check(tick_uart = '0' and tick_motor = '0', "Test 1 Fallo: Los ticks no estan en reposo durante el reset", errors);
        
        -- Soltamos el reset
        reset <= '0';


        -- TEST 2: Frecuencia y ancho del Tick del Motor
        report "--> Test 2: Tick Motor (Frecuencia y 1 ciclo de ancho)";
        wait until tick_motor = '1';
        t_start := now;
        
        wait until tick_motor = '0';
        pulse_width := now - t_start;
        check(pulse_width = CLK_PER, "Test 2 Fallo: El pulso del motor no dura exactamente 10 ns", errors);
        
        wait until tick_motor = '1';
        t_end := now;
        check((t_end - t_start) = PER_MOT, "Test 2 Fallo: Periodo del motor incorrecto (esperado 20 us)", errors);


        -- TEST 3: Frecuencia y ancho del Tick de la UART
        report "--> Test 3: Tick UART (Frecuencia y 1 ciclo de ancho)";
        wait until tick_uart = '1';
        t_start := now;
        
        wait until tick_uart = '0';
        pulse_width := now - t_start;
        check(pulse_width = CLK_PER, "Test 3 Fallo: El pulso de UART no dura exactamente 10 ns", errors);
        
        wait until tick_uart = '1';
        t_end := now;
        check((t_end - t_start) = PER_UART, "Test 3 Fallo: Periodo de UART incorrecto (esperado 8680 ns)", errors);


        -- TEST 4: Independencia (Corremos el tiempo y comprobamos conteos paralelos)
        report "--> Test 4: Independencia de canales (Carrera de 100 us)";
        snap_m := count_m;
        snap_u := count_u;
        
        -- Dejamos que el reloj corra libre durante 100 microsegundos
        wait for 100 us;
        
        -- Matematicas esperadas en 100 us:
        -- Motor: 100us / 20us = 5 pulsos
        -- UART:  100000ns / 8680ns = 11.52 (entre 11 y 12 pulsos)
        check((count_m - snap_m) = 5, "Test 4 Fallo: El canal del motor se detuvo o interfirio", errors);
        check((count_u - snap_u) = 11 or (count_u - snap_u) = 12, "Test 4 Fallo: El canal UART perdio el ritmo", errors);


        -- RESULTADO FINAL
        report "========================================";
        if errors = 0 then 
            report "tb_divisor_reloj: PASS - Relojes sincronizados, independientes y precisos"; 
        else 
            report "tb_divisor_reloj: FAIL con " & integer'image(errors) & " errores" severity failure; 
        end if;
        finish;
    end process;
end architecture;