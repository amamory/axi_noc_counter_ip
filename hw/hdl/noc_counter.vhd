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
	m_ready_i : in  std_logic;
	m_last_o  : out std_logic;
	m_data_o  : out std_logic_vector(31 downto 0)
);
end noc_counter;

architecture Behavioral of noc_counter is

-- incomming packet fsm
type State_type IS (WAIT_IN_HEADER, GET_SIZE, GET_SOURCE, SEND_HEADER, SEND_SIZE, SEND_SOURCE, INCREMENTING_PAYLOAD); 
signal state, next_state : State_Type;    

-- get the source of the incomming packet , which will be the target of the outgoing packet
signal source_addr : std_logic_vector(15 downto 0);
-- get the header of the incomming packet , which will be the source of the outgoing packet
signal self_addr   : std_logic_vector(15 downto 0);
signal size : std_logic_vector(15 downto 0);

attribute KEEP : string;
--attribute MARK_DEBUG : string;
--
attribute KEEP of state       : signal is "TRUE";
attribute KEEP of source_addr : signal is "TRUE";
attribute KEEP of self_addr   : signal is "TRUE";
attribute KEEP of size        : signal is "TRUE";
---- in verilog: (* keep = "true" *) wire signal_name;
--attribute MARK_DEBUG of state : signal is "TRUE";
--

begin

    process(clock)
    begin
        if (clock'event and clock = '1') then
            state <= next_state;
        end if;
    end process;

    -- accepts incomming flit if there is something new and if the FSM is in a receiving state
    s_ready_o <= '1' when (state = WAIT_IN_HEADER or state = GET_SIZE  or state = GET_SOURCE) else
                -- accepts the incomming flit if there is a new flit and the output port can send data 
                 '1' when m_ready_i = '1' and state = INCREMENTING_PAYLOAD  else '0';
    
    -- get the packet size and the target address for the response packet
    process(state, s_valid_i, m_ready_i, s_last_i )
    begin
        case state is
            -- get the source of the incomming packet , which will be the target of the outgoing packet
            when WAIT_IN_HEADER =>
                if s_valid_i = '1' then
                    next_state <= GET_SIZE;
                else
                    next_state <= WAIT_IN_HEADER;
                end if; 
            -- the outgoing packet will have the same size of the incomming packet. So, its necessary to save it 
            when GET_SIZE =>
                if s_valid_i = '1' then
                    next_state <= GET_SOURCE;
                else
                    next_state <= GET_SIZE;
                end if; 
            -- it's assuming that the first payload flit will tell the source noc address
            -- so its possible to send the packet back to it
            when GET_SOURCE =>
                if s_valid_i = '1' then
                    next_state <= SEND_HEADER;
                else
                    next_state <= GET_SOURCE;
                end if; 
            -- send the header of the outgoing packet if there is no network contention
            when SEND_HEADER =>
                if m_ready_i = '1' then
                    next_state <= SEND_SIZE;
                else
                    next_state <= SEND_HEADER;
                end if; 
            -- send the size of the outgoing packet if there is no network contention
            when SEND_SIZE =>
                if m_ready_i = '1' then
                    next_state <= SEND_SOURCE;
                else
                    next_state <= SEND_SIZE;
                end if; 
            -- send the header of the outgoing packet. just to avoid changing the packet size
            when SEND_SOURCE =>
                if m_ready_i = '1' then
                    next_state <= INCREMENTING_PAYLOAD;
                else
                    next_state <= SEND_SOURCE;
                end if; 
            -- increment the rest of the payload
            when INCREMENTING_PAYLOAD =>
                if s_valid_i = '1' and  m_ready_i = '1' then
                    if  s_last_i = '1' then
                        next_state <= WAIT_IN_HEADER;
                    else
                        next_state <= INCREMENTING_PAYLOAD;
                    end if;
                else
                    next_state <= INCREMENTING_PAYLOAD;
                end if; 
            when others => 
                next_state <= WAIT_IN_HEADER;
        end case;
    end process;    

    process(clock)
    begin
        if (clock'event and clock = '1') then
            if (reset_n = '0') then 
                source_addr <= (others => '0');
                self_addr <= (others => '0');
                size <= (others => '0');
            else
                if s_valid_i = '1' then
                    if state = WAIT_IN_HEADER then 
                        self_addr <= s_data_i(15 downto 0);
                    end if;
                    if state = GET_SIZE then 
                        size <= s_data_i(15 downto 0);
                    end if;
                    if state = GET_SOURCE then 
                        source_addr <= s_data_i(15 downto 0);
                    end if;
                end if;
             end if;
        end if; 
    end process;    

    m_valid_o <= '1' when s_valid_i = '1' and  m_ready_i = '1' and (state = SEND_HEADER or state = SEND_SIZE or state = SEND_SOURCE or state = INCREMENTING_PAYLOAD) else '0';
    m_last_o <= '1' when state = INCREMENTING_PAYLOAD and s_last_i = '1' and m_ready_i = '1' else '0';
    m_data_o <= x"0000" & source_addr when state = SEND_HEADER  else
                x"0000" & size        when state = SEND_SIZE    else
                x"0000" & self_addr   when state = SEND_SOURCE  else
                s_data_i + INC_VALUE  when state = INCREMENTING_PAYLOAD else
                (others => '0');                                

end Behavioral;
