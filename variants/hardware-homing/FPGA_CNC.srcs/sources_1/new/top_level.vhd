
----------------------------------------------------------------------------------
-- Módulo: top_level - Versión Definitiva (Homing Rápido + Fix Port Map)
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity top_level is
    Generic (
        SYS_CLK_FREQ : integer := 100000000;
        SYS_BAUD     : integer := 115200;    
        SYS_MOT_FREQ : integer := 1000       
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
        servo_pwm : out STD_LOGIC
    );
end top_level;

architecture Structural of top_level is

    component divisor_reloj
        Generic ( CLK_FREQ : integer; BAUD_RATE : integer; MOTOR_FREQ : integer );
        Port ( clk, reset : in STD_LOGIC; tick_uart, tick_motor : out STD_LOGIC );
    end component;

    component uart_rx
        Generic ( CLK_FREQ : integer; BAUD_RATE : integer );
        Port ( clk, reset, rx : in STD_LOGIC; data_out : out STD_LOGIC_VECTOR(7 downto 0); rx_ready : out STD_LOGIC );
    end component;

    component uart_tx
        Generic ( CLK_FREQ : integer; BAUD_RATE : integer );
        Port ( clk, reset, tx_start : in STD_LOGIC; data_in : in STD_LOGIC_VECTOR(7 downto 0);
               tx, tx_active, tx_done : out STD_LOGIC );
    end component;

    component fsm_main
        Port ( clk, reset : in STD_LOGIC;
               rx_data : in STD_LOGIC_VECTOR(7 downto 0); rx_ready : in STD_LOGIC;
               tx_data : out STD_LOGIC_VECTOR(7 downto 0); tx_start : out STD_LOGIC;
               dir_x, dir_y, pen_state, pen_update : out STD_LOGIC;
               steps_x, steps_y : out STD_LOGIC_VECTOR(15 downto 0);
               start_motion : out STD_LOGIC; motion_done : in STD_LOGIC;
               is_homing : out STD_LOGIC );
    end component;

    component bresenham_2d
        Port ( clk, reset, tick_motor, start_motion, abort_motion : in STD_LOGIC;
               steps_x, steps_y : in STD_LOGIC_VECTOR(15 downto 0);
               step_x, step_y, motion_done : out STD_LOGIC );
    end component;

    component pen_controller
        Generic ( CLK_FREQ_HZ : integer := 100000000; PWM_HZ : integer := 50; 
                  PULSE_UP_US : integer := 1500; PULSE_DOWN_US : integer := 2000 );
        Port ( clk, reset, update, pen_down_cmd : in std_logic; 
               servo_pwm, pen_is_down : out std_logic );
    end component;

    component tb6600_axis_driver
        Generic ( CLK_FREQ_HZ : positive := 100000000; STEP_PULSE_US : positive := 5 );
        Port ( clk, reset, step_request, direction, enable_request, limit_active : in  STD_LOGIC;
               step_out, dir_out, enable_out, busy, limit_fault, dropped_step : out STD_LOGIC );
    end component;

    -- Cables internos generales
    signal w_tick_uart, w_tick_motor : STD_LOGIC;
    signal w_rx_data, w_tx_data      : STD_LOGIC_VECTOR(7 downto 0);
    signal w_rx_ready, w_tx_start    : STD_LOGIC;
    signal w_steps_x, w_steps_y      : STD_LOGIC_VECTOR(15 downto 0);
    signal w_start_mot, w_motion_done, w_pen_state, w_pen_update, w_abort_motion : STD_LOGIC;
    
    signal w_step_x_req, w_step_y_req : STD_LOGIC;
    signal w_dir_x_int, w_dir_y_int   : STD_LOGIC;

    -- Señales de Seguridad y Homing
    signal w_crash_x, w_crash_y       : STD_LOGIC;
    signal w_is_homing                : STD_LOGIC;
    
    -- Memoria (Latches) para el Homing
    signal r_homing_done_x, r_homing_done_y : STD_LOGIC := '0';
    
    -- Cables intermedios limpios para conectar a los Drivers
    signal w_limit_x_final, w_limit_y_final : STD_LOGIC;

