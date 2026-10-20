library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_fsm_main is
end entity;

architecture sim of tb_fsm_main is
    constant CLK_PERIOD : time := 10 ns;

    signal clk          : std_logic := '0';
    signal reset        : std_logic := '1';
    signal rx_data      : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_ready     : std_logic := '0';
    signal rx_error     : std_logic := '0';
    signal tx_data      : std_logic_vector(7 downto 0);
    signal tx_start     : std_logic;
    signal tx_active    : std_logic := '0';
    signal tx_done      : std_logic := '0';
    signal dir_x        : std_logic;
    signal dir_y        : std_logic;
    signal pen_state    : std_logic;
    signal pen_update   : std_logic;
    signal steps_x      : std_logic_vector(15 downto 0);
    signal steps_y      : std_logic_vector(15 downto 0);
    signal start_motion : std_logic;
    signal motion_done  : std_logic := '0';
    signal is_homing    : std_logic;

    type t_resp_bytes is array (0 to 4) of std_logic_vector(7 downto 0);
    signal r_resp_bytes : t_resp_bytes := (others => (others => '0'));
    signal r_resp_index : natural range 0 to 4 := 0;
    signal response_ready  : std_logic := '0';
    signal response_status : std_logic_vector(7 downto 0) := (others => '0');
    signal response_seq    : std_logic_vector(15 downto 0) := (others => '0');
    signal response_crc_ok : std_logic := '0';
    signal tx_busy_count   : natural range 0 to 3 := 0;
    signal start_count     : natural := 0;

    procedure send_byte(
        constant value : in std_logic_vector(7 downto 0);
        signal data     : out std_logic_vector(7 downto 0);
        signal ready    : out std_logic
    ) is
    begin
        wait until rising_edge(clk);
        data  <= value;
        ready <= '1';
        wait until rising_edge(clk);
        ready <= '0';
    end procedure;

    procedure send_frame(
        constant flags    : in std_logic_vector(7 downto 0);
        constant sx       : in natural;
        constant sy       : in natural;
        constant sequence : in natural;
        constant corrupt  : in boolean;
        signal data       : out std_logic_vector(7 downto 0);
        signal ready      : out std_logic
    ) is
        variable bytes : t_resp_bytes;
        variable crc   : std_logic_vector(7 downto 0);
        variable seq_v : unsigned(15 downto 0);
        variable sx_v  : unsigned(15 downto 0);
        variable sy_v  : unsigned(15 downto 0);
    begin
        seq_v := to_unsigned(sequence, 16);
        sx_v  := to_unsigned(sx, 16);
        sy_v  := to_unsigned(sy, 16);
        crc := x"AA" xor flags xor
               std_logic_vector(sx_v(15 downto 8)) xor std_logic_vector(sx_v(7 downto 0)) xor
               std_logic_vector(sy_v(15 downto 8)) xor std_logic_vector(sy_v(7 downto 0)) xor
               std_logic_vector(seq_v(15 downto 8)) xor std_logic_vector(seq_v(7 downto 0));
        if corrupt then
            crc := not crc;
        end if;

        send_byte(x"AA", data, ready);
        send_byte(flags, data, ready);
        send_byte(std_logic_vector(sx_v(15 downto 8)), data, ready);
        send_byte(std_logic_vector(sx_v(7 downto 0)), data, ready);
        send_byte(std_logic_vector(sy_v(15 downto 8)), data, ready);
        send_byte(std_logic_vector(sy_v(7 downto 0)), data, ready);
        send_byte(std_logic_vector(seq_v(15 downto 8)), data, ready);
        send_byte(std_logic_vector(seq_v(7 downto 0)), data, ready);
        send_byte(crc, data, ready);
    end procedure;

begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.fsm_main
        generic map (
            CLK_FREQ_HZ => 1000000,
            RX_GAP_TIMEOUT_MS => 1,
            RESPONSE_QUEUE_LEN => 4
        )
        port map (
            clk => clk,
            reset => reset,
            rx_data => rx_data,
            rx_ready => rx_ready,
            rx_error => rx_error,
            tx_data => tx_data,
            tx_start => tx_start,
            tx_active => tx_active,
            tx_done => tx_done,
            dir_x => dir_x,
            dir_y => dir_y,
            pen_state => pen_state,
            pen_update => pen_update,
            steps_x => steps_x,
            steps_y => steps_y,
            start_motion => start_motion,
            motion_done => motion_done,
            is_homing => is_homing
        );

    -- Minimal UART-TX handshake model and response-frame monitor.
    process(clk)
        variable checksum : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk) then
            response_ready <= '0';
            tx_done <= '0';

            if reset = '1' then
                tx_active <= '0';
                tx_busy_count <= 0;
                r_resp_index <= 0;
                response_crc_ok <= '0';
                start_count <= 0;
            else
                if start_motion = '1' then
                    start_count <= start_count + 1;
                end if;

                if tx_active = '0' then
                    if tx_start = '1' then
                        tx_active <= '1';
                        tx_busy_count <= 2;
                        r_resp_bytes(r_resp_index) <= tx_data;
                        if r_resp_index = 4 then
                            checksum := r_resp_bytes(0) xor r_resp_bytes(1) xor
                                        r_resp_bytes(2) xor r_resp_bytes(3);
                            response_status <= r_resp_bytes(1);
                            response_seq <= r_resp_bytes(2) & r_resp_bytes(3);
                            if checksum = tx_data and r_resp_bytes(0) = x"55" then
                                response_crc_ok <= '1';
                            else
                                response_crc_ok <= '0';
                            end if;
                            response_ready <= '1';
                            r_resp_index <= 0;
                        else
                            r_resp_index <= r_resp_index + 1;
                        end if;
                    end if;
                else
                    if tx_busy_count = 0 then
                        tx_active <= '0';
                        tx_done <= '1';
                    else
                        tx_busy_count <= tx_busy_count - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    process
        variable starts_before : natural;
    begin
        wait for 100 ns;
        reset <= '0';
        wait for 50 ns;

        -- New command: one start pulse and A response.
        send_frame(x"05", 10, 11, 16#1234#, false, rx_data, rx_ready);
        wait until start_motion = '1';
        assert dir_x = '1' and dir_y = '0' and pen_state = '1'
            report "command flags not loaded" severity failure;
        assert unsigned(steps_x) = 10 and unsigned(steps_y) = 11
            report "step counts not loaded" severity failure;
        wait until response_ready = '1';
        assert response_crc_ok = '1' and response_status = x"41" and response_seq = x"1234"
            report "missing/invalid A response" severity failure;

        -- Same sequence while running is a status poll, never a second move.
        starts_before := start_count;
        send_frame(x"05", 10, 11, 16#1234#, false, rx_data, rx_ready);
        wait until response_ready = '1';
        assert response_status = x"52" and response_seq = x"1234"
            report "duplicate-running frame did not return R" severity failure;
        assert start_count = starts_before
            report "duplicate-running frame restarted movement" severity failure;

        -- Completion returns K.
        wait until rising_edge(clk);
        motion_done <= '1';
        wait until rising_edge(clk);
        motion_done <= '0';
        wait until response_ready = '1';
        assert response_status = x"4B" and response_seq = x"1234"
            report "completion did not return K" severity failure;

        -- Repeating a completed sequence replays K without movement.
        starts_before := start_count;
        send_frame(x"05", 10, 11, 16#1234#, false, rx_data, rx_ready);
        wait until response_ready = '1';
        assert response_status = x"4B" and response_seq = x"1234"
            report "completed duplicate did not replay K" severity failure;
        assert start_count = starts_before
            report "completed duplicate restarted movement" severity failure;

        -- Corrupted CRC returns C and does not start movement.
        starts_before := start_count;
        send_frame(x"00", 1, 2, 16#2222#, true, rx_data, rx_ready);
        wait until response_ready = '1';
        assert response_status = x"43" and response_seq = x"2222"
            report "bad CRC did not return C" severity failure;
        assert start_count = starts_before
            report "bad CRC started movement" severity failure;

        report "tb_fsm_main PASS" severity note;
        finish;
    end process;

end architecture;
