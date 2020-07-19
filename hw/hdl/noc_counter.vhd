----------------------------------------------------------------------------------
-- Company: 
-- Engineer: Alexandre Amory
-- 
-- Create Date: 06/07/2020 05:41:32 PM

-- Description: 
-- It receives a hermes packet, increments its payload, and sends the packet back to the source IP.
-- to perform this, it's required to buffer the input packet and invert the order of the 3 1st flits.

-- This means that the 3rd flit of the incomming packet will be the outgoing packet header and 
-- The incomming packet header will be the 3rd flit of the outgoing packet

-- Incomming packet format:
-- self_addr (header) | size | source    | payload of size-1 flits
--
-- Incomming packet format:
-- source (header)    | size | self_addr | payload of size-1 flits
--
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

entity noc_counter is
generic (
    INC_VALUE : integer := 1
);
port ( 
	clock     : in  std_logic;
	reset_n   : in  std_logic;  
	-- axi slave streaming interface
	s_valid_i : in  std_logic;
	s_ready_o : out std_logic;
	s_last_i  : in  std_logic;
	s_data_i  : in  std_logic_vector(31 downto 0);

	-- axi master streaming interface
	m_valid_o : out std_logic;
	m_ready_i : in  std_logic; -- TODO, this port is not used and it will cause error when Noc has congestion
	m_last_o  : out std_logic;
	m_data_o  : out std_logic_vector(31 downto 0)
);
end noc_counter;

architecture Behavioral of noc_counter is

constant FIFO_SIZE : integer := 3; 

-- incomming packet fsm
type State_in_type IS (IDLE_IN, GET_SIZE, GET_STORE_SOURCE, WAIT_LAST_FLIT); 
signal state_in : State_in_Type;    

-- outgoing packet fsm
type State_out_type IS (IDLE_OUT, SEND_HEADER, SEND_SIZE, SEND_SOURCE, INCREMENTING); 
signal state_out : State_out_type;    

-- fsm to get both in and out fsm in sync
type State_handshake_type IS (WAIT_IN_PACKET, WAIT_OUT_PACKET); 
signal state_handshake : State_handshake_type;    

signal can_send      : std_logic;

-- get the source of the incomming packet , which will be the target of the outgoing packet
signal source_addr : std_logic_vector(15 downto 0);
-- get the header of the incomming packet , which will be the source of the outgoing packet
signal self_addr   : std_logic_vector(15 downto 0);
signal size : std_logic_vector(15 downto 0);

signal s_ready_s    : std_logic;

-- fifo signals
signal fifo_wr      : std_logic;
signal fifo_data_in : std_logic_vector(32 downto 0);
signal fifo_full    : std_logic;
signal fifo_rd      : std_logic;
signal fifo_data_out: std_logic_vector(32 downto 0);
signal fifo_empty   : std_logic;

--attribute KEEP : string;
--attribute MARK_DEBUG : string;
--
--attribute KEEP of state : signal is "TRUE";
---- in verilog: (* keep = "true" *) wire signal_name;
--attribute MARK_DEBUG of state : signal is "TRUE";
--

begin

    ----------------------------------------
    -- INPUT PACKET PROCESSING
    ----------------------------------------
    u_fifo: entity work.fifo
      generic map(
        g_WIDTH => 33,
        g_DEPTH => 8
        )
      port map(
        i_rst_sync => reset_n,
        i_clk      => clock,
     
        -- FIFO Write Interface
        i_wr_en   => fifo_wr,
        i_wr_data => fifo_data_in,
        o_full    => fifo_full,
     
        -- FIFO Read Interface
        i_rd_en   => fifo_rd,
        o_rd_data => fifo_data_out,
        o_empty   => fifo_empty
        );
 
    -- write data from the master port into the fifo
