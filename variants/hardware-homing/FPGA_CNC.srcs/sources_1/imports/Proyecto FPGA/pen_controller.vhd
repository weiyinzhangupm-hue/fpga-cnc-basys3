library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pen_controller is
    Generic (
        CLK_FREQ_HZ   : integer := 100000000;
        PWM_HZ        : integer := 50; 
        PULSE_UP_US   : integer := 500;
        PULSE_DOWN_US : integer := 2500
    );
    Port (
        clk          : in  STD_LOGIC;
        reset        : in  STD_LOGIC;
        update       : in  STD_LOGIC;
        pen_down_cmd : in  STD_LOGIC;
        servo_pwm    : out STD_LOGIC;
        pen_is_down  : out STD_LOGIC
    );
end pen_controller;

architecture Behavioral of pen_controller is

    -- Calculo automatico de limites
    constant TICKS_PER_US : integer := CLK_FREQ_HZ / 1000000;
    constant MAX_COUNT    : integer := CLK_FREQ_HZ / PWM_HZ;
    constant UP_COUNT     : integer := PULSE_UP_US * TICKS_PER_US;
    constant DOWN_COUNT   : integer := PULSE_DOWN_US * TICKS_PER_US;

    signal r_counter      : integer range 0 to MAX_COUNT := 0;

    -- REGISTRO ACTIVO: El que esta usando el hardware ahora mismo
    signal r_active_limit : integer := UP_COUNT;

    -- REGISTRO SOMBRA: Guarda la nueva orden hasta que sea seguro aplicarla
    signal r_shadow_limit : integer := UP_COUNT;
    signal r_shadow_state : std_logic := '0';

begin

    process(clk, reset)
    begin
        if reset = '1' then
            r_counter      <= 0;
            r_active_limit <= UP_COUNT;
            r_shadow_limit <= UP_COUNT;
            r_shadow_state <= '0';
            servo_pwm      <= '0';
            pen_is_down    <= '0';
            
        elsif rising_edge(clk) then

            -- 1. Capturamos la orden en el Registro Sombra inmediatamente
            if update = '1' then
                if pen_down_cmd = '1' then
                    r_shadow_limit <= DOWN_COUNT;
                    r_shadow_state <= '1';
                else
                    r_shadow_limit <= UP_COUNT;
                    r_shadow_state <= '0';
                end if;
            end if;

            -- 2. Base de tiempos y actualizacion segura
            if r_counter = MAX_COUNT - 1 then
                -- Ha terminado el periodo (por ejemplo, 20 ms). 
                -- Es seguro actualizar el pulso activo con lo que haya en la sombra.
                r_counter      <= 0;
                r_active_limit <= r_shadow_limit;
                pen_is_down    <= r_shadow_state;
            else
                r_counter <= r_counter + 1;
            end if;

            -- 3. Generacion fisica del PWM basada SOLO en el registro activo
            if r_counter < r_active_limit then
                servo_pwm <= '1';
            else
                servo_pwm <= '0';
            end if;

        end if;
    end process;

end Behavioral;