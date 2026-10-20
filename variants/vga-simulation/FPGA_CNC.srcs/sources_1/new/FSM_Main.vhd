----------------------------------------------------------------------------------
-- Controlador del protocolo CNC fiable
--
-- Trama de comando (9 bytes):
--   [0]  0xAA
--   [1]  flags: bit0 dir_x, bit1 dir_y, bit2 pen, bit3 homing
--   [2]  steps_x MSB
--   [3]  steps_x LSB
--   [4]  steps_y MSB
--   [5]  steps_y LSB
--   [6]  secuencia MSB
--   [7]  secuencia LSB
--   [8]  checksum XOR de los bytes 0..7
--
-- Trama de respuesta (5 bytes):
--   [0]  0x55
--   [1]  estado: A=aceptado, R=ejecutando, K=terminado, B=ocupado,
--                C=error CRC, F=error UART framing, T=timeout de trama
--   [2]  secuencia MSB
--   [3]  secuencia LSB
--   [4]  checksum XOR de los bytes 0..3
--
-- La secuencia hace que la retransmision sea idempotente: repetir el mismo
-- comando nunca ejecuta el movimiento dos veces. Si hay un comando activo,
-- una trama repetida responde R. Tras terminar, responde K en cache.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fsm_main is
    Generic (
        CLK_FREQ_HZ        : positive := 100000000;
        RX_GAP_TIMEOUT_MS  : positive := 5;
        RESPONSE_QUEUE_LEN : positive := 4
    );
    Port (
        clk          : in  STD_LOGIC;
        reset        : in  STD_LOGIC;

        rx_data      : in  STD_LOGIC_VECTOR(7 downto 0);
        rx_ready     : in  STD_LOGIC;
        rx_error     : in  STD_LOGIC;

        tx_data      : out STD_LOGIC_VECTOR(7 downto 0);
        tx_start     : out STD_LOGIC;
        tx_active    : in  STD_LOGIC;
        tx_done      : in  STD_LOGIC;

        dir_x        : out STD_LOGIC;
        dir_y        : out STD_LOGIC;
        pen_state    : out STD_LOGIC;
        pen_update   : out STD_LOGIC;
        steps_x      : out STD_LOGIC_VECTOR(15 downto 0);
        steps_y      : out STD_LOGIC_VECTOR(15 downto 0);
        start_motion : out STD_LOGIC;
        motion_done  : in  STD_LOGIC;
        is_homing    : out STD_LOGIC
    );
end fsm_main;

