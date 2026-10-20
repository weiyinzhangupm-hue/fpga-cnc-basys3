----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 05.05.2026 20:41:04
-- Design Name: 
-- Module Name: tb_bresenham_2d - Behavioral
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

entity tb_bresenham_2d is
end entity;

architecture sim of tb_bresenham_2d is
    signal clk          : std_logic := '0';
    signal reset        : std_logic := '1';
    signal tick_motor   : std_logic := '0';
    signal start_motion : std_logic := '0';
    signal abort_motion : std_logic := '0';
    signal steps_x      : std_logic_vector(15 downto 0) := (others => '0');
    signal steps_y      : std_logic_vector(15 downto 0) := (others => '0');
    signal step_x       : std_logic;
    signal step_y       : std_logic;
    signal motion_done  : std_logic;
    
    signal count_x      : integer := 0;
    signal count_y      : integer := 0;

    procedure check(condition : boolean; message : string; variable errors : inout integer) is
    begin
        if not condition then
            report "FAIL: " & message severity error;
            errors := errors + 1;
        end if;
    end procedure;

begin
    clk <= not clk after 5 ns; -- Reloj de 100 MHz

    -- Generador artificial del tick del motor (cada 100 ns para simular rápido)
    process
    begin
        wait for 95 ns;
        tick_motor <= '1';
        wait for 10 ns;
        tick_motor <= '0';
    end process;

    dut : entity work.bresenham_2d
        port map (
            clk => clk, reset => reset, tick_motor => tick_motor,
            start_motion => start_motion, abort_motion => abort_motion,
            steps_x => steps_x, steps_y => steps_y,
            step_x => step_x, step_y => step_y, motion_done => motion_done
        );

    -- Contador de pasos generados (CORREGIDO PARA EVITAR MULTIPLE DRIVERS)
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                count_x <= 0;
                count_y <= 0;
            else
                if step_x = '1' then count_x <= count_x + 1; end if;
                if step_y = '1' then count_y <= count_y + 1; end if;
            end if;
        end if;
    end process;

    process
        variable errors : integer := 0;
    begin
        report "tb_bresenham_2d: Iniciando pruebas";
        wait for 50 ns;
        reset <= '0';
        wait for 100 ns;

        -- PRUEBA 1: Movimiento Normal (5 pasos en X, 3 en Y)
        steps_x <= std_logic_vector(to_unsigned(5, 16));
        steps_y <= std_logic_vector(to_unsigned(3, 16));
        start_motion <= '1';
        wait for 10 ns;
        start_motion <= '0';
        
        wait until motion_done = '1';
        check(count_x = 5, "Fallo Prueba 1: Pasos X incorrectos", errors);
        check(count_y = 3, "Fallo Prueba 1: Pasos Y incorrectos", errors);
        
        -- PRUEBA 2: Freno de emergencia (Abortar)
        -- En lugar de forzar count_x a 0, aplicamos un reset limpio al sistema
        reset <= '1'; 
        wait for 50 ns;
        reset <= '0';
        wait for 50 ns;
        
        steps_x <= std_logic_vector(to_unsigned(100, 16));
        steps_y <= std_logic_vector(to_unsigned(100, 16));
        start_motion <= '1';
        wait for 10 ns;
        start_motion <= '0';
        
        wait for 300 ns; -- Dejamos que de un par de pasos
        abort_motion <= '1'; -- Activamos final de carrera
        wait for 10 ns;
        abort_motion <= '0';
        
        wait until motion_done = '1';
        check(count_x < 100, "Fallo Prueba 2: No se detuvo a tiempo", errors);

        if errors = 0 then
            report "tb_bresenham_2d: PASS";
        else
            report "tb_bresenham_2d: FAIL con " & integer'image(errors) & " errores" severity failure;
        end if;
        finish;
    end process;
end architecture;