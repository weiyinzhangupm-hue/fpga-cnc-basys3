----------------------------------------------------------------------------------
-- Nivel superior Basys3 CNC - protocolo UART fiable y modo rapido
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top_level is
    Generic (
        SYS_CLK_FREQ       : positive := 100000000;
        SYS_BAUD           : positive := 115200;
        SYS_MOT_FREQ       : positive := 3000;
        LIMIT_DEBOUNCE_MS  : positive := 2
    );
    Port (
        clk       : in  STD_LOGIC;
        reset     : in  STD_LOGIC;
        rx        : in  STD_LOGIC;
        tx        : out STD_LOGIC;
        step_x    : out STD_LOGIC;
        dir_x     : out STD_LOGIC;
        step_y    : out STD_LOGIC;
        dir_y     : out STD_LOGIC;
        limit_x   : in  STD_LOGIC;
        limit_y   : in  STD_LOGIC;
        servo_pwm : out STD_LOGIC;
        vgaRed    : out STD_LOGIC_VECTOR(3 downto 0);
        vgaGreen  : out STD_LOGIC_VECTOR(3 downto 0);
        vgaBlue   : out STD_LOGIC_VECTOR(3 downto 0);
        Hsync     : out STD_LOGIC;
        Vsync     : out STD_LOGIC
    );
end top_level;

