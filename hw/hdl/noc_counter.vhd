----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 06/07/2020 05:41:32 PM
-- Design Name: 
-- Module Name: NoN counter
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- it receives a hermes packet, increments its payload, and sends the packet back to the source IP
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

type State_type IS (IDLE, GET_SIZE, GET_SOURCE, SEND_HEADER, SEND_SIZE, INCREMENTING); 
signal state : State_Type;    

signal m_data_s : std_logic_vector(31 downto 0);    
signal source_addr : std_logic_vector(15 downto 0);
signal size : std_logic_vector(15 downto 0);
signal m_valid_s, m_last_s : std_logic_vector(3 downto 0);


--attribute KEEP : string;
--attribute MARK_DEBUG : string;
--
--attribute KEEP of state : signal is "TRUE";
---- in verilog: (* keep = "true" *) wire signal_name;
--attribute MARK_DEBUG of state : signal is "TRUE";
--

begin

    -- the master signals are delayed 3 clock cycles
    process(clock, reset_n)
    begin
        if (reset_n = '0') then 
            m_valid_s <= (others => '0');
            m_last_s <= (others => '0');
        elsif (clock'event and clock = '0') then
            m_valid_s <= m_valid_s(2 downto 0) & s_valid_i;
            m_last_s <= m_last_s(2 downto 0) & s_last_i;
        end if;
    end process;
    

    process(clock, reset_n)
    begin
        if (reset_n = '0') then 
            state <= IDLE;
            m_data_s <= (others => '0');
            source_addr <= (others => '0');
            size <= (others => '0');
        elsif (clock'event and clock = '0') then
            case state is
                -- wait for the header flit
                when IDLE =>
                    if s_valid_i = '1' then
                        state <= GET_SIZE;
                    end if; 
                -- the packet size is not used because we have the last signal to say when the packer is finished
                when GET_SIZE =>
                    state <= GET_SOURCE;
                    size <= s_data_i(15 downto 0);
                -- it's assuming that the first payload flit will tell the source IP address
                -- so its possible to send the packet back to it
                when GET_SOURCE =>
                    source_addr <= s_data_i(15 downto 0);
                    state <= SEND_HEADER;
                -- send the header of the response packet
                when SEND_HEADER =>
                    m_data_s <= x"0000" & source_addr;
                    state <= SEND_SIZE;
                -- send the size of the response packet
                when SEND_SIZE =>
                    m_data_s <= (x"0000" & size) -1;
                    state <= INCREMENTING;
                -- increment the rest of the payload
                when INCREMENTING =>
                    m_data_s <= s_data_i + INC_VALUE;
                    if s_last_i = '1' then
                        state <= IDLE;
                    else
                        state <= INCREMENTING;
                    end if;
            end case;
        end if; 
	end process;

    m_valid_o <= m_valid_s(3);
    m_last_o <= m_last_s(3);
    m_data_o <= m_data_s;
    --always ready to receive since there is no back pressure mechanism
    s_ready_o <= '1';

end Behavioral;
