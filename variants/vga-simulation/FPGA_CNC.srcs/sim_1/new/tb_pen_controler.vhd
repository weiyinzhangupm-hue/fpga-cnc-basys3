----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 05.05.2026 20:44:39
-- Design Name: 
-- Module Name: tb_pen_controler - Behavioral
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

entity tb_pen_controller is
end entity;

architecture sim of tb_pen_controller is
    constant CLK_FREQ  : integer := 1000000; -- 1 MHz simulado (1 tick = 1 us)
    constant PWM_HZ    : integer := 500;     -- Periodo = 2 ms = 2000 us
    
    constant PULSE_UP  : time := 100 us;
    constant PULSE_DN  : time := 200 us;
    constant PERIOD    : time := 2000 us;
    
    signal clk         : std_logic := '0';
    signal reset       : std_logic := '1';
    signal update      : std_logic := '0';
    signal pen_down_cmd: std_logic := '0';
    signal servo_pwm   : std_logic;
    signal pen_is_down : std_logic; -- Ahora si conectamos el pin de estado
    
    procedure check(condition : boolean; message : string; variable errors : inout integer) is
    begin
        if not condition then 
            report "FAIL: " & message severity error; 
            errors := errors + 1; 
        end if;
    end procedure;

begin
    clk <= not clk after 500 ns; -- 1 us de periodo

    dut : entity work.pen_controller
        generic map ( CLK_FREQ_HZ => CLK_FREQ, PWM_HZ => PWM_HZ, PULSE_UP_US => 100, PULSE_DOWN_US => 200 )
        port map ( clk => clk, reset => reset, update => update, pen_down_cmd => pen_down_cmd,
                   servo_pwm => servo_pwm, pen_is_down => pen_is_down );

    process
        variable errors : integer := 0;
        variable t_start, t_end, t_period_start, t_period_end : time;
        variable pulse_width : time;
        variable period_width : time;
    begin
        report "========================================";
        report "tb_pen_controller: Iniciando Bateria";
        report "========================================";
        wait for 2 us;
        reset <= '0';
        wait for 5 us;

        -- ========================================================
        -- TEST 1: Pulso DOWN correcto (200 us) y pen_is_down
        -- ========================================================
        report "--> Test 1: Bajar el boligrafo (DOWN, 200 us)";
        pen_down_cmd <= '1';
        update <= '1';
        wait for 1 us;
        update <= '0';

        wait until servo_pwm = '1';
        t_start := now;
        t_period_start := now; -- Guardamos este timestamp para el Test 2
        wait until servo_pwm = '0';
        t_end := now;

        pulse_width := t_end - t_start;
        check(pulse_width = PULSE_DN, "Test 1 Fallo: Ancho de pulso DOWN incorrecto", errors);
        check(pen_is_down = '1', "Test 1 Fallo: Senal pen_is_down no es 1", errors);


        -- ========================================================
        -- TEST 2: Frecuencia del periodo PWM (500 Hz = 2000 us)
        -- ========================================================
        report "--> Test 2: Verificando periodo de 500 Hz (2000 us)";
        wait until servo_pwm = '1';
        t_period_end := now;
        period_width := t_period_end - t_period_start;
        check(period_width = PERIOD, "Test 2 Fallo: Periodo PWM incorrecto", errors);


        -- ========================================================
        -- TEST 3: Pulso UP correcto (100 us) y pen_is_down
        -- ========================================================
        report "--> Test 3: Subir el boligrafo (UP, 100 us)";
        wait until servo_pwm = '0'; -- Esperamos a que la senal caiga a reposo
        wait for 10 us;             -- Margen de seguridad
        pen_down_cmd <= '0';
        update <= '1';
        wait for 1 us;
        update <= '0';

        wait until servo_pwm = '1';
        t_start := now;
        wait until servo_pwm = '0';
        t_end := now;

        pulse_width := t_end - t_start;
        check(pulse_width = PULSE_UP, "Test 3 Fallo: Ancho de pulso UP incorrecto", errors);
        check(pen_is_down = '0', "Test 3 Fallo: Senal pen_is_down no es 0", errors);


        -- ========================================================
        -- TEST 4: Update ignorado durante pulso activo (Proteccion)
        -- ========================================================
        report "--> Test 4: Intento de corrupcion en pleno pulso ALTO";
        wait until servo_pwm = '1';
        t_start := now;
        
        wait for 50 us; -- Justo a la mitad del pulso (de 100us)
        pen_down_cmd <= '1'; -- Intentamos forzar DOWN (200us) de golpe
        update <= '1';
        wait for 1 us;
        update <= '0';

        wait until servo_pwm = '0';
        t_end := now;

        pulse_width := t_end - t_start;
        -- Deberia seguir siendo UP (100 us) porque no debe alargar el pulso en caliente
        check(pulse_width = PULSE_UP, "Test 4 Fallo: El pulso se corrompio. No ignoro el update", errors);


        -- ========================================================
        -- TEST 5: Cambio dinamico (UP -> DOWN -> UP rapidamente)
        -- ========================================================
        report "--> Test 5: Cambios dinamicos de ordenes rapidas";
        
        -- Comprobamos si la orden DOWN que mandamos a traicion en el Test 4 aplico para ESTE ciclo
        wait until servo_pwm = '1';
        t_start := now;
        wait until servo_pwm = '0';
        t_end := now;
        pulse_width := t_end - t_start;
        check(pulse_width = PULSE_DN, "Test 5a Fallo: No aplico el DOWN del Test 4 al siguiente ciclo", errors);

        -- Mandamos UP inmediatamente en el tiempo de reposo
        pen_down_cmd <= '0';
        update <= '1';
        wait for 1 us;
        update <= '0';
        
        wait until servo_pwm = '1';
        t_start := now;
        wait until servo_pwm = '0';
        t_end := now;
        pulse_width := t_end - t_start;
        check(pulse_width = PULSE_UP, "Test 5b Fallo: No volvio a UP rapidamente", errors);


        -- RESULTADO FINAL
        report "========================================";
        if errors = 0 then 
            report "tb_pen_controller: PASS - El controlador de servomotores es solido como una roca"; 
        else 
            report "tb_pen_controller: FAIL - Se encontraron " & integer'image(errors) & " errores." severity failure; 
        end if;
        finish;
    end process;
end architecture;