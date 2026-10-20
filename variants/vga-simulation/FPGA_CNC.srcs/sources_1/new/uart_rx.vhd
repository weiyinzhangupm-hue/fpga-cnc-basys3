----------------------------------------------------------------------------------
-- Receptor UART robusto para Basys3
-- 8 data bits, no parity, 1 stop bit (8N1)
-- Mejoras sobre la version original:
--   * sincronizador de tres etapas y filtro antiglitch de 3 muestras
--   * calculo redondeado de clocks por bit
--   * validacion del bit de parada y frame_error de un ciclo
--   * rx_ready de un ciclo solo para bytes validos
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_rx is
    Generic (
        CLK_FREQ  : positive := 100000000;
        BAUD_RATE : positive := 115200
    );
    Port (
        clk         : in  STD_LOGIC;
        reset       : in  STD_LOGIC;
        rx          : in  STD_LOGIC;
        data_out    : out STD_LOGIC_VECTOR(7 downto 0);
        rx_ready    : out STD_LOGIC;
        frame_error : out STD_LOGIC
    );
end uart_rx;

architecture Behavioral of uart_rx is

    function majority3(v : std_logic_vector(2 downto 0)) return std_logic is
    begin
        if (v(2) = '1' and v(1) = '1') or
           (v(2) = '1' and v(0) = '1') or
           (v(1) = '1' and v(0) = '1') then
            return '1';
        end if;
        return '0';
    end function;

    constant CLKS_PER_BIT : positive := (CLK_FREQ + (BAUD_RATE / 2)) / BAUD_RATE;
    constant HALF_BIT_CLKS : positive := CLKS_PER_BIT / 2;

    type t_state is (s_IDLE, s_START, s_DATA, s_STOP);
    signal r_state : t_state := s_IDLE;

    signal r_clk_count : natural range 0 to CLKS_PER_BIT - 1 := 0;
    signal r_bit_index : natural range 0 to 7 := 0;
    signal r_data      : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');

    signal r_rx_meta   : STD_LOGIC := '1';
    signal r_rx_sync_1 : STD_LOGIC := '1';
    signal r_rx_sync_2 : STD_LOGIC := '1';
    signal r_rx_hist   : STD_LOGIC_VECTOR(2 downto 0) := (others => '1');
    signal w_rx_clean  : STD_LOGIC;

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of r_rx_meta   : signal is "TRUE";
    attribute ASYNC_REG of r_rx_sync_1 : signal is "TRUE";
    attribute ASYNC_REG of r_rx_sync_2 : signal is "TRUE";

begin

    w_rx_clean <= majority3(r_rx_hist);

    process(clk, reset)
    begin
        if reset = '1' then
            r_state      <= s_IDLE;
            r_clk_count  <= 0;
            r_bit_index  <= 0;
            r_data       <= (others => '0');
            data_out     <= (others => '0');
            rx_ready     <= '0';
            frame_error  <= '0';
            r_rx_meta    <= '1';
            r_rx_sync_1  <= '1';
            r_rx_sync_2  <= '1';
            r_rx_hist    <= (others => '1');

        elsif rising_edge(clk) then
            -- Sincronizar la entrada serie asincrona antes de usarla.
            r_rx_meta   <= rx;
            r_rx_sync_1 <= r_rx_meta;
            r_rx_sync_2 <= r_rx_sync_1;
            r_rx_hist   <= r_rx_hist(1 downto 0) & r_rx_sync_2;

            rx_ready    <= '0';
            frame_error <= '0';

            case r_state is
                when s_IDLE =>
                    r_clk_count <= 0;
                    r_bit_index <= 0;

                    if w_rx_clean = '0' then
                        r_state <= s_START;
                    end if;

                when s_START =>
                    -- Validar el bit de arranque cerca de su centro.
                    if r_clk_count = HALF_BIT_CLKS - 1 then
                        r_clk_count <= 0;
                        if w_rx_clean = '0' then
                            r_state <= s_DATA;
                        else
                            r_state <= s_IDLE;
                        end if;
                    else
                        r_clk_count <= r_clk_count + 1;
                    end if;

                when s_DATA =>
                    -- Muestrear cada bit de datos cerca de su centro.
                    if r_clk_count = CLKS_PER_BIT - 1 then
                        r_clk_count         <= 0;
                        r_data(r_bit_index) <= w_rx_clean;

                        if r_bit_index = 7 then
                            r_bit_index <= 0;
                            r_state     <= s_STOP;
                        else
                            r_bit_index <= r_bit_index + 1;
                        end if;
                    else
                        r_clk_count <= r_clk_count + 1;
                    end if;

                when s_STOP =>
                    -- Una trama 8N1 valida debe tener el bit de parada en alto.
                    if r_clk_count = CLKS_PER_BIT - 1 then
                        r_clk_count <= 0;
                        if w_rx_clean = '1' then
                            data_out <= r_data;
                            rx_ready <= '1';
                        else
                            frame_error <= '1';
                        end if;
                        r_state <= s_IDLE;
                    else
                        r_clk_count <= r_clk_count + 1;
                    end if;

                when others =>
                    r_state <= s_IDLE;
            end case;
        end if;
    end process;

end Behavioral;