architecture Structural of top_level is

    function max_positive(a : positive; b : natural) return positive is
    begin
        if b < a then
            return a;
        end if;
        return b;
    end function;

    constant C_LIMIT_FILTER_CYCLES : positive := max_positive(
        1,
        (SYS_CLK_FREQ / 1000) * LIMIT_DEBOUNCE_MS
    );

    component divisor_reloj
        Generic (
            CLK_FREQ  : integer;
            BAUD_RATE : integer;
            MOTOR_FREQ: integer
        );
        Port (
            clk, reset : in STD_LOGIC;
            tick_uart, tick_motor : out STD_LOGIC
        );
    end component;

    component uart_rx
        Generic (
            CLK_FREQ  : positive;
            BAUD_RATE : positive
        );
        Port (
            clk, reset, rx : in STD_LOGIC;
            data_out       : out STD_LOGIC_VECTOR(7 downto 0);
            rx_ready       : out STD_LOGIC;
            frame_error    : out STD_LOGIC
        );
    end component;

    component uart_tx
        Generic (
            CLK_FREQ  : positive;
            BAUD_RATE : positive
        );
        Port (
            clk, reset, tx_start : in STD_LOGIC;
            data_in              : in STD_LOGIC_VECTOR(7 downto 0);
            tx, tx_active, tx_done : out STD_LOGIC
        );
    end component;

    component fsm_main
        Generic (
            CLK_FREQ_HZ        : positive := 100000000;
            RX_GAP_TIMEOUT_MS  : positive := 5;
            RESPONSE_QUEUE_LEN : positive := 4
        );
        Port (
            clk, reset : in STD_LOGIC;
            rx_data    : in STD_LOGIC_VECTOR(7 downto 0);
            rx_ready, rx_error : in STD_LOGIC;
            tx_data    : out STD_LOGIC_VECTOR(7 downto 0);
            tx_start   : out STD_LOGIC;
            tx_active, tx_done : in STD_LOGIC;
            dir_x, dir_y, pen_state, pen_update : out STD_LOGIC;
            steps_x, steps_y : out STD_LOGIC_VECTOR(15 downto 0);
            start_motion : out STD_LOGIC;
            motion_done  : in STD_LOGIC;
            is_homing    : out STD_LOGIC
        );
    end component;

    component bresenham_2d
        Port (
            clk, reset, tick_motor, start_motion, abort_motion : in STD_LOGIC;
            steps_x, steps_y : in STD_LOGIC_VECTOR(15 downto 0);
            step_x, step_y, motion_done : out STD_LOGIC
        );
    end component;

    component pen_controller
        Generic (
            CLK_FREQ_HZ : integer := 100000000;
            PWM_HZ      : integer := 50;
            PULSE_UP_US : integer := 1500;
            PULSE_DOWN_US : integer := 2000
        );
        Port (
            clk, reset, update, pen_down_cmd : in std_logic;
            servo_pwm, pen_is_down : out std_logic
        );
    end component;

    component tb6600_axis_driver
        Generic (
            CLK_FREQ_HZ  : positive := 100000000;
            STEP_PULSE_US: positive := 5
        );
        Port (
            clk, reset, step_request, direction, enable_request, limit_active : in STD_LOGIC;
            step_out, dir_out, enable_out, busy, limit_fault, dropped_step : out STD_LOGIC
        );
    end component;

    component vga_shapes
        Port (
            clk, reset : in STD_LOGIC;
            step_x_pulse, step_y_pulse, dir_x, dir_y,
            pen_down, pen_update, trace_clear : in STD_LOGIC;
            vgaRed, vgaGreen, vgaBlue : out STD_LOGIC_VECTOR(3 downto 0);
            Hsync, Vsync : out STD_LOGIC
        );
    end component;

    signal w_tick_uart, w_tick_motor : STD_LOGIC;
    signal w_rx_data, w_tx_data      : STD_LOGIC_VECTOR(7 downto 0);
    signal w_rx_ready, w_rx_error    : STD_LOGIC;
    signal w_tx_start, w_tx_active, w_tx_done : STD_LOGIC;

    signal w_steps_x, w_steps_y : STD_LOGIC_VECTOR(15 downto 0);
    signal w_start_mot, w_motion_done : STD_LOGIC;
    signal w_pen_state, w_pen_update  : STD_LOGIC;
    signal w_abort_motion, w_is_homing : STD_LOGIC;

    signal w_step_x_req, w_step_y_req : STD_LOGIC;
    signal w_dir_x_int, w_dir_y_int   : STD_LOGIC;
    signal r_trace_step_x_req, r_trace_step_y_req : STD_LOGIC := '0';

    signal r_limit_x_meta, r_limit_x_sync : STD_LOGIC := '0';
    signal r_limit_y_meta, r_limit_y_sync : STD_LOGIC := '0';
    signal r_limit_x_stable, r_limit_y_stable : STD_LOGIC := '0';
    signal r_limit_x_count : natural range 0 to C_LIMIT_FILTER_CYCLES - 1 := 0;
    signal r_limit_y_count : natural range 0 to C_LIMIT_FILTER_CYCLES - 1 := 0;
    signal w_crash_x, w_crash_y : STD_LOGIC;

    signal r_homing_done_x, r_homing_done_y : STD_LOGIC := '0';
    signal w_limit_x_final, w_limit_y_final : STD_LOGIC;
    signal w_has_x_steps, w_has_y_steps     : STD_LOGIC;

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of r_limit_x_meta : signal is "TRUE";
    attribute ASYNC_REG of r_limit_x_sync : signal is "TRUE";
    attribute ASYNC_REG of r_limit_y_meta : signal is "TRUE";
    attribute ASYNC_REG of r_limit_y_sync : signal is "TRUE";

