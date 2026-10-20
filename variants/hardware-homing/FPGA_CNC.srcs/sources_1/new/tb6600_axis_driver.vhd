library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tb6600_axis_driver is
    Generic (
        CLK_FREQ_HZ         : positive  := 100000000;
        STEP_PULSE_US       : positive  := 5;
        DIR_SETUP_US        : natural   := 5;
        STEP_ACTIVE_LEVEL   : std_logic := '1';
        ENABLE_ACTIVE_LEVEL : std_logic := '1';
        DIR_INVERT          : std_logic := '0'
    );
    Port (
        clk            : in  STD_LOGIC;
        reset          : in  STD_LOGIC;
        step_request   : in  STD_LOGIC;
        direction      : in  STD_LOGIC;
        enable_request : in  STD_LOGIC;
        limit_active   : in  STD_LOGIC;
        step_out       : out STD_LOGIC;
        dir_out        : out STD_LOGIC;
        enable_out     : out STD_LOGIC;
        busy           : out STD_LOGIC;
        limit_fault    : out STD_LOGIC;
        dropped_step   : out STD_LOGIC
    );
end tb6600_axis_driver;

architecture Behavioral of tb6600_axis_driver is

    function us_to_cycles(clk_hz : positive; pulse_us : natural) return positive is
        variable ticks_per_us : natural;
        variable cycles       : natural;
    begin
        ticks_per_us := (clk_hz + 999999) / 1000000;
        if ticks_per_us = 0 then
            ticks_per_us := 1;
        end if;

        cycles := ticks_per_us * pulse_us;
        if cycles = 0 then
            return 1;
        end if;
        return cycles;
    end function;

    constant STEP_PULSE_CLKS : positive := us_to_cycles(CLK_FREQ_HZ, STEP_PULSE_US);
    constant DIR_SETUP_CLKS  : natural  := DIR_SETUP_US * ((CLK_FREQ_HZ + 999999) / 1000000);

    type t_state is (s_IDLE, s_DIR_SETUP, s_STEP_HIGH);
    signal r_state             : t_state := s_IDLE;
    signal r_prev_step_request : std_logic := '0';
    signal r_pending           : std_logic := '0';
    signal r_step              : std_logic := not STEP_ACTIVE_LEVEL;
    signal r_dir               : std_logic := '0';
    signal r_enable            : std_logic := not ENABLE_ACTIVE_LEVEL;
    signal r_step_count        : natural range 0 to STEP_PULSE_CLKS := 0;
    signal r_setup_count       : natural range 0 to DIR_SETUP_CLKS := 0;
    signal r_dropped_step      : std_logic := '0';

begin

    process(clk, reset)
        variable v_new_request    : boolean;
        variable v_enable_allowed : boolean;
        variable v_pending_next   : std_logic;
        variable v_dropped_next   : std_logic;
    begin
        if reset = '1' then
            r_state             <= s_IDLE;
            r_prev_step_request <= '0';
            r_pending           <= '0';
            r_step              <= not STEP_ACTIVE_LEVEL;
            r_dir               <= '0';
            r_enable            <= not ENABLE_ACTIVE_LEVEL;
            r_step_count        <= 0;
            r_setup_count       <= 0;
            r_dropped_step      <= '0';
        elsif rising_edge(clk) then
            v_new_request    := (step_request = '1' and r_prev_step_request = '0');
            v_enable_allowed := (enable_request = '1');
            v_pending_next   := r_pending;
            v_dropped_next   := r_dropped_step;

            r_prev_step_request <= step_request;

            if v_enable_allowed then
                r_enable <= ENABLE_ACTIVE_LEVEL;
            else
                r_enable      <= not ENABLE_ACTIVE_LEVEL;
                r_step        <= not STEP_ACTIVE_LEVEL;
                r_state       <= s_IDLE;
                r_step_count  <= 0;
                r_setup_count <= 0;
                v_pending_next := '0';
            end if;

            if v_new_request then
                if v_enable_allowed then
                    if limit_active = '1' then
                        v_dropped_next := '1';
                    elsif v_pending_next = '0' then
                        v_pending_next := '1';
                    else
                        v_dropped_next := '1';
                    end if;
                else
                    v_dropped_next := '1';
                end if;
            end if;

            if v_enable_allowed and limit_active = '1' then
                r_step        <= not STEP_ACTIVE_LEVEL;
                r_state       <= s_IDLE;
                r_step_count  <= 0;
                r_setup_count <= 0;
                v_pending_next := '0';
            elsif v_enable_allowed then
                case r_state is
                    when s_IDLE =>
                        r_step <= not STEP_ACTIVE_LEVEL;
                        if v_pending_next = '1' then
                            v_pending_next := '0';
                            r_dir <= direction xor DIR_INVERT;

                            if DIR_SETUP_CLKS = 0 then
                                r_step       <= STEP_ACTIVE_LEVEL;
                                r_step_count <= STEP_PULSE_CLKS;
                                r_state      <= s_STEP_HIGH;
                            else
                                r_setup_count <= DIR_SETUP_CLKS;
                                r_state       <= s_DIR_SETUP;
                            end if;
                        end if;

                    when s_DIR_SETUP =>
                        r_step <= not STEP_ACTIVE_LEVEL;
                        if r_setup_count <= 1 then
                            r_setup_count <= 0;
                            r_step        <= STEP_ACTIVE_LEVEL;
                            r_step_count  <= STEP_PULSE_CLKS;
                            r_state       <= s_STEP_HIGH;
                        else
                            r_setup_count <= r_setup_count - 1;
                        end if;

                    when s_STEP_HIGH =>
                        if r_step_count <= 1 then
                            r_step       <= not STEP_ACTIVE_LEVEL;
                            r_step_count <= 0;
                            r_state      <= s_IDLE;
                        else
                            r_step       <= STEP_ACTIVE_LEVEL;
                            r_step_count <= r_step_count - 1;
                        end if;
                end case;
            end if;

            r_pending      <= v_pending_next;
            r_dropped_step <= v_dropped_next;
        end if;
    end process;

    step_out     <= r_step;
    dir_out      <= r_dir;
    enable_out   <= r_enable;
    busy         <= '1' when (r_state /= s_IDLE or r_pending = '1') else '0';
    limit_fault  <= limit_active;
    dropped_step <= r_dropped_step;

end Behavioral;
