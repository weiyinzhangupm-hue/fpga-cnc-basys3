----------------------------------------------------------------------------------
-- Transmisor UART robusto para Basys3, 8N1
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_tx is
    Generic (
        CLK_FREQ  : positive := 100000000;
        BAUD_RATE : positive := 115200
    );
    Port (
        clk       : in  STD_LOGIC;
        reset     : in  STD_LOGIC;
        tx_start  : in  STD_LOGIC;
        data_in   : in  STD_LOGIC_VECTOR(7 downto 0);
        tx        : out STD_LOGIC;
        tx_active : out STD_LOGIC;
        tx_done   : out STD_LOGIC
    );
end uart_tx;

architecture Behavioral of uart_tx is

    constant CLKS_PER_BIT : positive := (CLK_FREQ + (BAUD_RATE / 2)) / BAUD_RATE;

    type t_state is (s_IDLE, s_START, s_DATA, s_STOP);
    signal r_state : t_state := s_IDLE;

    signal r_clk_count : natural range 0 to CLKS_PER_BIT - 1 := 0;
    signal r_bit_index : natural range 0 to 7 := 0;
    signal r_data      : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');

begin

    process(clk, reset)
    begin
        if reset = '1' then
            r_state     <= s_IDLE;
            r_clk_count <= 0;
            r_bit_index <= 0;
            r_data      <= (others => '0');
            tx           <= '1';
            tx_active    <= '0';
            tx_done      <= '0';

        elsif rising_edge(clk) then
            tx_done <= '0';

            case r_state is
                when s_IDLE =>
                    tx           <= '1';
                    tx_active    <= '0';
                    r_clk_count  <= 0;
                    r_bit_index  <= 0;

                    if tx_start = '1' then
                        r_data   <= data_in;
                        tx_active <= '1';
                        r_state  <= s_START;
                    end if;

                when s_START =>
                    tx        <= '0';
                    tx_active <= '1';

                    if r_clk_count = CLKS_PER_BIT - 1 then
                        r_clk_count <= 0;
                        r_state     <= s_DATA;
                    else
                        r_clk_count <= r_clk_count + 1;
                    end if;

                when s_DATA =>
                    tx        <= r_data(r_bit_index);
                    tx_active <= '1';

                    if r_clk_count = CLKS_PER_BIT - 1 then
                        r_clk_count <= 0;
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
                    tx        <= '1';
                    tx_active <= '1';

                    if r_clk_count = CLKS_PER_BIT - 1 then
                        r_clk_count <= 0;
                        tx_done     <= '1';
                        r_state     <= s_IDLE;
                    else
                        r_clk_count <= r_clk_count + 1;
                    end if;

                when others =>
                    r_state <= s_IDLE;
            end case;
        end if;
    end process;

end Behavioral;
