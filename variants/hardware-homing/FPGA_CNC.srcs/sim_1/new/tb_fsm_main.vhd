----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 05.05.2026 20:41:55
-- Design Name: 
-- Module Name: tb_fsm_main - Behavioral
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

entity tb_fsm_main is
end entity;

architecture sim of tb_fsm_main is
    signal clk          : std_logic := '0';
    signal reset        : std_logic := '1';
    signal rx_data      : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_ready     : std_logic := '0';
    signal tx_data      : std_logic_vector(7 downto 0);
    signal tx_start     : std_logic;
    signal dir_x, dir_y : std_logic;
    signal pen_state    : std_logic;
    signal pen_update   : std_logic;
    signal steps_x      : std_logic_vector(15 downto 0);
    signal steps_y      : std_logic_vector(15 downto 0);
    signal start_motion : std_logic;
    signal motion_done  : std_logic := '0';

    procedure check(condition : boolean; message : string; variable errors : inout integer) is
    begin
        if not condition then
            report "FAIL: " & message severity error;
            errors := errors + 1;
        end if;
    end procedure;

    procedure send_byte(data : std_logic_vector(7 downto 0); signal r_data: out std_logic_vector; signal r_ready: out std_logic) is
    begin
        wait until rising_edge(clk);
        r_data <= data;
        r_ready <= '1';
        wait until rising_edge(clk);
        r_ready <= '0';
    end procedure;

