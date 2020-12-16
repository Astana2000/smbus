LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_unsigned.all;

entity tester_SMBus_master IS
  PORT(
    clk       : out     std_logic;                   
    reset_n   : out     std_logic;                   
    ena       : out     std_logic;                   
    pec       : out     std_logic;
    addr      : out     std_logic_vector(6 downto 0); 
    rw        : out     std_logic;                    
    data_wr   : out     std_logic_vector(7 downto 0); 
    busy      : in    std_logic;                   
    data_rd   : in    std_logic_vector(7 downto 0); 
    --ack_error : BUFFER std_logic;                    
    sda       : inout  std_logic;                    --serial data output of SMbus
    scl       : inout  std_logic);                   --serial clock output of SMbus
END tester_SMBus_master;

architecture Tester_behavioral of tester_SMBus_master is

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
    	addr<="1100101";
    	rw<='0';
    	data_wr<="11111110";
    	sda<='H';
    	scl<='H';
    	wait for 15 us;
    	data_wr<="00000001";
    	wait for 10 us;
    	pec<='1';
    	wait for 15 us;
    	ena<='0';
    	pec<='0';
    	wait for 2 us;
    	ena<='1';
    	addr<="1010101";
    	rw<='1';
    	
    	wait for 12 us;
    	sda<='0';
    	wait for 5 us;
    	sda<='1';
    	wait for 3.5 us;
    	pec<='1';
    	wait for 2 us;
    	ena<='0';
    	
    	sda<='H';
    	wait for 15 ns;
    	

    end process stim_proc;


end Tester_behavioral;