--    process(clock, reset_n)
--    begin
--        if (reset_n = '0') then 
--            fifo_data_in <= (others => '0');
--            fifo_wr <= '0';
--        elsif (clock'event and clock = '1') then
--            if s_ready_s = '1' then 
--                fifo_data_in <= s_last_i & s_data_i;
--                fifo_wr <= '1';
--            else
--                fifo_data_in <= (others => '0');
--                fifo_wr <= '0';
--            end if;
--        end if;
--    end process;
    
    -- accepts incomming data as long as the master wants to write and the fifo is not full
    s_ready_s <= s_valid_i and not fifo_full;
    s_ready_o <= '1' when s_ready_s = '1' and state_handshake = WAIT_IN_PACKET else '0';
    
    -- get the packet size and the target address for the response packet
    process(clock, reset_n)
    begin
        if (reset_n = '0') then 
            state_in <= IDLE_IN;
            source_addr <= (others => '0');
            self_addr <= (others => '0');
            size <= (others => '0');
            --fifo_wr <= '0';
        elsif (clock'event and clock = '1') then
            case state_in is
                -- wait for fifo not empty and discard the header
                when IDLE_IN =>
                    --fifo_wr <= '0';
                    -- start receiving a new packet only when the output packet is sent
                    if s_ready_s = '1' and state_handshake = WAIT_IN_PACKET then
                        state_in <= GET_SIZE;
                        self_addr <= s_data_i(15 downto 0);
                    --    fifo_wr <= '1';
                    --else
                    --    fifo_wr <= '0';
                    end if; 
                -- the fifo has one clock cycle of latency 
                --when READ_SIZE =>
                --    state_in <= GET_SIZE;
                -- the outgoing packet will have the same size of the incomming packet. So, its necessary to save it 
                when GET_SIZE =>
                    --fifo_wr <= '0';
                    if s_ready_s = '1' then
                        state_in <= GET_STORE_SOURCE;
                        size <= s_data_i(15 downto 0);
                    --    fifo_wr <= '1';
                    --else
                    --    fifo_wr <= '0';
                    end if; 
                -- it's assuming that the first payload flit will tell the source IP address
                -- so its possible to send the packet back to it
                when GET_STORE_SOURCE =>
                    --fifo_wr <= '0';
                    if s_ready_s = '1' then
                        state_in <= WAIT_LAST_FLIT;
                        source_addr <= s_data_i(15 downto 0);
                    --    fifo_wr <= '1';
                    --else
                    --    fifo_wr <= '0';
                    end if; 
                when WAIT_LAST_FLIT =>
                    if s_ready_s = '1' then
                        --fifo_wr <= '1';
                        if s_last_i = '1' then
                            state_in <= IDLE_IN;
                        else
                            state_in <= WAIT_LAST_FLIT;
                        end if;
                        --source_addr <= fifo_data_in(15 downto 0);
                    --else
                    --    fifo_wr <= '0';
                    end if; 
                -- check if the last signal is high
                --when WAIT_LAST_FLIT =>
                --    if s_ready_s = '1'then
                --        fifo_wr <= '1';
                --        if s_last_i = '1' then
                --           state_in <= IDLE_IN;
                --        end if; 
                --    else
                --        fifo_wr <= '0';
                --    end if; 
            end case;
        end if; 
    end process;    

--    fifo_data_in <= '0' & x"0000" & s_data_i(15 downto 0) when state_in = GET_STORE_SOURCE and s_ready_s = '1' else
--                    '0' & x"0000" & size                  when state_in = STORE_SIZE and s_ready_s = '1' else
--                    s_last_i & s_data_i;

    fifo_data_in <= s_last_i & s_data_i when state_in = WAIT_LAST_FLIT and s_ready_s = '1' else
                    (others => '0');

    fifo_wr <= '1' when  state_in = WAIT_LAST_FLIT and s_ready_s = '1' else '0';
    
    process(clock, reset_n)
    begin
        if (reset_n = '0') then 
            state_handshake <= WAIT_IN_PACKET;
            can_send <= '0';
        elsif (clock'event and clock = '1') then
            case state_handshake is
                -- wait for fifo not empty and discard the header
                when WAIT_IN_PACKET =>
                    if state_in = WAIT_LAST_FLIT then 
                        can_send <= '1';
                        -- now that it finished to receive the 1st 3 flits, I can start sending the packet
                        state_handshake <= WAIT_OUT_PACKET;
                    else 
                        can_send <= '0';
                    end if;
                when WAIT_OUT_PACKET =>
                    if state_out = INCREMENTING then 
                        can_send <= '0';
                        -- now that it finished to send the 1st 3 flits, It is ready to receive another packet
                        state_handshake <= WAIT_IN_PACKET;
                    else 
                        can_send <= '1';
                    end if;
            end case;
        end if; 
    end process; 

    ----------------------------------------
    -- OUTPUT PACKET PROCESSING
    ----------------------------------------
    process(clock, reset_n)
    begin
        if (reset_n = '0') then 
            state_out <= IDLE_OUT;
            fifo_rd <= '0';
        elsif (clock'event and clock = '1') then
            case state_out is
                -- wait for fifo not empty and discard the header
                when IDLE_OUT =>
                    fifo_rd <= '0';
                    -- start to send after the 3 first flits were received
                    if  m_ready_i = '1' and state_handshake = WAIT_OUT_PACKET then
                        state_out <= SEND_HEADER;
                    --    fifo_rd <= '1';
                    --else
                    --    fifo_rd <= '0';
                    end if; 
                -- send the header of the outgoing packet if there is no network contention
                when SEND_HEADER =>
                    fifo_rd <= '0';
                    if m_ready_i = '1' then
                        state_out <= SEND_SIZE;
                    --    fifo_rd <= '1';
                    --else
                    --   fifo_rd <= '0';
                    end if; 
                -- send the size of the outgoing packet if there is no network contention
                when SEND_SIZE =>
                    fifo_rd <= '0';
                    if m_ready_i = '1' then
                        state_out <= SEND_SOURCE;
                    --    fifo_rd <= '1';
                    --else
                    --    fifo_rd <= '0';
                    end if; 
                -- send the header of the outgoing packet. just to avoid changing the packet size
                when SEND_SOURCE =>
                    fifo_rd <= '0';
                    if m_ready_i = '1' then
                        state_out <= INCREMENTING;
                    end if; 
                -- increment the rest of the payload
                when INCREMENTING =>
                    if fifo_empty = '0' and  m_ready_i = '1' then
                        fifo_rd <= '1';
                        if  fifo_data_out(32) = '1' then
                            --fifo_rd <= '0';
                            state_out <= IDLE_OUT;
                        else
                            state_out <= INCREMENTING;
                        end if;
                    else
                        fifo_rd <= '0';
                        state_out <= INCREMENTING;
                    end if;
            end case;
        end if; 
	end process;


    -- send the last position of the FIFOs
    m_valid_o <= '1' when state_handshake = WAIT_OUT_PACKET and m_ready_i = '1' else '0';
    -- it only read from the fifo when the noc can receive a new flit
    --m_valid_o <= fifo_rd;
    m_last_o <= '1' when state_out =  INCREMENTING and fifo_data_out(32) = '1' and m_ready_i = '1' else '0';
    m_data_o <= x"0000" & source_addr when state_out = SEND_HEADER  else
                x"0000" & size        when state_out = SEND_SIZE    else
                x"0000" & self_addr   when state_out = SEND_SOURCE  else
                fifo_data_out(31 downto 0) + INC_VALUE when state_out = INCREMENTING else
                (others => '0');

end Behavioral;