begin

    --------------------------------------------------------------------------
    -- Sincronizacion y antirrebote de los finales de carrera.
    -- El diseño asume interruptores activos en alto; el XDC añade pulldown debil.
    --------------------------------------------------------------------------
    process(clk, reset)
    begin
        if reset = '1' then
            r_limit_x_meta   <= '0';
            r_limit_x_sync   <= '0';
            r_limit_y_meta   <= '0';
            r_limit_y_sync   <= '0';
            r_limit_x_stable <= '0';
            r_limit_y_stable <= '0';
            r_limit_x_count  <= 0;
            r_limit_y_count  <= 0;

        elsif rising_edge(clk) then
            r_limit_x_meta <= limit_x;
            r_limit_x_sync <= r_limit_x_meta;
            r_limit_y_meta <= limit_y;
            r_limit_y_sync <= r_limit_y_meta;

            if r_limit_x_sync = r_limit_x_stable then
                r_limit_x_count <= 0;
            elsif r_limit_x_count = C_LIMIT_FILTER_CYCLES - 1 then
                r_limit_x_stable <= r_limit_x_sync;
                r_limit_x_count  <= 0;
            else
                r_limit_x_count <= r_limit_x_count + 1;
            end if;

            if r_limit_y_sync = r_limit_y_stable then
                r_limit_y_count <= 0;
            elsif r_limit_y_count = C_LIMIT_FILTER_CYCLES - 1 then
                r_limit_y_stable <= r_limit_y_sync;
                r_limit_y_count  <= 0;
            else
                r_limit_y_count <= r_limit_y_count + 1;
            end if;
        end if;
    end process;

    w_crash_x <= r_limit_x_stable;
    w_crash_y <= r_limit_y_stable;

    --------------------------------------------------------------------------
    -- Memoria de fin de homing. Cada eje se detiene fisicamente al tocar
    -- su final de carrera; el interpolador termina cuando todos los ejes
    -- solicitados han llegado al origen.
    --------------------------------------------------------------------------
    process(clk, reset)
    begin
        if reset = '1' then
            r_homing_done_x <= '0';
            r_homing_done_y <= '0';
        elsif rising_edge(clk) then
            if w_is_homing = '0' then
                r_homing_done_x <= '0';
                r_homing_done_y <= '0';
            else
                if w_crash_x = '1' then
                    r_homing_done_x <= '1';
                end if;
                if w_crash_y = '1' then
                    r_homing_done_y <= '1';
                end if;
            end if;
        end if;
    end process;

    w_has_x_steps <= '1' when unsigned(w_steps_x) /= to_unsigned(0, w_steps_x'length) else '0';
    w_has_y_steps <= '1' when unsigned(w_steps_y) /= to_unsigned(0, w_steps_y'length) else '0';

    w_abort_motion <= '1' when
        w_is_homing = '1' and
        (w_has_x_steps = '0' or r_homing_done_x = '1') and
        (w_has_y_steps = '0' or r_homing_done_y = '1')
        else '0';

    -- Finales de origen: dir=0 mueve hacia home, dir=1 se aleja.
    w_limit_x_final <= '1' when
        (w_is_homing = '1' and (w_crash_x = '1' or r_homing_done_x = '1')) or
        (w_is_homing = '0' and w_crash_x = '1' and w_dir_x_int = '0')
        else '0';

    w_limit_y_final <= '1' when
        (w_is_homing = '1' and (w_crash_y = '1' or r_homing_done_y = '1')) or
        (w_is_homing = '0' and w_crash_y = '1' and w_dir_y_int = '0')
        else '0';

    --------------------------------------------------------------------------
    -- La VGA usa los pulsos virtuales del interpolador. El homing no se dibuja.
    --------------------------------------------------------------------------
    process(clk, reset)
    begin
        if reset = '1' then
            r_trace_step_x_req <= '0';
            r_trace_step_y_req <= '0';
        elsif rising_edge(clk) then
            if w_is_homing = '1' then
                r_trace_step_x_req <= '0';
                r_trace_step_y_req <= '0';
            else
                r_trace_step_x_req <= w_step_x_req;
                r_trace_step_y_req <= w_step_y_req;
            end if;
        end if;
    end process;

    Inst_Divisor: divisor_reloj
        generic map (
            CLK_FREQ   => SYS_CLK_FREQ,
            BAUD_RATE  => SYS_BAUD,
            MOTOR_FREQ => SYS_MOT_FREQ
        )
        port map (
            clk => clk,
            reset => reset,
            tick_uart => w_tick_uart,
            tick_motor => w_tick_motor
        );

    Inst_UART_RX: uart_rx
        generic map (
            CLK_FREQ  => SYS_CLK_FREQ,
            BAUD_RATE => SYS_BAUD
        )
        port map (
            clk => clk,
            reset => reset,
            rx => rx,
            data_out => w_rx_data,
            rx_ready => w_rx_ready,
            frame_error => w_rx_error
        );

    Inst_UART_TX: uart_tx
        generic map (
            CLK_FREQ  => SYS_CLK_FREQ,
            BAUD_RATE => SYS_BAUD
        )
        port map (
            clk => clk,
            reset => reset,
            tx_start => w_tx_start,
            data_in => w_tx_data,
            tx => tx,
            tx_active => w_tx_active,
            tx_done => w_tx_done
        );

    Inst_FSM_Main: fsm_main
        generic map (
            CLK_FREQ_HZ => SYS_CLK_FREQ,
            RX_GAP_TIMEOUT_MS => 5,
            RESPONSE_QUEUE_LEN => 4
        )
        port map (
            clk => clk,
            reset => reset,
            rx_data => w_rx_data,
            rx_ready => w_rx_ready,
            rx_error => w_rx_error,
            tx_data => w_tx_data,
            tx_start => w_tx_start,
            tx_active => w_tx_active,
            tx_done => w_tx_done,
            dir_x => w_dir_x_int,
            dir_y => w_dir_y_int,
            pen_state => w_pen_state,
            pen_update => w_pen_update,
            steps_x => w_steps_x,
            steps_y => w_steps_y,
            start_motion => w_start_mot,
            motion_done => w_motion_done,
            is_homing => w_is_homing
        );

    Inst_Bresenham: bresenham_2d
        port map (
            clk => clk,
            reset => reset,
            tick_motor => w_tick_motor,
            start_motion => w_start_mot,
            abort_motion => w_abort_motion,
            steps_x => w_steps_x,
            steps_y => w_steps_y,
            step_x => w_step_x_req,
            step_y => w_step_y_req,
            motion_done => w_motion_done
        );

    Inst_Pen_Controller: pen_controller
        generic map (
            CLK_FREQ_HZ => SYS_CLK_FREQ,
            PWM_HZ => 50,
            PULSE_UP_US => 1500,
            PULSE_DOWN_US => 2000
        )
        port map (
            clk => clk,
            reset => reset,
            update => w_pen_update,
            pen_down_cmd => w_pen_state,
            servo_pwm => servo_pwm,
            pen_is_down => open
        );

    Inst_VGA_Shapes: vga_shapes
        port map (
            clk => clk,
            reset => reset,
            step_x_pulse => r_trace_step_x_req,
            step_y_pulse => r_trace_step_y_req,
            dir_x => w_dir_x_int,
            dir_y => w_dir_y_int,
            pen_down => w_pen_state,
            pen_update => w_pen_update,
            trace_clear => w_is_homing,
            vgaRed => vgaRed,
            vgaGreen => vgaGreen,
            vgaBlue => vgaBlue,
            Hsync => Hsync,
            Vsync => Vsync
        );

    Inst_Driver_X: tb6600_axis_driver
        generic map (
            CLK_FREQ_HZ => SYS_CLK_FREQ,
            STEP_PULSE_US => 5
        )
        port map (
            clk => clk,
            reset => reset,
            step_request => w_step_x_req,
            direction => w_dir_x_int,
            enable_request => '1',
            limit_active => w_limit_x_final,
            step_out => step_x,
            dir_out => dir_x,
            enable_out => open,
            busy => open,
            limit_fault => open,
            dropped_step => open
        );

    Inst_Driver_Y: tb6600_axis_driver
        generic map (
            CLK_FREQ_HZ => SYS_CLK_FREQ,
            STEP_PULSE_US => 5
        )
        port map (
            clk => clk,
            reset => reset,
            step_request => w_step_y_req,
            direction => w_dir_y_int,
            enable_request => '1',
            limit_active => w_limit_y_final,
            step_out => step_y,
            dir_out => dir_y,
            enable_out => open,
            busy => open,
            limit_fault => open,
            dropped_step => open
        );

end Structural;