architecture Behavioral of fsm_main is

    function max_positive(a : positive; b : natural) return positive is
    begin
        if b < a then
            return a;
        end if;
        return b;
    end function;

    function next_index(current : natural; depth : positive) return natural is
    begin
        if current = depth - 1 then
            return 0;
        end if;
        return current + 1;
    end function;

    constant C_CMD_SYNC      : STD_LOGIC_VECTOR(7 downto 0) := x"AA";
    constant C_RESP_SYNC     : STD_LOGIC_VECTOR(7 downto 0) := x"55";
    constant C_STATUS_ACCEPT : STD_LOGIC_VECTOR(7 downto 0) := x"41"; -- A
    constant C_STATUS_RUN    : STD_LOGIC_VECTOR(7 downto 0) := x"52"; -- R
    constant C_STATUS_DONE   : STD_LOGIC_VECTOR(7 downto 0) := x"4B"; -- K
    constant C_STATUS_BUSY   : STD_LOGIC_VECTOR(7 downto 0) := x"42"; -- B
    constant C_STATUS_CRC    : STD_LOGIC_VECTOR(7 downto 0) := x"43"; -- C
    constant C_STATUS_FRAME  : STD_LOGIC_VECTOR(7 downto 0) := x"46"; -- F
    constant C_STATUS_GAP    : STD_LOGIC_VECTOR(7 downto 0) := x"54"; -- T
    constant C_UNKNOWN_SEQ   : STD_LOGIC_VECTOR(15 downto 0) := x"FFFF";

    constant C_RX_GAP_CYCLES : positive := max_positive(
        1,
        (CLK_FREQ_HZ / 1000) * RX_GAP_TIMEOUT_MS
    );

    type t_rx_state is (RX_WAIT_SYNC, RX_RECEIVE);
    type t_tx_state is (TX_IDLE, TX_LAUNCH, TX_WAIT_ACTIVE, TX_WAIT_DONE);
    type t_byte_array_9 is array (0 to 8) of STD_LOGIC_VECTOR(7 downto 0);
    type t_byte_array_5 is array (0 to 4) of STD_LOGIC_VECTOR(7 downto 0);
    type t_status_queue is array (natural range <>) of STD_LOGIC_VECTOR(7 downto 0);
    type t_seq_queue is array (natural range <>) of STD_LOGIC_VECTOR(15 downto 0);

    signal r_rx_state    : t_rx_state := RX_WAIT_SYNC;
    signal r_rx_buffer   : t_byte_array_9 := (others => (others => '0'));
    signal r_byte_count  : natural range 0 to 8 := 0;
    signal r_checksum    : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal r_gap_count   : natural range 0 to C_RX_GAP_CYCLES - 1 := 0;

    signal r_exec_active : STD_LOGIC := '0';
    signal r_current_seq : STD_LOGIC_VECTOR(15 downto 0) := (others => '0');
    signal r_last_valid  : STD_LOGIC := '0';
    signal r_last_seq    : STD_LOGIC_VECTOR(15 downto 0) := (others => '0');
    signal r_is_homing   : STD_LOGIC := '0';

    signal r_q_status : t_status_queue(0 to RESPONSE_QUEUE_LEN - 1) :=
        (others => C_STATUS_DONE);
    signal r_q_seq    : t_seq_queue(0 to RESPONSE_QUEUE_LEN - 1) :=
        (others => (others => '0'));
    signal r_q_write  : natural range 0 to RESPONSE_QUEUE_LEN - 1 := 0;
    signal r_q_read   : natural range 0 to RESPONSE_QUEUE_LEN - 1 := 0;
    signal r_q_count  : natural range 0 to RESPONSE_QUEUE_LEN := 0;

    signal r_tx_state : t_tx_state := TX_IDLE;
    signal r_tx_frame : t_byte_array_5 := (others => (others => '0'));
    signal r_tx_index : natural range 0 to 4 := 0;

