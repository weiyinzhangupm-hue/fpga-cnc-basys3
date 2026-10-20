----------------------------------------------------------------------------------
-- Modulo: vga_shapes - monitor VGA 640x480 para trayectoria CNC
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library xpm;
use xpm.vcomponents.all;

entity vga_shapes is
    Port (
        clk          : in  STD_LOGIC;
        reset        : in  STD_LOGIC;
        step_x_pulse : in  STD_LOGIC;
        step_y_pulse : in  STD_LOGIC;
        dir_x        : in  STD_LOGIC;
        dir_y        : in  STD_LOGIC;
        pen_down     : in  STD_LOGIC;
        pen_update   : in  STD_LOGIC;
        trace_clear  : in  STD_LOGIC;
        vgaRed       : out STD_LOGIC_VECTOR(3 downto 0);
        vgaGreen     : out STD_LOGIC_VECTOR(3 downto 0);
        vgaBlue      : out STD_LOGIC_VECTOR(3 downto 0);
        Hsync        : out STD_LOGIC;
        Vsync        : out STD_LOGIC
    );
end vga_shapes;

architecture Behavioral of vga_shapes is
    constant H_VISIBLE     : integer := 640;
    constant H_FRONT_PORCH : integer := 16;
    constant H_SYNC_PULSE  : integer := 96;
    constant H_BACK_PORCH  : integer := 48;
    constant H_TOTAL       : integer := H_VISIBLE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH;

    constant V_VISIBLE     : integer := 480;
    constant V_FRONT_PORCH : integer := 10;
    constant V_SYNC_PULSE  : integer := 2;
    constant V_BACK_PORCH  : integer := 33;
    constant V_TOTAL       : integer := V_VISIBLE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH;

    constant TRACE_W        : integer := 320;
    constant TRACE_H        : integer := 220;
    constant TRACE_PIXELS   : integer := TRACE_W * TRACE_H;
    constant TRACE_ADDR_BITS : integer := 17;
    constant TRACE_SCREEN_H : integer := TRACE_H * 2;
    constant STEPS_PER_MM   : integer := 20;
    constant STEPS_PER_DOT  : integer := 10;

    constant TEXT_Y0     : integer := 450;
    constant TEXT_SCALE  : integer := 3;
    constant GLYPH_W     : integer := 5;
    constant GLYPH_H     : integer := 7;
    constant GLYPH_SW    : integer := GLYPH_W * TEXT_SCALE;
    constant GLYPH_SH    : integer := GLYPH_H * TEXT_SCALE;
    constant GLYPH_GAP   : integer := 4;
    constant X_TEXT_X0   : integer := 18;
    constant Y_TEXT_X0   : integer := 240;

    constant GLYPH_X     : integer := 10;
    constant GLYPH_Y     : integer := 11;
    constant GLYPH_COLON : integer := 12;
    constant GLYPH_MINUS : integer := 13;
    constant GLYPH_BLANK : integer := 14;
    subtype t_digit is integer range 0 to 9;

    signal r_pixel_div : unsigned(1 downto 0) := (others => '0');
    signal r_h_count   : integer range 0 to H_TOTAL - 1 := 0;
    signal r_v_count   : integer range 0 to V_TOTAL - 1 := 0;

    signal r_cur_dot_x   : integer range 0 to TRACE_W - 1 := 0;
    signal r_cur_dot_y   : integer range 0 to TRACE_H - 1 := 0;
    signal r_x_dot_raw    : integer range -32768 to 32767 := 0;
    signal r_y_dot_raw    : integer range -32768 to 32767 := 0;
    signal r_x_dot_rem    : integer range -(STEPS_PER_DOT - 1) to STEPS_PER_DOT - 1 := 0;
    signal r_y_dot_rem    : integer range -(STEPS_PER_DOT - 1) to STEPS_PER_DOT - 1 := 0;
    signal r_cur_addr     : integer range 0 to TRACE_PIXELS - 1 := 0;
    signal r_read_addr_int : integer range 0 to TRACE_PIXELS - 1 := 0;
    signal r_read_row_base : integer range 0 to TRACE_PIXELS - 1 := 0;
    signal r_x_mm         : integer range -9999 to 9999 := 0;
    signal r_y_mm         : integer range -9999 to 9999 := 0;
    signal r_x_mm_rem     : integer range -(STEPS_PER_MM - 1) to STEPS_PER_MM - 1 := 0;
    signal r_y_mm_rem     : integer range -(STEPS_PER_MM - 1) to STEPS_PER_MM - 1 := 0;

    signal r_trace_bit : STD_LOGIC := '0';
    signal r_trace_read_data : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal r_trace_write_data : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal r_trace_we : STD_LOGIC_VECTOR(0 downto 0) := (others => '0');
    signal r_trace_read_addr : STD_LOGIC_VECTOR(TRACE_ADDR_BITS - 1 downto 0) := (others => '0');
    signal r_trace_write_addr : STD_LOGIC_VECTOR(TRACE_ADDR_BITS - 1 downto 0) := (others => '0');
    signal r_clearing  : STD_LOGIC := '1';
    signal r_clear_addr : integer range 0 to TRACE_PIXELS - 1 := 0;
    signal r_trace_clear_sync : STD_LOGIC := '0';
    signal r_trace_clear_d : STD_LOGIC := '0';
    signal r_draw_pending : STD_LOGIC := '0';
    signal r_addr_pending : STD_LOGIC := '0';
    signal r_pen_pending : STD_LOGIC := '0';
    signal r_move_x_pos : STD_LOGIC := '0';
    signal r_move_x_neg : STD_LOGIC := '0';
    signal r_move_y_pos : STD_LOGIC := '0';
    signal r_move_y_neg : STD_LOGIC := '0';
    signal r_x_bcd_pending : STD_LOGIC := '0';
    signal r_y_bcd_pending : STD_LOGIC := '0';
    signal r_x_bcd_inc : STD_LOGIC := '1';
    signal r_y_bcd_inc : STD_LOGIC := '1';

    signal r_x_negative : STD_LOGIC := '0';
    signal r_y_negative : STD_LOGIC := '0';
    signal r_x_d3, r_x_d2, r_x_d1, r_x_d0 : t_digit := 0;
    signal r_y_d3, r_y_d2, r_y_d1, r_y_d0 : t_digit := 0;

    function abs_int(value : integer) return integer is
    begin
        if value < 0 then
            return -value;
        else
            return value;
        end if;
    end function;

    procedure inc_bcd(signal d3, d2, d1, d0 : inout t_digit) is
    begin
        if d0 < 9 then
            d0 <= d0 + 1;
        else
            d0 <= 0;
            if d1 < 9 then
                d1 <= d1 + 1;
            else
                d1 <= 0;
                if d2 < 9 then
                    d2 <= d2 + 1;
                else
                    d2 <= 0;
                    if d3 < 9 then
                        d3 <= d3 + 1;
                    end if;
                end if;
            end if;
        end if;
    end procedure;

    procedure dec_bcd(signal d3, d2, d1, d0 : inout t_digit) is
    begin
        if d0 > 0 then
            d0 <= d0 - 1;
        else
            d0 <= 9;
            if d1 > 0 then
                d1 <= d1 - 1;
            else
                d1 <= 9;
                if d2 > 0 then
                    d2 <= d2 - 1;
                else
                    d2 <= 9;
                    if d3 > 0 then
                        d3 <= d3 - 1;
                    end if;
                end if;
            end if;
        end if;
    end procedure;

    procedure update_mm_counter(
        variable mm_value : inout integer;
        variable rem_value : inout integer;
        constant delta : in integer;
        variable bcd_delta : out integer
    ) is
        variable old_abs : integer;
        variable new_abs : integer;
        variable next_rem : integer;
    begin
        bcd_delta := 0;
        old_abs := abs_int(mm_value);

        if delta > 0 then
            if rem_value = 0 and mm_value < 0 then
                mm_value := mm_value + 1;
                rem_value := -(STEPS_PER_MM - 1);
            else
                next_rem := rem_value + 1;
                if next_rem >= STEPS_PER_MM then
                    rem_value := 0;
                    if mm_value < 9999 then
                        mm_value := mm_value + 1;
                    end if;
                else
                    rem_value := next_rem;
                end if;
            end if;
        else
            if rem_value = 0 and mm_value > 0 then
                mm_value := mm_value - 1;
                rem_value := STEPS_PER_MM - 1;
            else
                next_rem := rem_value - 1;
                if next_rem <= -STEPS_PER_MM then
                    rem_value := 0;
                    if mm_value > -9999 then
                        mm_value := mm_value - 1;
                    end if;
                else
                    rem_value := next_rem;
                end if;
            end if;
        end if;

        new_abs := abs_int(mm_value);
        if new_abs > old_abs then
            bcd_delta := 1;
        elsif new_abs < old_abs then
            bcd_delta := -1;
        end if;
    end procedure;

    procedure update_dot_counter(
        variable dot_value : inout integer;
        variable rem_value : inout integer;
        constant delta : in integer
    ) is
        variable next_rem : integer;
    begin
        if delta > 0 then
            if rem_value = 0 and dot_value < 0 then
                dot_value := dot_value + 1;
                rem_value := -(STEPS_PER_DOT - 1);
            else
                next_rem := rem_value + 1;
                if next_rem >= STEPS_PER_DOT then
                    rem_value := 0;
                    if dot_value < 32767 then
                        dot_value := dot_value + 1;
                    end if;
                else
                    rem_value := next_rem;
                end if;
            end if;
        else
            if rem_value = 0 and dot_value > 0 then
                dot_value := dot_value - 1;
                rem_value := STEPS_PER_DOT - 1;
            else
                next_rem := rem_value - 1;
                if next_rem <= -STEPS_PER_DOT then
                    rem_value := 0;
                    if dot_value > -32768 then
                        dot_value := dot_value - 1;
                    end if;
                else
                    rem_value := next_rem;
                end if;
            end if;
        end if;
    end procedure;

    function clamp_raw_dot(value_dot : integer; limit : integer) return integer is
    begin
        if value_dot < 0 then
            return 0;
        elsif value_dot > limit - 1 then
            return limit - 1;
        else
            return value_dot;
        end if;
    end function;

    function clamp_dot(value_steps : integer; limit : integer) return integer is
        variable v_abs : integer;
        variable v_dot : integer;
    begin
        if value_steps < 0 then
            v_abs := 0;
        else
            v_abs := value_steps;
        end if;

        v_dot := v_abs / STEPS_PER_DOT;
        if v_dot < 0 then
            return 0;
        elsif v_dot > limit - 1 then
            return limit - 1;
        else
            return v_dot;
        end if;
    end function;

    function glyph_row(glyph : integer; row_index : integer) return STD_LOGIC_VECTOR is
        variable row_bits : STD_LOGIC_VECTOR(4 downto 0);
    begin
        row_bits := "00000";

        case glyph is
            when 0 =>
                case row_index is
                    when 0 | 6 => row_bits := "11111";
                    when others => row_bits := "10001";
                end case;
            when 1 =>
                case row_index is
                    when 0 => row_bits := "00100";
                    when 1 => row_bits := "01100";
                    when 6 => row_bits := "11111";
                    when others => row_bits := "00100";
                end case;
            when 2 =>
                case row_index is
                    when 0 | 3 | 6 => row_bits := "11111";
                    when 1 | 2 => row_bits := "00001";
                    when others => row_bits := "10000";
                end case;
            when 3 =>
                case row_index is
                    when 0 | 3 | 6 => row_bits := "11111";
                    when others => row_bits := "00001";
                end case;
            when 4 =>
                case row_index is
                    when 0 | 1 | 2 => row_bits := "10001";
                    when 3 => row_bits := "11111";
                    when others => row_bits := "00001";
                end case;
            when 5 =>
                case row_index is
                    when 0 | 3 | 6 => row_bits := "11111";
                    when 1 | 2 => row_bits := "10000";
                    when others => row_bits := "00001";
                end case;
            when 6 =>
                case row_index is
                    when 0 | 3 | 6 => row_bits := "11111";
                    when 1 | 2 => row_bits := "10000";
                    when others => row_bits := "10001";
                end case;
            when 7 =>
                case row_index is
                    when 0 => row_bits := "11111";
                    when others => row_bits := "00001";
                end case;
            when 8 =>
                case row_index is
                    when 0 | 3 | 6 => row_bits := "11111";
                    when others => row_bits := "10001";
                end case;
            when 9 =>
                case row_index is
                    when 0 | 3 | 6 => row_bits := "11111";
                    when 1 | 2 => row_bits := "10001";
                    when others => row_bits := "00001";
                end case;
            when GLYPH_X =>
                case row_index is
                    when 0 | 1 | 5 | 6 => row_bits := "10001";
                    when 2 | 4 => row_bits := "01010";
                    when others => row_bits := "00100";
                end case;
            when GLYPH_Y =>
                case row_index is
                    when 0 => row_bits := "10001";
                    when 1 => row_bits := "01010";
                    when others => row_bits := "00100";
                end case;
            when GLYPH_COLON =>
                case row_index is
                    when 1 | 2 | 4 | 5 => row_bits := "00100";
                    when others => row_bits := "00000";
                end case;
            when GLYPH_MINUS =>
                if row_index = 3 then
                    row_bits := "11111";
                end if;
            when others =>
                row_bits := "00000";
        end case;

        return row_bits;
    end function;

    function glyph_pixel(px : integer; py : integer; origin_x : integer; origin_y : integer; glyph : integer) return boolean is
        variable lx : integer;
        variable ly : integer;
        variable gx : integer;
        variable gy : integer;
        variable row_bits : STD_LOGIC_VECTOR(4 downto 0);
    begin
        if px < origin_x or px >= origin_x + GLYPH_SW or
           py < origin_y or py >= origin_y + GLYPH_SH then
            return false;
        end if;

        lx := px - origin_x;
        ly := py - origin_y;
        gx := lx / TEXT_SCALE;
        gy := ly / TEXT_SCALE;
        row_bits := glyph_row(glyph, gy);
        return row_bits(4 - gx) = '1';
    end function;

    function text_digit_x(base_x : integer; index : integer) return integer is
    begin
        return base_x + (index * (GLYPH_SW + GLYPH_GAP));
    end function;