begin
    clk <= not clk after 5 ns;

    dut : entity work.fsm_main
        port map (
            clk => clk, reset => reset, rx_data => rx_data, rx_ready => rx_ready,
            tx_data => tx_data, tx_start => tx_start, dir_x => dir_x, dir_y => dir_y,
            pen_state => pen_state, pen_update => pen_update, steps_x => steps_x, steps_y => steps_y,
            start_motion => start_motion, motion_done => motion_done
        );

    process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "tb_fsm_main: Iniciando Bateria (9 Bytes)";
        report "========================================";
        wait for 50 ns;
        reset <= '0';
        wait for 50 ns;

        -- ========================================================
        -- TEST 1: Trama valida normal con Checksum
        -- ========================================================
        report "--> Test 1: Trama valida";
        send_byte(x"AA", rx_data, rx_ready); -- Sync
        send_byte(x"05", rx_data, rx_ready); -- Config
        send_byte(x"00", rx_data, rx_ready); -- X High
        send_byte(x"0A", rx_data, rx_ready); -- X Low = 10
        send_byte(x"00", rx_data, rx_ready); -- Y High
        send_byte(x"0B", rx_data, rx_ready); -- Y Low = 11
        send_byte(x"00", rx_data, rx_ready); -- Z High
        send_byte(x"00", rx_data, rx_ready); -- Z Low
        send_byte(x"AE", rx_data, rx_ready); -- CHECKSUM (AA^05^00^0A^00^0B^00^00 = AE)
        
        wait until start_motion = '1';
        check(dir_x = '1', "Test 1 Fallo: dir_x incorrecto", errors);
        check(dir_y = '0', "Test 1 Fallo: dir_y incorrecto", errors);
        check(pen_state = '1', "Test 1 Fallo: pen_state incorrecto", errors);
        check(to_integer(unsigned(steps_x)) = 10, "Test 1 Fallo: steps_x incorrecto", errors);
        check(to_integer(unsigned(steps_y)) = 11, "Test 1 Fallo: steps_y incorrecto", errors);
        
        wait for 50 ns; motion_done <= '1'; wait for 10 ns; motion_done <= '0';
        wait until tx_start = '1';
        check(tx_data = x"4B", "Test 1 Fallo: No devolvio la letra K", errors);
        wait for 50 ns;

        -- ========================================================
        -- TEST 2: Checksum Invalido (Rechazo de trama)
        -- ========================================================
        report "--> Test 2: Checksum Invalido";
        send_byte(x"AA", rx_data, rx_ready); 
        send_byte(x"05", rx_data, rx_ready); 
        send_byte(x"00", rx_data, rx_ready); 
        send_byte(x"0A", rx_data, rx_ready); 
        send_byte(x"00", rx_data, rx_ready); 
        send_byte(x"0B", rx_data, rx_ready); 
        send_byte(x"00", rx_data, rx_ready); 
        send_byte(x"00", rx_data, rx_ready); 
        send_byte(x"FF", rx_data, rx_ready); -- CHECKSUM ERRONEO (Deberia ser AE)
        
        wait for 200 ns;
        check(start_motion = '0', "Test 2 Fallo: La FSM acepto un Checksum corrupto", errors);

        -- ========================================================
        -- TEST 3: Basura antes de trama valida
        -- ========================================================
        report "--> Test 3: Basura antes de trama valida";
        send_byte(x"FF", rx_data, rx_ready); -- Basura
        send_byte(x"33", rx_data, rx_ready); -- Basura
        
        send_byte(x"AA", rx_data, rx_ready); 
        send_byte(x"02", rx_data, rx_ready); 
        send_byte(x"00", rx_data, rx_ready);
        send_byte(x"05", rx_data, rx_ready); 
        send_byte(x"00", rx_data, rx_ready);
        send_byte(x"05", rx_data, rx_ready); 
        send_byte(x"00", rx_data, rx_ready);
        send_byte(x"00", rx_data, rx_ready);
        send_byte(x"A8", rx_data, rx_ready); -- CHECKSUM (AA^02^00^05^00^05^00^00 = A8)

        wait until start_motion = '1';
        check(dir_y = '1', "Test 3 Fallo: dir_y no se recupero", errors);
        check(to_integer(unsigned(steps_x)) = 5, "Test 3 Fallo: steps_x corrupto", errors);
        
        wait for 50 ns; motion_done <= '1'; wait for 10 ns; motion_done <= '0';
        wait until tx_start = '1';
        wait for 50 ns;

        -- ========================================================
        -- TEST 4: Trama con zero pasos (Solo Boli) - SALTO A DONE
        -- ========================================================
        report "--> Test 4: Trama con zero pasos (Solo Boli)";
        send_byte(x"AA", rx_data, rx_ready); 
        send_byte(x"04", rx_data, rx_ready); -- Pen=1
        send_byte(x"00", rx_data, rx_ready); send_byte(x"00", rx_data, rx_ready); 
        send_byte(x"00", rx_data, rx_ready); send_byte(x"00", rx_data, rx_ready); 
        send_byte(x"00", rx_data, rx_ready); send_byte(x"00", rx_data, rx_ready); 
        send_byte(x"AE", rx_data, rx_ready); -- CHECKSUM (AA^04 = AE)
        
        wait until start_motion = '1' or tx_start = '1';
        wait for 10 ns; 
        
        check(to_integer(unsigned(steps_x)) = 0, "Test 4 Fallo: steps_x no es 0", errors);
        check(pen_state = '1', "Test 4 Fallo: Boli no bajo", errors);
        
        if start_motion = '1' then
            wait for 50 ns; motion_done <= '1'; wait for 10 ns; motion_done <= '0';
            wait until tx_start = '1';
        end if;
        wait for 50 ns;

        -- ========================================================
        -- TEST 5: Tramas en rafaga (Frame A y Frame B)
        -- ========================================================
        report "--> Test 5: Tramas en rafaga";
        
        send_byte(x"AA", rx_data, rx_ready); send_byte(x"00", rx_data, rx_ready);
        send_byte(x"00", rx_data, rx_ready); send_byte(x"01", rx_data, rx_ready);
        send_byte(x"00", rx_data, rx_ready); send_byte(x"01", rx_data, rx_ready);
        send_byte(x"00", rx_data, rx_ready); send_byte(x"00", rx_data, rx_ready);
        send_byte(x"AA", rx_data, rx_ready); -- CHECKSUM (AA^01^01 = AA)
        
        wait until start_motion = '1';
        wait for 20 ns; motion_done <= '1'; wait for 10 ns; motion_done <= '0';
        wait until tx_start = '1';
        wait for 20 ns;
        
        send_byte(x"AA", rx_data, rx_ready); send_byte(x"00", rx_data, rx_ready);
        send_byte(x"00", rx_data, rx_ready); send_byte(x"07", rx_data, rx_ready);
        send_byte(x"00", rx_data, rx_ready); send_byte(x"08", rx_data, rx_ready);
        send_byte(x"00", rx_data, rx_ready); send_byte(x"00", rx_data, rx_ready);
        send_byte(x"A5", rx_data, rx_ready); -- CHECKSUM (AA^07^08 = A5)
        
        wait until start_motion = '1';
        check(to_integer(unsigned(steps_x)) = 7, "Test 5 Fallo: steps_x del Frame B incorrecto", errors);
        wait for 20 ns; motion_done <= '1'; wait for 10 ns; motion_done <= '0';
        wait until tx_start = '1';

        -- RESULTADO FINAL
        report "========================================";
        if errors = 0 then
            report "tb_fsm_main: PASS - La FSM procesa Checksums perfectamente";
        else
            report "tb_fsm_main: FAIL con " & integer'image(errors) & " errores" severity failure;
        end if;
        finish;
    end process;
end architecture;