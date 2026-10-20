----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 05.05.2026 20:42:59
-- Design Name: 
-- Module Name: tb_uart_tx - Behavioral
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

entity tb_uart_tx is
end entity;

architecture sim of tb_uart_tx is
    constant CLK_FREQ  : integer := 1000000; -- 1 MHz simulado
    constant BAUD_RATE : integer := 100000;  -- 100 kHz simulado
    constant BIT_PERIOD: time := 10 us;      -- 1 / 100kHz
    
    signal clk         : std_logic := '0';
    signal reset       : std_logic := '1';
    signal tx_start    : std_logic := '0';
    signal data_in     : std_logic_vector(7 downto 0) := (others => '0');
    signal tx          : std_logic;
    signal tx_done     : std_logic;

    -- Senales del Monitor Espia (Simula ser el PC recibiendo)
    signal spy_data    : std_logic_vector(7 downto 0) := (others => '0');
    signal spy_count   : integer := 0;

    -- Procedimiento para reportar errores
    procedure check(condition : boolean; message : string; variable errors : inout integer) is
    begin
        if not condition then 
            report "FAIL: " & message severity error; 
            errors := errors + 1; 
        end if;
    end procedure;

    -- Procedimiento para ordenar a la FPGA que transmita (pulso sincrono)
    procedure trigger_tx(value : std_logic_vector(7 downto 0); signal s_data: out std_logic_vector; signal s_start: out std_logic) is
    begin
        wait until rising_edge(clk);
        s_data <= value;
        s_start <= '1';
        wait until rising_edge(clk);
        s_start <= '0';
    end procedure;

begin
    -- Generador de Reloj
    clk <= not clk after 500 ns;

    -- Instanciamos tu transmisor UART
    dut : entity work.uart_tx
        generic map ( CLK_FREQ => CLK_FREQ, BAUD_RATE => BAUD_RATE )
        port map ( clk => clk, reset => reset, tx_start => tx_start, data_in => data_in,
                   tx => tx, tx_active => open, tx_done => tx_done );

    -- ========================================================
    -- PROCESO ESPIA: Decodifica la linea tx independientemente
    -- ========================================================
    process
        variable rx_byte : std_logic_vector(7 downto 0);
    begin
        loop
            wait until tx = '0'; -- Detecta el Start Bit fisico
            wait for BIT_PERIOD / 2; -- Nos movemos al centro del bit
            
            if tx = '0' then
                -- Leemos los 8 bits
                for i in 0 to 7 loop
                    wait for BIT_PERIOD;
                    rx_byte(i) := tx;
                end loop;
                
                -- Verificamos el Stop Bit
                wait for BIT_PERIOD;
                if tx = '1' then
                    spy_data <= rx_byte;
                    spy_count <= spy_count + 1;
                else
                    report "FAIL ESPIA: La FPGA no genero un Stop Bit correcto" severity error;
                end if;
            end if;
        end loop;
    end process;

    -- ========================================================
    -- PROCESO PRINCIPAL: Bateria de estimulos
    -- ========================================================
    process
        variable errors : integer := 0;
        variable initial_count : integer := 0;
    begin
        report "========================================";
        report "tb_uart_tx: Iniciando Bateria de Pruebas";
        report "========================================";
        wait for 2 us;
        reset <= '0';
        wait for 5 us;

        -- PRUEBA 1: Byte normal (0xAA = 10101010)
        report "--> Test 1: Byte alternante (0xAA)";
        trigger_tx(x"AA", data_in, tx_start);
        wait until spy_count = 1; 
        check(spy_data = x"AA", "Test 1 Fallo: El espia leyo un dato diferente", errors);
        wait for BIT_PERIOD; -- Margen de seguridad


        -- PRUEBA 2: Todo ceros
        report "--> Test 2: Byte todo ceros (0x00)";
        trigger_tx(x"00", data_in, tx_start);
        wait until spy_count = 2;
        check(spy_data = x"00", "Test 2 Fallo: El espia leyo un dato diferente", errors);
        wait for BIT_PERIOD;


        -- PRUEBA 3: Todo unos
        report "--> Test 3: Byte todo unos (0xFF)";
        trigger_tx(x"FF", data_in, tx_start);
        wait until spy_count = 3;
        check(spy_data = x"FF", "Test 3 Fallo: El espia leyo un dato diferente", errors);
        wait for BIT_PERIOD;


        -- PRUEBA 4: Interrupcion Indebida (Resistencia)
        -- Ordenamos enviar 0x55 e, inmediatamente en medio de la transmision, le ordenamos enviar 0x99
        report "--> Test 4: Intento de corromper un envio a medias";
        initial_count := spy_count;
        trigger_tx(x"55", data_in, tx_start);
        
        wait for BIT_PERIOD * 3; -- Esperamos 3 bits
        trigger_tx(x"99", data_in, tx_start); -- ATAQUE: Intentamos sobreescribir con 0x99
        
        wait until spy_count = initial_count + 1;
        check(spy_data = x"55", "Test 4 Fallo: La FPGA hizo caso a tx_start mientras estaba ocupada", errors);
        wait for BIT_PERIOD;


        -- PRUEBA 5: Rafaga / Back-to-Back
        -- Disparamos el siguiente byte en el mismo instante en el que avisa que ha terminado
        report "--> Test 5: Rafaga de envios sin descanso (0x11, 0x22, 0x33)";
        initial_count := spy_count;
        
        trigger_tx(x"11", data_in, tx_start);
        wait until tx_done = '1';
        
        trigger_tx(x"22", data_in, tx_start);
        wait until tx_done = '1';
        
        trigger_tx(x"33", data_in, tx_start);
        

        wait until spy_count = initial_count + 3;
        check(spy_data = x"33", "Test 5 Fallo: El ultimo byte de la rafaga se perdio o corrompio", errors);

        -- RESULTADO FINAL
        report "========================================";
        if errors = 0 then 
            report "tb_uart_tx: PASS - Tu transmisor funciona a la perfeccion"; 
        else 
            report "tb_uart_tx: FAIL - Se encontraron " & integer'image(errors) & " errores." severity failure; 
        end if;
        finish;
    end process;
end architecture;