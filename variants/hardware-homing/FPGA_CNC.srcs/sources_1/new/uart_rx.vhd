----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 29.04.2026 21:37:35
-- Design Name: 
-- Module Name: uart_rx - Behavioral
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
use IEEE.NUMERIC_STD.ALL;

entity uart_rx is
    Generic (
        CLK_FREQ     : integer := 100000000; -- Reloj de la Basys 3
        BAUD_RATE    : integer := 115200     -- Velocidad en baudios
    );
    Port (
        clk          : in  STD_LOGIC;
        reset        : in  STD_LOGIC;
        rx           : in  STD_LOGIC;        -- Pin físico de recepción (del USB)
        data_out     : out STD_LOGIC_VECTOR (7 downto 0); -- El byte recibido
        rx_ready     : out STD_LOGIC         -- Pulso de 1 ciclo cuando el byte está listo
    );
end uart_rx;

architecture Behavioral of uart_rx is

    -- Cálculo de los ciclos de reloj por cada bit enviado
    constant CLKS_PER_BIT : integer := CLK_FREQ / BAUD_RATE;

    -- Definición de los estados de la Máquina de Estados
    type t_SM_Main is (s_IDLE, s_START, s_DATA, s_STOP);
    signal r_SM_Main : t_SM_Main := s_IDLE;

    -- Registros internos
    signal r_Clk_Count : integer range 0 to CLKS_PER_BIT - 1 := 0;
    signal r_Bit_Index : integer range 0 to 7 := 0;  -- Para contar los 8 bits
    signal r_Data      : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');

begin

    process(clk, reset)
    begin
        if reset = '1' then
            r_SM_Main   <= s_IDLE;
            r_Clk_Count <= 0;
            r_Bit_Index <= 0;
            rx_ready    <= '0';
            data_out    <= (others => '0');
        elsif rising_edge(clk) then
            
            case r_SM_Main is
                
                -- ESTADO 1: Reposo, esperando que la línea baje a 0 (Start Bit)
                when s_IDLE =>
                    rx_ready <= '0';
                    r_Clk_Count <= 0;
                    r_Bit_Index <= 0;
                    
                    if rx = '0' then
                        r_SM_Main <= s_START;
                    else
                        r_SM_Main <= s_IDLE;
                    end if;
                    
                -- ESTADO 2: Confirmar el Start Bit leyendo en el centro del pulso
                when s_START =>
                    if r_Clk_Count = (CLKS_PER_BIT - 1) / 2 then
                        if rx = '0' then
                            r_Clk_Count <= 0;
                            r_SM_Main   <= s_DATA;
                        else
                            r_SM_Main   <= s_IDLE; -- Falsa alarma (ruido)
                        end if;
                    else
                        r_Clk_Count <= r_Clk_Count + 1;
                        r_SM_Main   <= s_START;
                    end if;
                    
                -- ESTADO 3: Leer los 8 bits de datos
                when s_DATA =>
                    if r_Clk_Count = CLKS_PER_BIT - 1 then
                        r_Clk_Count            <= 0;
                        r_Data(r_Bit_Index) <= rx; -- Guardamos el bit recibido
                        
                        -- Verificamos si ya leímos los 8 bits
                        if r_Bit_Index = 7 then
                            r_Bit_Index <= 0;
                            r_SM_Main   <= s_STOP;
                        else
                            r_Bit_Index <= r_Bit_Index + 1;
                            r_SM_Main   <= s_DATA;
                        end if;
                    else
                        r_Clk_Count <= r_Clk_Count + 1;
                        r_SM_Main   <= s_DATA;
                    end if;
                    
                -- ESTADO 4: Bit de Parada (Stop Bit)
                when s_STOP =>
                    -- Esperamos el tiempo de un bit entero
                    if r_Clk_Count = CLKS_PER_BIT - 1 then
                        r_Clk_Count <= 0;
                        rx_ready    <= '1';       -- ¡Avisamos que el byte está listo!
                        data_out    <= r_Data; -- Entregamos el byte
                        r_SM_Main   <= s_IDLE;
                    else
                        r_Clk_Count <= r_Clk_Count + 1;
                        r_SM_Main   <= s_STOP;
                    end if;
                    
                when others =>
                    r_SM_Main <= s_IDLE;
                    
            end case;
        end if;
    end process;

end Behavioral;
