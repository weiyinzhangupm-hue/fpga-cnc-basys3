----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 05.05.2026 20:43:55
-- Design Name: 
-- Module Name: tb_uart_rx - Behavioral
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

entity tb_uart_rx is
end entity;

architecture sim of tb_uart_rx is
    constant CLK_FREQ  : integer := 1000000;
    constant BAUD_RATE : integer := 100000;
    constant BIT_PERIOD: time := 10 us;
    
    signal clk         : std_logic := '0';
    signal reset       : std_logic := '1';
    signal rx          : std_logic := '1';
    signal data_out    : std_logic_vector(7 downto 0);
    signal rx_ready    : std_logic;

    -- Señales del Monitor Espía
    signal rx_capture_data  : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_capture_count : integer := 0;

    -- Procedimiento para reportar errores
    procedure check(condition : boolean; message : string; variable errors : inout integer) is
    begin
        if not condition then 
            report "FAIL: " & message severity error; 
            errors := errors + 1; 
        end if;
    end procedure;

    -- Procedimiento 1: Enviar un byte perfecto
    procedure send_serial_byte(value : std_logic_vector(7 downto 0); signal r_rx: out std_logic) is
    begin
        r_rx <= '0'; -- Start bit
        wait for BIT_PERIOD;
        for i in 0 to 7 loop
            r_rx <= value(i); -- Data bits
            wait for BIT_PERIOD;
        end loop;
        r_rx <= '1'; -- Stop bit
        wait for BIT_PERIOD;
    end procedure;

    -- Procedimiento 2: Enviar un byte con interferencias (Glitch)
    -- Inyecta un micro-corte a '0' en los bits que deberían ser '1', 
    -- pero se recupera antes de llegar al centro del bit (donde lee la FPGA).
    procedure send_noisy_byte(value : std_logic_vector(7 downto 0); signal r_rx: out std_logic) is
    begin
        r_rx <= '0'; -- Start bit
        wait for BIT_PERIOD;
        for i in 0 to 7 loop
            if value(i) = '1' then
                r_rx <= '1';
                wait for BIT_PERIOD / 4;
                r_rx <= '0'; -- ¡GLITCH! (Ruido parásito)
                wait for BIT_PERIOD / 8;
                r_rx <= '1'; -- Recuperación de la línea
                wait for BIT_PERIOD * 5 / 8;
            else
                r_rx <= '0';
                wait for BIT_PERIOD;
            end if;
        end loop;
        r_rx <= '1'; -- Stop bit
        wait for BIT_PERIOD;
    end procedure;

begin
    clk <= not clk after 500 ns;

    -- Instanciación del módulo a probar
    dut : entity work.uart_rx
        generic map ( CLK_FREQ => CLK_FREQ, BAUD_RATE => BAUD_RATE)
        port map ( clk => clk, reset => reset, rx => rx, data_out => data_out, rx_ready => rx_ready );

    -- PROCESO MONITOR: Captura los bytes en cuanto salen de la FPGA
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                rx_capture_count <= 0;
            elsif rx_ready = '1' then
                rx_capture_data <= data_out;
                rx_capture_count <= rx_capture_count + 1;
            end if;
        end if;
    end process;


    -- PROCESO DE PRUEBAS PRINCIPAL
    process
        variable errors : integer := 0;
        variable count_snapshot : integer := 0;
    begin
        report "========================================";
        report "tb_uart_rx: Iniciando Bateria de Pruebas";
        report "========================================";
        wait for 2 us;
        reset <= '0';
        wait for 5 us;

        -- PRUEBA 1: Byte correcto normal
        report "--> Test 1: Byte normal (0xAA)";
        send_serial_byte(x"AA", rx);
        wait for 1 us; -- Margen de seguridad
        check(rx_capture_data = x"AA", "Test 1 Fallo: Dato incorrecto", errors);
        check(rx_capture_count = 1, "Test 1 Fallo: Contador no incrementó", errors);


        -- PRUEBA 2: Start bit falso (Pulso muy corto)
        -- Simulamos un bajón de tensión en la línea que no llega a ser un Start Bit real
        report "--> Test 2: Start bit falso (Glitch de reposo)";
        count_snapshot := rx_capture_count;
        rx <= '0';
        wait for BIT_PERIOD / 4; -- Muy corto, el módulo lee en BIT_PERIOD/2
        rx <= '1';
        wait for BIT_PERIOD * 2; -- Esperamos a ver si la FPGA se confunde
        check(rx_capture_count = count_snapshot, "Test 2 Fallo: La FPGA trago un falso start bit", errors);


        -- PRUEBA 3: Byte todo ceros (0x00)
        report "--> Test 3: Byte todo ceros (0x00)";
        send_serial_byte(x"00", rx);
        wait for 1 us;
        check(rx_capture_data = x"00", "Test 3 Fallo: No puede leer 0x00", errors);


        -- PRUEBA 4: Byte todo unos (0xFF)
        report "--> Test 4: Byte todo unos (0xFF)";
        send_serial_byte(x"FF", rx);
        wait for 1 us;
        check(rx_capture_data = x"FF", "Test 4 Fallo: No puede leer 0xFF", errors);


        -- PRUEBA 5: Ruido en la línea (Glitch)
        -- Se envían microcortes durante la transmisión, pero la FPGA debería ignorarlos
        report "--> Test 5: Byte con ruido electromagnetico (0x55)";
        send_noisy_byte(x"55", rx);
        wait for 1 us;
        check(rx_capture_data = x"55", "Test 5 Fallo: El receptor no supero la prueba de ruido", errors);


        -- PRUEBA 6: Múltiples bytes seguidos (Ráfaga / Back-to-back)
        -- Enviamos 3 bytes sin ningún tiempo de reposo entre el Stop de uno y el Start del otro
        report "--> Test 6: Rafaga de multiples bytes (0x11, 0x22, 0x33)";
        
        send_serial_byte(x"11", rx);
        check(rx_capture_data = x"11", "Test 6 Fallo en el Byte 1", errors);
        
        send_serial_byte(x"22", rx);
        check(rx_capture_data = x"22", "Test 6 Fallo en el Byte 2", errors);
        
        send_serial_byte(x"33", rx);
        check(rx_capture_data = x"33", "Test 6 Fallo en el Byte 3", errors);

        
        -- RESULTADO FINAL
        report "========================================";
        if errors = 0 then 
            report "tb_uart_rx:  PASS - ¡Tu modulo es INDESTRUCTIBLE!"; 
        else 
            report "tb_uart_rx:  FAIL - Se encontraron " & integer'image(errors) & " errores." severity failure; 
        end if;
        finish;
    end process;
end architecture;
