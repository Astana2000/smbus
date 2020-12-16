LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_unsigned.all;

entity tester_SMBus IS
  PORT(
    clk       : out     std_logic;                   
    reset_n   : out     std_logic;                   
    ena       : out     std_logic;                   
    pec       : out     std_logic;
    addr      : out     std_logic_vector(6 downto 0); 
    rw        : out     std_logic;                    
    data_wr   : out     std_logic_vector(7 downto 0); 
    data_to_master   : out    std_logic_vector(7 downto 0);
    busy      : in    std_logic;                   
    data_rd   : in    std_logic_vector(7 downto 0); 
    ack_error : inout std_logic;                    
    sda       : inout  std_logic;                    --serial data output of SMbus
    scl       : inout  std_logic);                   --serial clock output of SMbus
END tester_SMBus;

architecture Tester_behavioral of tester_SMBus is

constant period : time := 5 ns;
begin

clock_process : process
    begin
        clk <= '0';
        wait for period;
        clk <= '1';
        wait for period;
end process clock_process;

stim_proc : process
    begin
    	reset_n<='0';
    	ena<='0';
    	wait for 20 ns;
    	reset_n<='1';
    	ena<='1';
    	pec<='0';
    	ack_error<='H';
    	addr<="1100101";
    	rw<='0';
    	data_wr<="11111110";
    	data_to_master<="00000000";
    	sda<='H';
    	scl<='H';
    	wait for 17 us;
    	pec<='1';
    	wait for 13 us;
    	pec<='0';
    	wait for 2 us;
    	ena<='0';
    	--
    	wait for 5 us;
    	reset_n<='1';
    	ena<='1';
    	addr<="1010101";
    	rw<='1';
    	data_to_master<="10010011";
    	wait for 15 us;
    	pec<='1';
    	wait for 13 us;
    	pec<='0';
    	
    	wait for 10 us;
    	ena<='0';
 
    	
				

    end process stim_proc;


end Tester_behavioral;










