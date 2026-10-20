----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 04.05.2026 17:26:09
-- Design Name: 
-- Module Name: uart_tx - Behavioral
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

entity uart_tx is
    Generic (
        CLK_FREQ     : integer := 100000000; -- Reloj de la Basys 3
        BAUD_RATE    : integer := 115200     -- Velocidad en baudios
    );
    Port (
        clk          : in  STD_LOGIC;
        reset        : in  STD_LOGIC;
        
        -- Interfaz con el Cerebro (FSM_Main)
        tx_start     : in  STD_LOGIC;        -- Pulso que ordena iniciar la transmisión
        data_in      : in  STD_LOGIC_VECTOR (7 downto 0); -- El byte a enviar
        
        -- Pin físico y señales de estado
        tx           : out STD_LOGIC;        -- Pin físico de transmisión (hacia el USB)
        tx_active    : out STD_LOGIC;        -- Indica si el módulo está ocupado enviando
        tx_done      : out STD_LOGIC         -- Pulso de 1 ciclo cuando termina de enviar
    );
end uart_tx;

architecture Behavioral of uart_tx is

    -- Cálculo de los ciclos de reloj por cada bit enviado
    constant CLKS_PER_BIT : integer := CLK_FREQ / BAUD_RATE;

    -- Máquina de Estados
    type t_SM_Main is (s_IDLE, s_START, s_DATA, s_STOP);
    signal r_SM_Main : t_SM_Main := s_IDLE;

    -- Registros internos
    signal r_Clk_Count : integer range 0 to CLKS_PER_BIT - 1 := 0;
    signal r_Bit_Index : integer range 0 to 7 := 0;
    
    -- Latch (candado) para el dato de entrada
    signal r_Data      : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');

begin

    process(clk, reset)
    begin
        if reset = '1' then
            r_SM_Main   <= s_IDLE;
            r_Clk_Count <= 0;
            r_Bit_Index <= 0;
            tx          <= '1'; -- La línea UART en reposo SIEMPRE es 1
            tx_active   <= '0';
            tx_done     <= '0';
            r_Data      <= (others => '0');
            
        elsif rising_edge(clk) then
            
            tx_done <= '0'; -- Por defecto es 0, solo será 1 durante un ciclo al terminar
            
            case r_SM_Main is
                
                -- ESTADO 1: Reposo, esperando la orden de disparo
                when s_IDLE =>
                    tx          <= '1'; 
                    r_Clk_Count <= 0;
                    r_Bit_Index <= 0;
                    tx_active   <= '0';
                    
                    if tx_start = '1' then
                        r_Data    <= data_in; -- Guardamos el dato por si la entrada cambia a mitad de envío
                        tx_active <= '1';
                        r_SM_Main <= s_START;
                    end if;
                    
                -- ESTADO 2: Start Bit (bajamos la línea a 0)
                when s_START =>
                    tx <= '0'; 
                    
                    -- Esperamos el tiempo de 1 bit completo
                    if r_Clk_Count = CLKS_PER_BIT - 1 then
                        r_Clk_Count <= 0;
                        r_SM_Main   <= s_DATA;
                    else
                        r_Clk_Count <= r_Clk_Count + 1;
                    end if;
                    
                -- ESTADO 3: Enviar los 8 bits de datos
                when s_DATA =>
                    tx <= r_Data(r_Bit_Index); -- Sacamos el bit correspondiente al pin físico
                    
                    if r_Clk_Count = CLKS_PER_BIT - 1 then
                        r_Clk_Count <= 0;
                        
                        -- Verificamos si enviamos los 8 bits
                        if r_Bit_Index = 7 then
                            r_Bit_Index <= 0;
                            r_SM_Main   <= s_STOP;
                        else
                            r_Bit_Index <= r_Bit_Index + 1;
                        end if;
                    else
                        r_Clk_Count <= r_Clk_Count + 1;
                    end if;
                    
                -- ESTADO 4: Stop Bit (volvemos a poner la línea a 1)
                when s_STOP =>
                    tx <= '1'; 
                    
                    if r_Clk_Count = CLKS_PER_BIT - 1 then
                        r_Clk_Count <= 0;
                        tx_done     <= '1'; -- Avisamos que ya terminamos
                        r_SM_Main   <= s_IDLE;
                    else
                        r_Clk_Count <= r_Clk_Count + 1;
                    end if;
                    
                when others =>
                    r_SM_Main <= s_IDLE;
                    
            end case;
        end if;
    end process;

end Behavioral;