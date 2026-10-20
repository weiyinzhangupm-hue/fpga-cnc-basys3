----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 04.05.2026 17:47:45
-- Design Name: 
-- Module Name: tb_top_level - Behavioral
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

entity tb_top_level is
end entity;

architecture sim of tb_top_level is
    constant SYS_CLK_FREQ : integer := 1000000;
    constant SYS_BAUD     : integer := 100000; 
    constant CLKS_PER_BIT : integer := SYS_CLK_FREQ / SYS_BAUD;

    signal clk        : std_logic := '0';
    signal reset      : std_logic := '1';
    signal rx         : std_logic := '1';
    signal tx         : std_logic;
    signal step_x     : std_logic;
    signal dir_x      : std_logic;
    signal step_y     : std_logic;
    signal dir_y      : std_logic;
    signal limit_x    : std_logic := '0';
    signal limit_y    : std_logic := '0';
    signal servo_pwm  : std_logic;
    
    signal count_x    : integer := 0;
    signal count_y    : integer := 0;
    signal clr_counts : std_logic := '0';
    
    signal tx_spy_data  : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_spy_ready : std_logic := '0';

    procedure check(condition : boolean; message : string; variable errors : inout integer) is
    begin
        if not condition then
            report "FAIL: " & message severity error;
            errors := errors + 1;
        end if;
    end procedure;

