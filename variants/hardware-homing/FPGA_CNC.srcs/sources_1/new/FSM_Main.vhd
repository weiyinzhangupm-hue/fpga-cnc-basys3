----------------------------------------------------------------------------------
-- Módulo: FSM_Main - Behavioral (Con soporte de Homing)
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fsm_main is
    Port (
        clk          : in  STD_LOGIC;
        reset        : in  STD_LOGIC;

        -- Interfaz con el Receptor UART (Oídos)
        rx_data      : in  STD_LOGIC_VECTOR(7 downto 0);
        rx_ready     : in  STD_LOGIC;

        -- Interfaz con el Transmisor UART (Boca)
        tx_data      : out STD_LOGIC_VECTOR(7 downto 0);
        tx_start     : out STD_LOGIC;

        -- Interfaz con el Generador de Movimiento (Bresenham) y el Bolígrafo (PWM)
        dir_x        : out STD_LOGIC;
        dir_y        : out STD_LOGIC;
        pen_state    : out STD_LOGIC;        -- 0 = Boli Arriba, 1 = Boli Abajo
        pen_update   : out STD_LOGIC;        -- Pulso para avisar al módulo PWM de un cambio
        steps_x      : out STD_LOGIC_VECTOR(15 downto 0);
        steps_y      : out STD_LOGIC_VECTOR(15 downto 0);
        start_motion : out STD_LOGIC;
        motion_done  : in  STD_LOGIC;
        
        -- ¡NUEVO! Señal para indicar que estamos haciendo Homing
        is_homing    : out STD_LOGIC
    );
end fsm_main;

architecture Behavioral of fsm_main is
    type t_state is (IDLE, RECEIVE, CHECK_CRC, EXECUTE, DONE);
    signal r_state : t_state := IDLE;

    type t_buffer is array (0 to 8) of std_logic_vector(7 downto 0);
    signal r_rx_buffer : t_buffer := (others => (others => '0'));
    signal r_byte_count : integer range 0 to 8 := 0;
    
    signal r_calc_checksum : std_logic_vector(7 downto 0) := (others => '0');
begin

    process(clk, reset)
    begin
        if reset = '1' then
            r_state <= IDLE;
            tx_start <= '0';
            start_motion <= '0';
            pen_update <= '0';
            is_homing <= '0'; -- Lo apagamos por seguridad en el reset
        elsif rising_edge(clk) then
            -- Valores por defecto (pulsos de 1 ciclo)
            tx_start <= '0';
            pen_update <= '0';

            case r_state is
                when IDLE =>
                    r_byte_count <= 0;
                    r_calc_checksum <= x"00"; -- Reset del calculo
                    if rx_ready = '1' and rx_data = x"AA" then
                        r_rx_buffer(0) <= rx_data;
                        r_calc_checksum <= x"AA"; -- Empezamos XOR con el SYNC
                        r_byte_count <= 1;
                        r_state <= RECEIVE;
                    end if;

                when RECEIVE =>
                    if rx_ready = '1' then
                        r_rx_buffer(r_byte_count) <= rx_data;
                        -- Si es uno de los primeros 8 bytes, lo incluimos en nuestro XOR
                        if r_byte_count < 8 then
                            r_calc_checksum <= r_calc_checksum xor rx_data;
                        end if;

                        if r_byte_count = 8 then
                            r_state <= CHECK_CRC;
                        else
                            r_byte_count <= r_byte_count + 1;
                        end if;
                    end if;

                when CHECK_CRC =>
                    -- Comparamos lo calculado (bytes 0-7) con el byte 8 (el enviado por PC)
                    if r_calc_checksum = r_rx_buffer(8) then
                        -- TODO CORRECTO: Extraemos datos
                        dir_x     <= r_rx_buffer(1)(0);
                        dir_y     <= r_rx_buffer(1)(1);
                        pen_state <= r_rx_buffer(1)(2);
                        is_homing <= r_rx_buffer(1)(3); -- ¡NUEVO! Extraemos el bit 3 (Homing)
                        
                        steps_x   <= r_rx_buffer(2) & r_rx_buffer(3);
                        steps_y   <= r_rx_buffer(4) & r_rx_buffer(5);
                        
                        pen_update <= '1';   -- Actualizamos servo
                        start_motion <= '1'; -- Iniciamos motores
                        r_state <= EXECUTE;
                    else
                        -- ERROR DE CHECKSUM: Ignoramos y volvemos a esperar Sync
                        r_state <= IDLE;
                    end if;

                when EXECUTE =>
                    start_motion <= '0'; -- Bajamos el pulso de arranque
                    if motion_done = '1' then
                        r_state <= DONE;
                    end if;

                when DONE =>
                    tx_data <= x"4B"; -- Letra 'K' de OK
                    tx_start <= '1';
                    r_state <= IDLE;

            end case;
        end if;
    end process;
end Behavioral;