begin

    Trace_RAM: xpm_memory_sdpram
        generic map (
            MEMORY_SIZE => TRACE_PIXELS * 8,
            MEMORY_PRIMITIVE => "block",
            CLOCKING_MODE => "common_clock",
            ECC_MODE => "no_ecc",
            MEMORY_INIT_FILE => "none",
            MEMORY_INIT_PARAM => "0",
            USE_MEM_INIT => 0,
            AUTO_SLEEP_TIME => 0,
            MESSAGE_CONTROL => 0,
            USE_EMBEDDED_CONSTRAINT => 0,
            MEMORY_OPTIMIZATION => "true",
            CASCADE_HEIGHT => 0,
            SIM_ASSERT_CHK => 0,
            WRITE_PROTECT => 0,
            WRITE_DATA_WIDTH_A => 8,
            BYTE_WRITE_WIDTH_A => 8,
            ADDR_WIDTH_A => TRACE_ADDR_BITS,
            RST_MODE_A => "SYNC",
            READ_DATA_WIDTH_B => 8,
            ADDR_WIDTH_B => TRACE_ADDR_BITS,
            READ_RESET_VALUE_B => "0",
            READ_LATENCY_B => 1,
            WRITE_MODE_B => "read_first",
            RST_MODE_B => "SYNC"
        )
        port map (
            sleep => '0',
            clka => clk,
            ena => '1',
            wea => r_trace_we,
            addra => r_trace_write_addr,
            dina => r_trace_write_data,
            injectsbiterra => '0',
            injectdbiterra => '0',
            clkb => clk,
            rstb => reset,
            enb => '1',
            regceb => '1',
            addrb => r_trace_read_addr,
            doutb => r_trace_read_data,
            sbiterrb => open,
            dbiterrb => open
        );

    process(clk, reset)
        variable v_clear_edge : boolean;
    begin
        if reset = '1' then
            r_trace_we <= (others => '0');
            r_trace_write_data <= (others => '0');
            r_trace_write_addr <= (others => '0');
            r_clearing <= '1';
            r_clear_addr <= 0;
            r_trace_clear_sync <= '0';
            r_trace_clear_d <= '0';
        elsif rising_edge(clk) then
            v_clear_edge := (r_trace_clear_sync = '1' and r_trace_clear_d = '0');

            r_trace_we <= (others => '0');
            r_trace_clear_sync <= trace_clear;
            r_trace_clear_d <= r_trace_clear_sync;

            if v_clear_edge then
                r_clearing <= '1';
                r_clear_addr <= 0;
            elsif r_clearing = '1' then
                r_trace_write_addr <= std_logic_vector(to_unsigned(r_clear_addr, TRACE_ADDR_BITS));
                r_trace_write_data <= (others => '0');
                r_trace_we <= "1";

                if r_clear_addr = TRACE_PIXELS - 1 then
                    r_clearing <= '0';
                else
                    r_clear_addr <= r_clear_addr + 1;
                end if;
            elsif r_draw_pending = '1' and r_trace_clear_sync = '0' then
                r_trace_write_addr <= std_logic_vector(to_unsigned(r_cur_addr, TRACE_ADDR_BITS));
                r_trace_write_data <= x"FF";
                r_trace_we <= "1";
            end if;
        end if;
    end process;

    process(clk, reset)
        variable v_clear_edge : boolean;
    begin
        if reset = '1' then
            r_x_d3 <= 0; r_x_d2 <= 0; r_x_d1 <= 0; r_x_d0 <= 0;
            r_y_d3 <= 0; r_y_d2 <= 0; r_y_d1 <= 0; r_y_d0 <= 0;
        elsif rising_edge(clk) then
            v_clear_edge := (r_trace_clear_sync = '1' and r_trace_clear_d = '0');

            if v_clear_edge then
                r_x_d3 <= 0; r_x_d2 <= 0; r_x_d1 <= 0; r_x_d0 <= 0;
                r_y_d3 <= 0; r_y_d2 <= 0; r_y_d1 <= 0; r_y_d0 <= 0;
            else
                if r_x_bcd_pending = '1' then
                    if r_x_bcd_inc = '1' then
                        inc_bcd(r_x_d3, r_x_d2, r_x_d1, r_x_d0);
                    else
                        dec_bcd(r_x_d3, r_x_d2, r_x_d1, r_x_d0);
                    end if;
                end if;

                if r_y_bcd_pending = '1' then
                    if r_y_bcd_inc = '1' then
                        inc_bcd(r_y_d3, r_y_d2, r_y_d1, r_y_d0);
                    else
                        dec_bcd(r_y_d3, r_y_d2, r_y_d1, r_y_d0);
                    end if;
                end if;
            end if;
        end if;
    end process;

    process(clk, reset)
        variable v_next_x_mm : integer range -9999 to 9999;
        variable v_next_y_mm : integer range -9999 to 9999;
        variable v_next_x_rem : integer range -(STEPS_PER_MM - 1) to STEPS_PER_MM - 1;
        variable v_next_y_rem : integer range -(STEPS_PER_MM - 1) to STEPS_PER_MM - 1;
        variable v_next_x_dot_raw : integer range -32768 to 32767;
        variable v_next_y_dot_raw : integer range -32768 to 32767;
        variable v_next_x_dot_rem : integer range -(STEPS_PER_DOT - 1) to STEPS_PER_DOT - 1;
        variable v_next_y_dot_rem : integer range -(STEPS_PER_DOT - 1) to STEPS_PER_DOT - 1;
        variable v_dot_x  : integer range 0 to TRACE_W - 1;
        variable v_dot_y  : integer range 0 to TRACE_H - 1;
        variable v_next_addr : integer range 0 to TRACE_PIXELS - 1;
        variable v_next_read_addr : integer range 0 to TRACE_PIXELS - 1;
        variable v_next_row_base : integer range 0 to TRACE_PIXELS - 1;
        variable v_next_h : integer range 0 to H_TOTAL - 1;
        variable v_next_v : integer range 0 to V_TOTAL - 1;
        variable v_clear_edge : boolean;
        variable v_x_bcd_delta : integer range -1 to 1;
        variable v_y_bcd_delta : integer range -1 to 1;
    begin
        if reset = '1' then
            r_pixel_div <= (others => '0');
            r_h_count <= 0;
            r_v_count <= 0;
            r_cur_dot_x <= 0;
            r_cur_dot_y <= 0;
            r_x_dot_raw <= 0;
            r_y_dot_raw <= 0;
            r_x_dot_rem <= 0;
            r_y_dot_rem <= 0;
            r_cur_addr <= 0;
            r_read_addr_int <= 0;
            r_read_row_base <= 0;
            r_x_mm <= 0;
            r_y_mm <= 0;
            r_x_mm_rem <= 0;
            r_y_mm_rem <= 0;
            r_trace_bit <= '0';
            r_trace_read_addr <= (others => '0');
            r_draw_pending <= '0';
            r_addr_pending <= '0';
            r_pen_pending <= '0';
            r_move_x_pos <= '0';
            r_move_x_neg <= '0';
            r_move_y_pos <= '0';
            r_move_y_neg <= '0';
            r_x_bcd_pending <= '0';
            r_y_bcd_pending <= '0';
            r_x_bcd_inc <= '1';
            r_y_bcd_inc <= '1';
            r_x_negative <= '0';
            r_y_negative <= '0';
        elsif rising_edge(clk) then
            v_next_x_mm := r_x_mm;
            v_next_y_mm := r_y_mm;
            v_next_x_rem := r_x_mm_rem;
            v_next_y_rem := r_y_mm_rem;
            v_next_x_dot_raw := r_x_dot_raw;
            v_next_y_dot_raw := r_y_dot_raw;
            v_next_x_dot_rem := r_x_dot_rem;
            v_next_y_dot_rem := r_y_dot_rem;
            v_next_addr := r_cur_addr;
            v_next_read_addr := r_read_addr_int;
            v_next_row_base := r_read_row_base;
            v_clear_edge := (r_trace_clear_sync = '1' and r_trace_clear_d = '0');
            v_x_bcd_delta := 0;
            v_y_bcd_delta := 0;
            r_draw_pending <= '0';
            r_addr_pending <= '0';
            r_pen_pending <= '0';
            r_move_x_pos <= '0';
            r_move_x_neg <= '0';
            r_move_y_pos <= '0';
            r_move_y_neg <= '0';
            r_x_bcd_pending <= '0';
            r_y_bcd_pending <= '0';

            if v_clear_edge then
                r_cur_dot_x <= 0;
                r_cur_dot_y <= 0;
                r_x_dot_raw <= 0;
                r_y_dot_raw <= 0;
                r_x_dot_rem <= 0;
                r_y_dot_rem <= 0;
                r_cur_addr <= 0;
                r_x_mm <= 0;
                r_y_mm <= 0;
                r_x_mm_rem <= 0;
                r_y_mm_rem <= 0;
                r_x_negative <= '0';
                r_y_negative <= '0';
                v_next_x_mm := 0;
                v_next_y_mm := 0;
                v_next_x_rem := 0;
                v_next_y_rem := 0;
                v_next_x_dot_raw := 0;
                v_next_y_dot_raw := 0;
                v_next_x_dot_rem := 0;
                v_next_y_dot_rem := 0;
                v_next_addr := 0;
                r_addr_pending <= '0';
                r_pen_pending <= '0';
                r_move_x_pos <= '0';
                r_move_x_neg <= '0';
                r_move_y_pos <= '0';
                r_move_y_neg <= '0';
                r_x_bcd_pending <= '0';
                r_y_bcd_pending <= '0';
            else
                if r_addr_pending = '1' then
                    if r_move_x_pos = '1' and v_next_addr < TRACE_PIXELS - 1 then
                        v_next_addr := v_next_addr + 1;
                    elsif r_move_x_neg = '1' and v_next_addr > 0 then
                        v_next_addr := v_next_addr - 1;
                    end if;

                    if r_move_y_pos = '1' and v_next_addr <= TRACE_PIXELS - TRACE_W - 1 then
                        v_next_addr := v_next_addr + TRACE_W;
                    elsif r_move_y_neg = '1' and v_next_addr >= TRACE_W then
                        v_next_addr := v_next_addr - TRACE_W;
                    end if;

                    if r_pen_pending = '1' then
                        r_draw_pending <= '1';
                    end if;
                end if;

                if r_clearing = '0' then
                    if pen_update = '1' and pen_down = '1' then
                        r_draw_pending <= '1';
                    end if;

                    if step_x_pulse = '1' then
                        r_x_bcd_inc <= dir_x;
                        if dir_x = '1' then
                            update_mm_counter(v_next_x_mm, v_next_x_rem, 1, v_x_bcd_delta);
                            update_dot_counter(v_next_x_dot_raw, v_next_x_dot_rem, 1);
                        else
                            update_mm_counter(v_next_x_mm, v_next_x_rem, -1, v_x_bcd_delta);
                            update_dot_counter(v_next_x_dot_raw, v_next_x_dot_rem, -1);
                        end if;
                    end if;

                    if step_y_pulse = '1' then
                        r_y_bcd_inc <= dir_y;
                        if dir_y = '1' then
                            update_mm_counter(v_next_y_mm, v_next_y_rem, 1, v_y_bcd_delta);
                            update_dot_counter(v_next_y_dot_raw, v_next_y_dot_rem, 1);
                        else
                            update_mm_counter(v_next_y_mm, v_next_y_rem, -1, v_y_bcd_delta);
                            update_dot_counter(v_next_y_dot_raw, v_next_y_dot_rem, -1);
                        end if;
                    end if;

                    if v_x_bcd_delta > 0 then
                        r_x_bcd_pending <= '1';
                    elsif v_x_bcd_delta < 0 then
                        r_x_bcd_pending <= '1';
                    end if;

                    if v_y_bcd_delta > 0 then
                        r_y_bcd_pending <= '1';
                    elsif v_y_bcd_delta < 0 then
                        r_y_bcd_pending <= '1';
                    end if;

                    if step_x_pulse = '1' or step_y_pulse = '1' then
                        v_dot_x := clamp_raw_dot(v_next_x_dot_raw, TRACE_W);
                        v_dot_y := clamp_raw_dot(v_next_y_dot_raw, TRACE_H);

                        if v_dot_x > r_cur_dot_x then
                            r_move_x_pos <= '1';
                        elsif v_dot_x < r_cur_dot_x then
                            r_move_x_neg <= '1';
                        end if;

                        if v_dot_y > r_cur_dot_y then
                            r_move_y_pos <= '1';
                        elsif v_dot_y < r_cur_dot_y then
                            r_move_y_neg <= '1';
                        end if;

                        r_pen_pending <= pen_down;
                        r_addr_pending <= '1';
                    end if;
                end if;

                v_dot_x := clamp_raw_dot(v_next_x_dot_raw, TRACE_W);
                v_dot_y := clamp_raw_dot(v_next_y_dot_raw, TRACE_H);
                r_cur_dot_x <= v_dot_x;
                r_cur_dot_y <= v_dot_y;
                r_x_dot_raw <= v_next_x_dot_raw;
                r_y_dot_raw <= v_next_y_dot_raw;
                r_x_dot_rem <= v_next_x_dot_rem;
                r_y_dot_rem <= v_next_y_dot_rem;
                r_cur_addr <= v_next_addr;
                r_x_mm <= v_next_x_mm;
                r_y_mm <= v_next_y_mm;
                r_x_mm_rem <= v_next_x_rem;
                r_y_mm_rem <= v_next_y_rem;

                if v_next_x_mm < 0 or v_next_x_rem < 0 then
                    r_x_negative <= '1';
                else
                    r_x_negative <= '0';
                end if;

                if v_next_y_mm < 0 or v_next_y_rem < 0 then
                    r_y_negative <= '1';
                else
                    r_y_negative <= '0';
                end if;
            end if;

            if r_h_count < H_VISIBLE and r_v_count < TRACE_SCREEN_H then
                r_trace_read_addr <= std_logic_vector(to_unsigned(r_read_addr_int, TRACE_ADDR_BITS));
                r_trace_bit <= r_trace_read_data(0);
            else
                r_trace_bit <= '0';
            end if;

            if r_pixel_div = "11" then
                r_pixel_div <= (others => '0');
                if r_h_count = H_TOTAL - 1 then
                    v_next_h := 0;
                    if r_v_count = V_TOTAL - 1 then
                        v_next_v := 0;
                    else
                        v_next_v := r_v_count + 1;
                    end if;
                else
                    v_next_h := r_h_count + 1;
                    v_next_v := r_v_count;
                end if;

                if r_h_count = H_TOTAL - 1 then
                    if v_next_v = 0 then
                        v_next_row_base := 0;
                    elsif v_next_v < TRACE_SCREEN_H and (v_next_v mod 2) = 0 and
                          r_read_row_base <= TRACE_PIXELS - TRACE_W - 1 then
                        v_next_row_base := r_read_row_base + TRACE_W;
                    end if;
                end if;

                if v_next_h < H_VISIBLE and v_next_v < TRACE_SCREEN_H then
                    if v_next_h = 0 then
                        v_next_read_addr := v_next_row_base;
                    elsif (v_next_h mod 2) = 0 and v_next_read_addr < TRACE_PIXELS - 1 then
                        v_next_read_addr := v_next_read_addr + 1;
                    end if;
                end if;

                r_h_count <= v_next_h;
                r_v_count <= v_next_v;
                r_read_addr_int <= v_next_read_addr;
                r_read_row_base <= v_next_row_base;
            else
                r_pixel_div <= r_pixel_div + 1;
            end if;
        end if;
    end process;

    Hsync <= '0' when (r_h_count >= H_VISIBLE + H_FRONT_PORCH and
                       r_h_count <  H_VISIBLE + H_FRONT_PORCH + H_SYNC_PULSE) else '1';
    Vsync <= '0' when (r_v_count >= V_VISIBLE + V_FRONT_PORCH and
                       r_v_count <  V_VISIBLE + V_FRONT_PORCH + V_SYNC_PULSE) else '1';

    process(r_h_count, r_v_count, r_trace_bit, r_cur_dot_x, r_cur_dot_y,
            r_x_negative, r_y_negative, r_x_d3, r_x_d2, r_x_d1, r_x_d0,
            r_y_d3, r_y_d2, r_y_d1, r_y_d0, r_clearing)
        variable v_active : boolean;
        variable v_trace_area : boolean;
        variable v_grid : boolean;
        variable v_cursor : boolean;
        variable v_text : boolean;
        variable v_sign_x : integer;
        variable v_sign_y : integer;
        variable v_cursor_x : integer;
        variable v_cursor_y : integer;
    begin
        v_active := (r_h_count < H_VISIBLE and r_v_count < V_VISIBLE);
        v_trace_area := (r_h_count < H_VISIBLE and r_v_count < TRACE_SCREEN_H);
        v_grid := false;
        v_cursor := false;
        v_text := false;

        if r_x_negative = '1' then
            v_sign_x := GLYPH_MINUS;
        else
            v_sign_x := GLYPH_BLANK;
        end if;

        if r_y_negative = '1' then
            v_sign_y := GLYPH_MINUS;
        else
            v_sign_y := GLYPH_BLANK;
        end if;

        if v_trace_area then
            v_grid := (((r_h_count / 2) mod 20) = 0) or (((r_v_count / 2) mod 20) = 0);
            v_cursor_x := (r_cur_dot_x * 2) + 1;
            v_cursor_y := (r_cur_dot_y * 2) + 1;
            v_cursor := abs_int(r_h_count - v_cursor_x) <= 4 and
                        abs_int(r_v_count - v_cursor_y) <= 4;
        end if;

        v_text := glyph_pixel(r_h_count, r_v_count, text_digit_x(X_TEXT_X0, 0), TEXT_Y0, GLYPH_X) or
                  glyph_pixel(r_h_count, r_v_count, text_digit_x(X_TEXT_X0, 1), TEXT_Y0, GLYPH_COLON) or
                  glyph_pixel(r_h_count, r_v_count, text_digit_x(X_TEXT_X0, 2), TEXT_Y0, v_sign_x) or
                  glyph_pixel(r_h_count, r_v_count, text_digit_x(X_TEXT_X0, 3), TEXT_Y0, r_x_d3) or
                  glyph_pixel(r_h_count, r_v_count, text_digit_x(X_TEXT_X0, 4), TEXT_Y0, r_x_d2) or
                  glyph_pixel(r_h_count, r_v_count, text_digit_x(X_TEXT_X0, 5), TEXT_Y0, r_x_d1) or
                  glyph_pixel(r_h_count, r_v_count, text_digit_x(X_TEXT_X0, 6), TEXT_Y0, r_x_d0) or
                  glyph_pixel(r_h_count, r_v_count, text_digit_x(Y_TEXT_X0, 0), TEXT_Y0, GLYPH_Y) or
                  glyph_pixel(r_h_count, r_v_count, text_digit_x(Y_TEXT_X0, 1), TEXT_Y0, GLYPH_COLON) or
                  glyph_pixel(r_h_count, r_v_count, text_digit_x(Y_TEXT_X0, 2), TEXT_Y0, v_sign_y) or
                  glyph_pixel(r_h_count, r_v_count, text_digit_x(Y_TEXT_X0, 3), TEXT_Y0, r_y_d3) or
                  glyph_pixel(r_h_count, r_v_count, text_digit_x(Y_TEXT_X0, 4), TEXT_Y0, r_y_d2) or
                  glyph_pixel(r_h_count, r_v_count, text_digit_x(Y_TEXT_X0, 5), TEXT_Y0, r_y_d1) or
                  glyph_pixel(r_h_count, r_v_count, text_digit_x(Y_TEXT_X0, 6), TEXT_Y0, r_y_d0);

        if not v_active then
            vgaRed   <= "0000";
            vgaGreen <= "0000";
            vgaBlue  <= "0000";
        elsif v_text then
            vgaRed   <= "1111";
            vgaGreen <= "1111";
            vgaBlue  <= "1111";
        elsif r_v_count >= TRACE_SCREEN_H then
            vgaRed   <= "0000";
            vgaGreen <= "0010";
            vgaBlue  <= "0011";
        elsif v_cursor then
            vgaRed   <= "1111";
            vgaGreen <= "1010";
            vgaBlue  <= "0000";
        elsif r_trace_bit = '1' then
            vgaRed   <= "0010";
            vgaGreen <= "1111";
            vgaBlue  <= "0100";
        elsif r_clearing = '1' and v_grid then
            vgaRed   <= "0010";
            vgaGreen <= "0010";
            vgaBlue  <= "0110";
        elsif v_grid then
            vgaRed   <= "0001";
            vgaGreen <= "0011";
            vgaBlue  <= "0100";
        else
            vgaRed   <= "0000";
            vgaGreen <= "0001";
            vgaBlue  <= "0010";
        end if;
    end process;

end Behavioral;