begin

    -- ==========================================
    -- LÓGICA DE SEGURIDAD (Lectura Directa)
    -- ==========================================
    w_crash_x <= limit_x;
    w_crash_y <= limit_y;

    -- ==========================================
    -- MEMORIA DE CHOQUE PARA HOMING
    -- ==========================================
    process(clk, reset)
    begin
        if reset = '1' then
            r_homing_done_x <= '0';
            r_homing_done_y <= '0';
        elsif rising_edge(clk) then
            if w_is_homing = '0' then
                -- Si estamos dibujando normal, la memoria se borra
                r_homing_done_x <= '0';
                r_homing_done_y <= '0';
            else
                -- En Homing: Si choca, se queda guardado para siempre hasta el próximo Homing
                if w_crash_x = '1' then r_homing_done_x <= '1'; end if;
                if w_crash_y = '1' then r_homing_done_y <= '1'; end if;
            end if;
        end if;
    end process;

    -- FRENO GLOBAL (Aborter de Bresenham):
    -- Aborta SI (No es homing Y hay choque normal) Ó (Es homing Y AMBOS ejes ya han tocado pared)
    w_abort_motion <= ( (w_crash_x or w_crash_y) and (not w_is_homing) ) or 
                      ( r_homing_done_x and r_homing_done_y and w_is_homing );

    -- Mezcla del freno para los Drivers individuales
    w_limit_x_final <= w_crash_x or r_homing_done_x;
    w_limit_y_final <= w_crash_y or r_homing_done_y;


    -- ==========================================
    -- SOLDADURA DE COMPONENTES
    -- ==========================================
    Inst_Divisor: divisor_reloj
        generic map ( CLK_FREQ => SYS_CLK_FREQ, BAUD_RATE => SYS_BAUD, MOTOR_FREQ => SYS_MOT_FREQ )
        port map ( clk => clk, reset => reset, tick_uart => w_tick_uart, tick_motor => w_tick_motor );

    Inst_UART_RX: uart_rx
        generic map ( CLK_FREQ => SYS_CLK_FREQ, BAUD_RATE => SYS_BAUD )
        port map ( clk => clk, reset => reset, rx => rx, data_out => w_rx_data, rx_ready => w_rx_ready );

    Inst_UART_TX: uart_tx
        generic map ( CLK_FREQ => SYS_CLK_FREQ, BAUD_RATE => SYS_BAUD )
        port map ( clk => clk, reset => reset, tx_start => w_tx_start, data_in => w_tx_data, tx => tx );

    Inst_FSM_Main: fsm_main
        port map (
            clk => clk, reset => reset,
            rx_data => w_rx_data, rx_ready => w_rx_ready,
            tx_data => w_tx_data, tx_start => w_tx_start,
            dir_x => w_dir_x_int, dir_y => w_dir_y_int, 
            pen_state => w_pen_state, pen_update => w_pen_update,
            steps_x => w_steps_x, steps_y => w_steps_y,
            start_motion => w_start_mot, motion_done => w_motion_done,
            is_homing => w_is_homing
        );

    Inst_Bresenham: bresenham_2d
        port map (
            clk => clk, reset => reset, tick_motor => w_tick_motor,
            start_motion => w_start_mot, abort_motion => w_abort_motion,
            steps_x => w_steps_x, steps_y => w_steps_y,
            step_x => w_step_x_req, step_y => w_step_y_req, 
            motion_done => w_motion_done
        );

    Inst_Pen_Controller: pen_controller
        generic map ( CLK_FREQ_HZ => SYS_CLK_FREQ, PWM_HZ => 50, PULSE_UP_US => 1500, PULSE_DOWN_US => 2000 )
        port map (
            clk => clk, reset => reset, update => w_pen_update, pen_down_cmd => w_pen_state,
            servo_pwm => servo_pwm, pen_is_down => open
        );

    -- ==========================================
    -- DRIVERS TB6600 (Con Freno Inteligente Limpio)
    -- ==========================================
    Inst_Driver_X: tb6600_axis_driver
        generic map ( CLK_FREQ_HZ => SYS_CLK_FREQ, STEP_PULSE_US => 5 )
        port map (
            clk => clk, reset => reset,
            step_request => w_step_x_req, direction => w_dir_x_int,
            enable_request => '1', limit_active => w_limit_x_final,
            step_out => step_x, dir_out => dir_x,  
            enable_out => open, busy => open, limit_fault => open, dropped_step => open
        );

    Inst_Driver_Y: tb6600_axis_driver
        generic map ( CLK_FREQ_HZ => SYS_CLK_FREQ, STEP_PULSE_US => 5 )
        port map (
            clk => clk, reset => reset,
            step_request => w_step_y_req, direction => w_dir_y_int,
            enable_request => '1', limit_active => w_limit_y_final,
            step_out => step_y, dir_out => dir_y,  
            enable_out => open, busy => open, limit_fault => open, dropped_step => open
        );

end Structural;