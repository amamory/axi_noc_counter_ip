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
	m_ready_i : in  std_logic; -- TODO, this port is not used and it will cause error when Noc has congestion
	m_last_o  : out std_logic;
	m_data_o  : out std_logic_vector(31 downto 0)
);
end noc_counter;

architecture Behavioral of noc_counter is

constant FIFO_SIZE : integer := 3; 

type State_type IS (IDLE, GET_SIZE, GET_SOURCE, SEND_HEADER, SEND_SIZE, SEND_SOURCE, INCREMENTING); 
signal state : State_Type;    

signal source_addr : std_logic_vector(15 downto 0);
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

    -- write data from the master port into the fifo
    process(clock, reset_n)
    begin
        if (reset_n = '0') then 
            fifo_data_in <= (others => '0');
            fifo_wr <= '0';
        elsif (clock'event and clock = '1') then
            if s_ready_s = '1' then 
                fifo_data_in <= s_last_i & s_data_i;
                fifo_wr <= '1';
            else
                fifo_data_in <= (others => '0');
                fifo_wr <= '0';
            end if;
        end if;
    end process;
    
    -- accepts incomming data as long as the master wants to write and the fifo is not full
    s_ready_s <= s_valid_i and not fifo_full;
    s_ready_o <= s_ready_s;
    
    
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
 
    

    process(clock, reset_n)
    begin
        if (reset_n = '0') then 
            state <= IDLE;
            source_addr <= (others => '0');
            size <= (others => '0');
            fifo_rd <= '0';
        elsif (clock'event and clock = '1') then
            case state is
                -- wait for fifo not empty and discard the header
                when IDLE =>
                    fifo_rd <= '0';
                    if fifo_empty = '0' then
                        state <= GET_SIZE;
                    end if; 
                -- the outgoing packet will have the same size of the incomming packet. So, its necessary to save it 
                when GET_SIZE =>
                    if fifo_empty = '0' then
                        state <= GET_SOURCE;
                        size <= fifo_data_out(15 downto 0);
                        fifo_rd <= '1';
                    else
                        state <= GET_SIZE;
                        fifo_rd <= '0';
                    end if; 
                -- it's assuming that the first payload flit will tell the source IP address
                -- so its possible to send the packet back to it
                when GET_SOURCE =>
                    if fifo_empty = '0' then
                        source_addr <= fifo_data_out(15 downto 0);
                        fifo_rd <= '1';
                        state <= SEND_HEADER;
                    else
                        state <= GET_SOURCE;
                        fifo_rd <= '0';
                    end if; 
                -- send the header of the outgoing packet if there is no network contention
                when SEND_HEADER =>
                    fifo_rd <= '0';
                    if m_ready_i = '1' then
                        state <= SEND_SIZE;
                    end if; 
                -- send the size of the outgoing packet if there is no network contention
                when SEND_SIZE =>
                    fifo_rd <= '0';
                    if m_ready_i = '1' then
                        state <= SEND_SOURCE;
                    end if; 
                -- send the header of the outgoing packet. just to avoid changing the packet size
                when SEND_SOURCE =>
                    fifo_rd <= '0';
                    if m_ready_i = '1' then
                        state <= INCREMENTING;
                    end if; 
                -- increment the rest of the payload
                when INCREMENTING =>
                    if  m_ready_i = '1' then
                        fifo_rd <= '1';
                        if  fifo_data_out(32) = '1' and m_ready_i = '1' then
                            state <= IDLE;
                        else
                            state <= INCREMENTING;
                        end if;
                    else
                        fifo_rd <= '0';
                        state <= INCREMENTING;
                    end if;
            end case;
        end if; 
	end process;

    -- send the last position of the FIFOs
    m_valid_o <= '0' when (state = IDLE or state = GET_SIZE  or state = GET_SOURCE) or m_ready_i = '0' else '1';
    m_last_o <= '1' when state =  INCREMENTING and fifo_data_out(32) = '1' and m_ready_i = '1' else '0';
    m_data_o <= x"0000" & source_addr when (state = SEND_HEADER or state = SEND_SOURCE) and m_ready_i = '1' else
                x"0000" & size        when state = SEND_SIZE and m_ready_i = '1' else
                fifo_data_out(31 downto 0) + INC_VALUE when state = INCREMENTING and m_ready_i = '1' else
                (others => '0');

end Behavioral;
