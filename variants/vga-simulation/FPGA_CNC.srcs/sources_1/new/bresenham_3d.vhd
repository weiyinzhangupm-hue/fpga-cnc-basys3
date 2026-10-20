----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 04.05.2026 17:32:04
-- Design Name: 
-- Module Name: bresenham_3d - Behavioral
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

entity bresenham_2d is
    Port (
        clk          : in  STD_LOGIC;
        reset        : in  STD_LOGIC;
        tick_motor   : in  STD_LOGIC;        -- Pulso lento que viene del divisor de reloj
        start_motion : in  STD_LOGIC;        -- Orden de arranque que viene del FSM_Main
        abort_motion : in  STD_LOGIC;        -- NUEVO: Freno de emergencia (Finales de carrera)
        
        -- Cantidad de pasos solicitada (Solo X e Y)
        steps_x      : in  STD_LOGIC_VECTOR(15 downto 0);
        steps_y      : in  STD_LOGIC_VECTOR(15 downto 0);
        
        -- Pulsos físicos hacia el controlador de motores
        step_x       : out STD_LOGIC;
        step_y       : out STD_LOGIC;
        
        -- Señal de finalización hacia el FSM_Main
        motion_done  : out STD_LOGIC
    );
end bresenham_2d;

architecture Behavioral of bresenham_2d is

    type t_State is (s_IDLE, s_SETUP, s_RUN, s_FINISH);
    signal r_State : t_State := s_IDLE;

    -- Registros matemáticos
    signal r_steps_x, r_steps_y : integer range 0 to 65535 := 0;
    signal r_max_steps          : integer range 0 to 65535 := 0;
    signal r_step_count         : integer range 0 to 65535 := 0;

    -- Acumuladores de error para X e Y
    signal err_x, err_y : integer range 0 to 131071 := 0;

begin

    process(clk, reset)
        variable v_max : integer range 0 to 65535;
    begin
        if reset = '1' then
            r_State     <= s_IDLE;
            step_x      <= '0';
            step_y      <= '0';
            motion_done <= '0';
            
        elsif rising_edge(clk) then
            
            -- Los pulsos de paso duran solo 1 ciclo de reloj maestro
            step_x      <= '0';
            step_y      <= '0';
            motion_done <= '0';

            case r_State is
                
                -- ESTADO 1: Esperar la orden de arranque
                when s_IDLE =>
                    if start_motion = '1' then
                        r_steps_x <= to_integer(unsigned(steps_x));
                        r_steps_y <= to_integer(unsigned(steps_y));
                        r_State   <= s_SETUP;
                    end if;

                -- ESTADO 2: Configurar las matemáticas (Buscamos el eje dominante 2D)
                when s_SETUP =>
                    -- Si detectamos una colisión incluso antes de arrancar, abortamos
                    if abort_motion = '1' then
                        r_State <= s_FINISH;
                    else
                        if r_steps_x > r_steps_y then
                            v_max := r_steps_x;
                        else
                            v_max := r_steps_y;
                        end if;
                        
                        r_max_steps <= v_max;
                        
                        -- Si no hay movimiento, pasamos directo al final
                        if v_max = 0 then
                            r_State <= s_FINISH;
                        else
                            -- Inicializamos los acumuladores al 50% para un redondeo perfecto
                            err_x <= v_max / 2;
                            err_y <= v_max / 2;
                            
                            r_step_count <= 0;
                            r_State      <= s_RUN;
                        end if;
                    end if;

                -- ESTADO 3: Ejecutar el movimiento
                when s_RUN =>
                    -- FRENO DE EMERGENCIA: Si un final de carrera se activa, paramos inmediatamente
                    if abort_motion = '1' then
                        r_State <= s_FINISH;
                        
                    elsif tick_motor = '1' then
                        
                        -- Cálculo Eje X
                        if (err_x + r_steps_x) >= r_max_steps then
                            err_x  <= err_x + r_steps_x - r_max_steps;
                            step_x <= '1';
                        else
                            err_x  <= err_x + r_steps_x;
                        end if;

                        -- Cálculo Eje Y
                        if (err_y + r_steps_y) >= r_max_steps then
                            err_y  <= err_y + r_steps_y - r_max_steps;
                            step_y <= '1';
                        else
                            err_y  <= err_y + r_steps_y;
                        end if;

                        -- Meta alcanzada
                        if r_step_count = r_max_steps - 1 then
                            r_State <= s_FINISH;
                        else
                            r_step_count <= r_step_count + 1;
                        end if;
                        
                    end if;

                -- ESTADO 4: Confirmación
                when s_FINISH =>
                    motion_done <= '1';
                    r_State     <= s_IDLE;
                    
            end case;
        end if;
    end process;

end Behavioral;