begin
    clk <= not clk after 500 ns; 

    dut : entity work.top_level
        generic map ( SYS_CLK_FREQ => SYS_CLK_FREQ, SYS_BAUD => SYS_BAUD, SYS_MOT_FREQ => 50000 )
        port map (
            clk => clk, reset => reset, rx => rx, tx => tx,
            step_x => step_x, dir_x => dir_x, step_y => step_y, dir_y => dir_y,
            limit_x => limit_x, limit_y => limit_y, servo_pwm => servo_pwm
        );

    -- MONITOR DE PASOS
    process(clk)
        variable last_step_x : std_logic := '0';
        variable last_step_y : std_logic := '0';
    begin
        if rising_edge(clk) then
            if reset = '1' or clr_counts = '1' then
                count_x <= 0;
                count_y <= 0;
                last_step_x := '0';
                last_step_y := '0';
            else
                if step_x = '1' and last_step_x = '0' then count_x <= count_x + 1; end if;
                if step_y = '1' and last_step_y = '0' then count_y <= count_y + 1; end if;
                last_step_x := step_x;
                last_step_y := step_y;
            end if;
        end if;
    end process;

    -- ESPIA TX
    process
    begin
        loop
            wait until tx = '0'; 
            wait for 5 us;       
            if tx = '0' then
                for i in 0 to 7 loop
                    wait for 10 us; 
                    tx_spy_data(i) <= tx;
                end loop;
                wait for 10 us; 
                tx_spy_ready <= '1';
                wait for 1 us;
                tx_spy_ready <= '0';
            end if;
        end loop;
    end process;

    -- PROCESO PRINCIPAL
    process
        variable errors : integer := 0;
        variable t_start, t_end : time;
        
        procedure uart_send_byte(value : std_logic_vector(7 downto 0)) is
        begin
            rx <= '0'; 
            wait for 10 us;
            for bit_index in 0 to 7 loop
                rx <= value(bit_index);
                wait for 10 us;
            end loop;
            rx <= '1'; 
            wait for 10 us;
        end procedure;

    begin
        report "========================================";
        report "tb_top_level: Integracion con Checksum";
        report "========================================";
        wait for 2 us;
        reset <= '0';
        wait for 10 us;

        -- TEST 1: Movimiento Normal
        report "--> Test 1: Diagonal X=5, Y=3";
        clr_counts <= '1'; wait for 2 us; clr_counts <= '0';
        
        uart_send_byte(x"AA"); uart_send_byte(x"06"); 
        uart_send_byte(x"00"); uart_send_byte(x"05"); 
        uart_send_byte(x"00"); uart_send_byte(x"03"); 
        uart_send_byte(x"00"); uart_send_byte(x"00");
        uart_send_byte(x"AA"); -- CHECKSUM (AA^06^05^03 = AA)

        wait until tx_spy_ready = '1';  
        
        check(tx_spy_data = x"4B", "Test 1 Fallo: La FPGA no devolvio la K (0x4B)", errors);
        check(count_x = 5, "Test 1 Fallo: Pasos X incorrectos", errors);
        check(count_y = 3, "Test 1 Fallo: Pasos Y incorrectos", errors);
        wait for 50 us;

        -- TEST 2: Sync falso 
        report "--> Test 2: Sync Falso";
        clr_counts <= '1'; wait for 2 us; clr_counts <= '0';
        
        uart_send_byte(x"55"); uart_send_byte(x"01"); uart_send_byte(x"00"); uart_send_byte(x"10");
        uart_send_byte(x"00"); uart_send_byte(x"10"); uart_send_byte(x"00"); uart_send_byte(x"00");
        uart_send_byte(x"54"); -- Checksum
        
        wait for 200 us; 
        check(count_x = 0 and count_y = 0, "Test 2 Fallo: La maquina se movio", errors);

        -- TEST 3: Final de Carrera
        report "--> Test 3: Interrupcion por Final de Carrera";
        clr_counts <= '1'; wait for 2 us; clr_counts <= '0';
        
        uart_send_byte(x"AA"); uart_send_byte(x"01"); 
        uart_send_byte(x"00"); uart_send_byte(x"64"); 
        uart_send_byte(x"00"); uart_send_byte(x"00"); 
        uart_send_byte(x"00"); uart_send_byte(x"00");
        uart_send_byte(x"CF"); -- CHECKSUM (AA^01^64 = CF)
        
        wait for 100 us; 
        limit_x <= '1'; 
        wait for 50 us;
        limit_x <= '0';
        
        wait until tx_spy_ready = '1'; 
        
        
        check(count_x > 0, "Test 3 Fallo: La maquina no llego a arrancar", errors);
        check(count_x < 100, "Test 3 Fallo: La maquina no se detuvo", errors);

        -- TEST 4: Modificacion del Servo PWM
        report "--> Test 4: Verificacion fisica del Servo PWM y ACK";
        
        uart_send_byte(x"AA"); uart_send_byte(x"00"); 
        uart_send_byte(x"00"); uart_send_byte(x"00"); 
        uart_send_byte(x"00"); uart_send_byte(x"00"); 
        uart_send_byte(x"00"); uart_send_byte(x"00");
        uart_send_byte(x"AA"); -- CHECKSUM
        
        wait until tx_spy_ready = '1';
        check(tx_spy_data = x"4B", "Test 4 Fallo: No hubo K al actualizar servo", errors);
        
        wait until servo_pwm = '0';
        
        wait until servo_pwm = '1';
        t_start := now;
        wait until servo_pwm = '0';
        t_end := now;
        check((t_end - t_start) = 100 us or (t_end - t_start) = 1000 us, "Test 4 Fallo: PWM incorrecto", errors);
       
        wait for 50 us;

        -- TEST 5: Movimientos consecutivos
        report "--> Test 5: Multiples tramas consecutivas";
        clr_counts <= '1'; wait for 2 us; clr_counts <= '0';
        
        -- Trama 1: X=2, Y=0
        uart_send_byte(x"AA"); uart_send_byte(x"01"); 
        uart_send_byte(x"00"); uart_send_byte(x"02"); 
        uart_send_byte(x"00"); uart_send_byte(x"00"); 
        uart_send_byte(x"00"); uart_send_byte(x"00");
        uart_send_byte(x"A9"); -- CHECKSUM (AA^01^02 = A9)
        wait until tx_spy_ready = '1';
        check(count_x = 2, "Test 5a Fallo: Trama 1 incorrecta", errors);
        
        -- Trama 2: X=0, Y=3
        clr_counts <= '1'; wait for 2 us; clr_counts <= '0';
        uart_send_byte(x"AA"); uart_send_byte(x"02"); 
        uart_send_byte(x"00"); uart_send_byte(x"00"); 
        uart_send_byte(x"00"); uart_send_byte(x"03"); 
        uart_send_byte(x"00"); uart_send_byte(x"00");
        uart_send_byte(x"AB"); -- CHECKSUM (AA^02^03 = AB)
        wait until tx_spy_ready = '1';
        check(count_y = 3, "Test 5b Fallo: Trama 2 incorrecta", errors);

        report "========================================";
        if errors = 0 then
            report "tb_top_level: PASS - LA INTEGRACION ES UN EXITO ABSOLUTO";
        else
            report "tb_top_level: FAIL con " & integer'image(errors) & " errores" severity failure;
        end if;
        finish;
    end process;
end architecture;