begin

    is_homing <= r_is_homing;

    process(clk, reset)
        variable v_push          : boolean;
        variable v_push_status   : STD_LOGIC_VECTOR(7 downto 0);
        variable v_push_seq      : STD_LOGIC_VECTOR(15 downto 0);
        variable v_seq           : STD_LOGIC_VECTOR(15 downto 0);
        variable v_q_write       : natural range 0 to RESPONSE_QUEUE_LEN - 1;
        variable v_q_read        : natural range 0 to RESPONSE_QUEUE_LEN - 1;
        variable v_q_count       : natural range 0 to RESPONSE_QUEUE_LEN;
        variable v_exec_active   : STD_LOGIC;
        variable v_current_seq   : STD_LOGIC_VECTOR(15 downto 0);
        variable v_last_valid    : STD_LOGIC;
        variable v_last_seq      : STD_LOGIC_VECTOR(15 downto 0);
        variable v_is_homing     : STD_LOGIC;
        variable v_status        : STD_LOGIC_VECTOR(7 downto 0);
        variable v_response_seq  : STD_LOGIC_VECTOR(15 downto 0);
    begin
        if reset = '1' then
            r_rx_state    <= RX_WAIT_SYNC;
            r_rx_buffer   <= (others => (others => '0'));
            r_byte_count  <= 0;
            r_checksum    <= (others => '0');
            r_gap_count   <= 0;

            r_exec_active <= '0';
            r_current_seq <= (others => '0');
            r_last_valid  <= '0';
            r_last_seq    <= (others => '0');
            r_is_homing   <= '0';

            r_q_status    <= (others => C_STATUS_DONE);
            r_q_seq       <= (others => (others => '0'));
            r_q_write     <= 0;
            r_q_read      <= 0;
            r_q_count     <= 0;

            r_tx_state    <= TX_IDLE;
            r_tx_frame    <= (others => (others => '0'));
            r_tx_index    <= 0;

            tx_data       <= (others => '0');
            tx_start      <= '0';
            dir_x         <= '0';
            dir_y         <= '0';
            pen_state     <= '0';
            pen_update    <= '0';
            steps_x       <= (others => '0');
            steps_y       <= (others => '0');
            start_motion  <= '0';

        elsif rising_edge(clk) then
            tx_start     <= '0';
            start_motion <= '0';
            pen_update   <= '0';

            v_push         := false;
            v_push_status  := C_STATUS_FRAME;
            v_push_seq     := C_UNKNOWN_SEQ;
            v_q_write      := r_q_write;
            v_q_read       := r_q_read;
            v_q_count      := r_q_count;
            v_exec_active  := r_exec_active;
            v_current_seq  := r_current_seq;
            v_last_valid   := r_last_valid;
            v_last_seq     := r_last_seq;
            v_is_homing    := r_is_homing;

            ------------------------------------------------------------------
            -- La finalizacion del movimiento tiene maxima prioridad de respuesta.
            ------------------------------------------------------------------
            if v_exec_active = '1' and motion_done = '1' then
                v_exec_active := '0';
                v_last_valid  := '1';
                v_last_seq    := v_current_seq;
                v_is_homing   := '0';
                v_push        := true;
                v_push_status := C_STATUS_DONE;
                v_push_seq    := v_current_seq;
            end if;

            ------------------------------------------------------------------
            -- Receptor UART de tramas. Sigue activo durante el movimiento,
            -- asi retransmitir la misma secuencia funciona como consulta segura.
            ------------------------------------------------------------------
            case r_rx_state is
                when RX_WAIT_SYNC =>
                    r_gap_count <= 0;
                    if rx_ready = '1' and rx_data = C_CMD_SYNC then
                        r_rx_buffer(0) <= rx_data;
                        r_checksum     <= rx_data;
                        r_byte_count   <= 1;
                        r_rx_state     <= RX_RECEIVE;
                    end if;

                when RX_RECEIVE =>
                    if rx_error = '1' then
                        r_rx_state   <= RX_WAIT_SYNC;
                        r_byte_count <= 0;
                        r_checksum   <= (others => '0');
                        r_gap_count  <= 0;

                        if not v_push then
                            v_push        := true;
                            v_push_status := C_STATUS_FRAME;
                            v_push_seq    := C_UNKNOWN_SEQ;
                        end if;

                    elsif rx_ready = '1' then
                        r_gap_count <= 0;

                        if r_byte_count = 8 then
                            -- r_checksum ya contiene XOR(bytes 0..7).
                            v_seq := r_rx_buffer(6) & r_rx_buffer(7);
                            r_rx_state   <= RX_WAIT_SYNC;
                            r_byte_count <= 0;

                            if r_checksum = rx_data then
                                if v_exec_active = '1' then
                                    if v_seq = v_current_seq then
                                        if not v_push then
                                            v_push        := true;
                                            v_push_status := C_STATUS_RUN;
                                            v_push_seq    := v_seq;
                                        end if;
                                    else
                                        if not v_push then
                                            v_push        := true;
                                            v_push_status := C_STATUS_BUSY;
                                            v_push_seq    := v_seq;
                                        end if;
                                    end if;

                                elsif v_last_valid = '1' and v_seq = v_last_seq then
                                    -- Repeticion de ACK: el movimiento no se ejecuta de nuevo.
                                    if not v_push then
                                        v_push        := true;
                                        v_push_status := C_STATUS_DONE;
                                        v_push_seq    := v_seq;
                                    end if;

                                else
                                    -- Comando nuevo: cargar parametros atomicamente.
                                    dir_x        <= r_rx_buffer(1)(0);
                                    dir_y        <= r_rx_buffer(1)(1);
                                    pen_state    <= r_rx_buffer(1)(2);
                                    steps_x      <= r_rx_buffer(2) & r_rx_buffer(3);
                                    steps_y      <= r_rx_buffer(4) & r_rx_buffer(5);
                                    pen_update   <= '1';
                                    start_motion <= '1';

                                    v_exec_active := '1';
                                    v_current_seq := v_seq;
                                    v_is_homing   := r_rx_buffer(1)(3);

                                    if not v_push then
                                        v_push        := true;
                                        v_push_status := C_STATUS_ACCEPT;
                                        v_push_seq    := v_seq;
                                    end if;
                                end if;

                            else
                                if not v_push then
                                    v_push        := true;
                                    v_push_status := C_STATUS_CRC;
                                    v_push_seq    := v_seq;
                                end if;
                            end if;

                        else
                            r_rx_buffer(r_byte_count) <= rx_data;
                            r_checksum                <= r_checksum xor rx_data;
                            r_byte_count              <= r_byte_count + 1;
                        end if;

                    else
                        if r_gap_count = C_RX_GAP_CYCLES - 1 then
                            r_rx_state   <= RX_WAIT_SYNC;
                            r_byte_count <= 0;
                            r_checksum   <= (others => '0');
                            r_gap_count  <= 0;

                            if not v_push then
                                v_push        := true;
                                v_push_status := C_STATUS_GAP;
                                v_push_seq    := C_UNKNOWN_SEQ;
                            end if;
                        else
                            r_gap_count <= r_gap_count + 1;
                        end if;
                    end if;
            end case;

            ------------------------------------------------------------------
            -- Serializador UART de respuestas. Cada respuesta en cola se envia como
            -- trama de 5 bytes con checksum y handshake tx_active/tx_done.
            ------------------------------------------------------------------
            case r_tx_state is
                when TX_IDLE =>
                    if tx_active = '0' and v_q_count > 0 then
                        v_status       := r_q_status(v_q_read);
                        v_response_seq := r_q_seq(v_q_read);

                        r_tx_frame(0) <= C_RESP_SYNC;
                        r_tx_frame(1) <= v_status;
                        r_tx_frame(2) <= v_response_seq(15 downto 8);
                        r_tx_frame(3) <= v_response_seq(7 downto 0);
                        r_tx_frame(4) <= C_RESP_SYNC xor v_status xor
                                         v_response_seq(15 downto 8) xor
                                         v_response_seq(7 downto 0);
                        r_tx_index <= 0;
                        r_tx_state <= TX_LAUNCH;

                        v_q_read  := next_index(v_q_read, RESPONSE_QUEUE_LEN);
                        v_q_count := v_q_count - 1;
                    end if;

                when TX_LAUNCH =>
                    if tx_active = '0' then
                        tx_data   <= r_tx_frame(r_tx_index);
                        tx_start  <= '1';
                        r_tx_state <= TX_WAIT_ACTIVE;
                    end if;

                when TX_WAIT_ACTIVE =>
                    if tx_active = '1' then
                        r_tx_state <= TX_WAIT_DONE;
                    end if;

                when TX_WAIT_DONE =>
                    if tx_done = '1' then
                        if r_tx_index = 4 then
                            r_tx_index <= 0;
                            r_tx_state <= TX_IDLE;
                        else
                            r_tx_index <= r_tx_index + 1;
                            r_tx_state <= TX_LAUNCH;
                        end if;
                    end if;
            end case;

            ------------------------------------------------------------------
            -- Encolar como maximo una respuesta por ciclo. Con un solo comando pendiente
            -- del PC, profundidad cuatro es suficiente; un pop simultaneo libera espacio.
            ------------------------------------------------------------------
            if v_push and v_q_count < RESPONSE_QUEUE_LEN then
                r_q_status(v_q_write) <= v_push_status;
                r_q_seq(v_q_write)    <= v_push_seq;
                v_q_write             := next_index(v_q_write, RESPONSE_QUEUE_LEN);
                v_q_count             := v_q_count + 1;
            end if;

            r_q_write     <= v_q_write;
            r_q_read      <= v_q_read;
            r_q_count     <= v_q_count;
            r_exec_active <= v_exec_active;
            r_current_seq <= v_current_seq;
            r_last_valid  <= v_last_valid;
            r_last_seq    <= v_last_seq;
            r_is_homing   <= v_is_homing;
        end if;
    end process;

end Behavioral;
