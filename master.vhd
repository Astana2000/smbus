LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_unsigned.all;

entity SMBus_master IS
  generic(
    input_clk : integer ;--:= 50_000_000; --input clock speed from user logic in Hz
    bus_clk   : integer );--:= 400_000);   --speed the SMbus (scl) will run at in Hz
  port(
    clk       : in     std_logic;                   
    reset_n   : in     std_logic;                   
    ena       : in     std_logic;  
    pec       : in     std_logic;
    addr      : in     std_logic_vector(6 downto 0); 
    rw        : in     std_logic;                    
    data_wr   : in     std_logic_vector(7 downto 0); 
    busy      : out    std_logic;                   
    data_rd   : out    std_logic_vector(7 downto 0); 
    ack_error : inout std_logic;                    
    sda       : inout  std_logic;                    --serial data output 
    scl       : inout  std_logic);                   --serial clock output 
end SMBus_master;

architecture behavior OF SMBus_master IS
  constant divider  :  integer := (input_clk/bus_clk)/4; --number of clocks in 1/4 cycle of scl
  type machine IS(ready, start, command, slv_ack1, wr,wr_pec, rd,rd_pec, slv_ack2, mstr_ack, mstr_ack2,stop); 
  signal state         : machine;                        
  signal data_clk      : std_logic;                      --data clock for sda
  signal data_clk_prev : std_logic;                      --data clock previous 
  signal scl_clk       : std_logic;                      --running internal scl
  signal scl_ena       : std_logic := '0';               --enables internal scl to output
  signal sda_int       : std_logic := '1';               --internal sda
  signal sda_ena_n     : std_logic;                     --enables internal sda to output
  signal addr_rw       : std_logic_vector(7 downto 0);   
  signal data_tx       : std_logic_vector(7 downto 0);   -- data to write 
  signal calc_pec      : std_logic_vector(7 downto 0)  := "00000000";
  signal data_rx       : std_logic_vector(7 downto 0);   --data received 
  signal bit_cnt       : integer range 0 to 7 := 7;                 
  
  function nextCRC8_D8
    (Data: std_logic_vector(7 downto 0);
     crc:  std_logic_vector(7 downto 0))
    return std_logic_vector is

    variable d:      std_logic_vector(7 downto 0);
    variable c:      std_logic_vector(7 downto 0);
    variable newcrc: std_logic_vector(7 downto 0);

  begin
    d := Data;
    c := crc;

    newcrc(0) := d(7) xor d(6) xor d(0) xor c(0) xor c(6) xor c(7);
    newcrc(1) := d(6) xor d(1) xor d(0) xor c(0) xor c(1) xor c(6);
    newcrc(2) := d(6) xor d(2) xor d(1) xor d(0) xor c(0) xor c(1) xor c(2) xor c(6);
    newcrc(3) := d(7) xor d(3) xor d(2) xor d(1) xor c(1) xor c(2) xor c(3) xor c(7);
    newcrc(4) := d(4) xor d(3) xor d(2) xor c(2) xor c(3) xor c(4);
    newcrc(5) := d(5) xor d(4) xor d(3) xor c(3) xor c(4) xor c(5);
    newcrc(6) := d(6) xor d(5) xor d(4) xor c(4) xor c(5) xor c(6);
    newcrc(7) := d(7) xor d(6) xor d(5) xor c(5) xor c(6) xor c(7);
    return newcrc;
  end nextCRC8_D8;
begin

   --generate the timing for the bus clock (scl_clk) and the data clock (data_clk)
  process(clk, reset_n)
    constant div: integer := 31;
    variable count  :  integer range 0 to divider*4;  --timing for clock generation
  begin
    if(reset_n = '0') then                --reset asserted
      count := 0;
    elsif(clk'EVENT and clk = '1') then
      data_clk_prev <= data_clk;          --store previous value of data clock
      if(count = divider*4-1) then        --end of timing cycle
        count := 0;                       --reset timer
      else          
        count := count + 1;               --continue clock generation timing
      end if;
      if count < divider-1 then
	scl_clk <= '0';
        data_clk <= '0';
      elsif count < divider*2-1 then
        scl_clk <= '0';
        data_clk <= '1';
      elsif count < divider*3-1 then
	  scl_clk <= '1';                 --release scl
          data_clk <= '1';
      else
	scl_clk <= '1';
        data_clk <= '0';
      end if;
    end if;
  end process;

  
   --state machine and writing to sda during scl low (data_clk rising edge)
  smbus_proc: process(clk, reset_n)
  begin
    if(reset_n = '0') then                 
      state <= ready;   
    elsif (rising_edge(clk)) then
      if(data_clk = '1' and data_clk_prev = '0') then
	case state is	
	  when ready =>
	  	if (ena = '1' ) then  		
		  state <=  start; 
	  	else                                             
              	  state <= ready;                
          	end if;     
          when start =>
          	  state <= command;
          when command =>                    --address and command byte of transaction
            	if(bit_cnt = 0) then           
              	  state <= slv_ack1;             
            	else                             
              	  state <= command;              
            	end if;
          when slv_ack1 =>         
            	if(addr_rw(0) = '0') then         
              	  state <= wr;                   
            	else                           
              	  state <= rd;                   
            	end if;
          
          when wr =>                                           
            	if(bit_cnt = 0) then            
              	  state <= slv_ack2;             
            	else                             --next clock cycle of write state
              	  state <= wr;                   
            	end if;
          when rd =>                                  
            	if(bit_cnt = 0) then            
              	  state <= mstr_ack;             
            	else                                    
              	  state <= rd;                   
            	end if;
          when slv_ack2 =>                   --slave acknowledge(write)
            	if(ena = '1') then  
            	  if (pec = '1') then 
            	     state <= wr_pec;            
              	  elsif(addr_rw = addr & rw) then   
                     state <= wr;                 
              	  else                          
                     state <= start;              
              	  end if;
            	else                             
              	  state <= stop;                 
            	end if;
         when wr_pec =>
                if(bit_cnt = 0) then            
              	  state <= slv_ack2;           
            	else                             
              	  state <= wr_pec;                   
            	end if; 
         when mstr_ack =>                  
            if(ena = '1') then 
              if (pec = '1') then 
                state<=rd_pec;            
              elsif(addr_rw = addr & rw) then   
                state <= rd;                
              end if;    
            else                             
              state <= stop;                 
            end if;
         when rd_pec =>
           if(bit_cnt = 0) then            
              state <= mstr_ack2;             
           else                                    
              state <= rd_pec;                   
           end if;
         when mstr_ack2 =>
            if(ena = '1') then 
               state <= start;                 
            else                             
              state <= stop;                 
            end if;
         when stop =>                                  
           state <= ready;    
        end case; 
      end if;
    end if;
    end process;
    
    smbus_main : process(reset_n,clk)
    begin
    if (reset_n = '0') then 
      busy <= '1';                         
      scl_ena <= '0';                      
      sda_int <= '1';                      
      ack_error <= '0';                    
      bit_cnt <= 7;                        
      data_rd <= "00000000";   
      calc_pec <= "00000000";
    elsif(rising_edge(clk)) then
      case state IS
          when ready =>
            if(data_clk = '1' and data_clk_prev = '0') then  
              if(ena = '1') then               
                busy <= '1';                   
                addr_rw <= addr & rw;          
                data_tx <= data_wr;            -- data to write             
              else                             
                busy <= '0';                                
              end if;
    	    end if;
    	  when start =>
    	      bit_cnt <= 7;  
    	    if(data_clk = '1' and data_clk_prev = '0') then 
    	      busy <= '1';                     
              sda_int <= addr_rw(bit_cnt); 
              calc_pec <="00000000";
            elsif(data_clk = '0' and data_clk_prev = '1') then                 
              if(scl_ena = '0') then                  -- new transaction
                scl_ena <= '1';                       --enable scl output
                ack_error <= '0';                     --reset error 
              end if;
            end if;
          when command =>                    --address and command 
            if(data_clk = '1' and data_clk_prev = '0') then 
              if(bit_cnt = 0) then             
                sda_int <= 'H';                --release sda for slave acknowledge
                bit_cnt <= 7;                     
              else                             
                bit_cnt <= bit_cnt - 1;        
                sda_int <= addr_rw(bit_cnt-1); --write address/command bit               
              end if;
            end if;
          when slv_ack1 =>  
            if(data_clk = '1' and data_clk_prev = '0') then  
              calc_pec<=nextCRC8_D8(addr_rw,calc_pec);              
              if(addr_rw(0) = '0') then         
                sda_int <= data_tx(bit_cnt);               
              else                             
                sda_int <= '1';                                  
              end if;
            elsif(data_clk = '0' and data_clk_prev = '1') then
              if(sda /= '0' OR ack_error = '1') then  
                ack_error <= '1';                     
              end if;
            end if;
          when wr =>
            if(data_clk = '1' and data_clk_prev = '0') then 
              busy <= '1';                     
              if(bit_cnt = 0) then             
                sda_int <= '1';                
                bit_cnt <= 7;  
                calc_pec<=nextCRC8_D8(data_tx,calc_pec);                     
              else                             
                bit_cnt <= bit_cnt - 1;        
                sda_int <= data_tx(bit_cnt-1);                  
              end if;
            end if;
          when rd => 
            if(data_clk = '1' and data_clk_prev = '0') then 
              busy <= '1';                     
              if(bit_cnt = 0) then 
                calc_pec<=nextCRC8_D8(data_rx,calc_pec);              
                if(ena = '1' and addr_rw = addr & rw) then  --read with same address
                  sda_int <= '0';              
                else                          
                  sda_int <= '1';              
                end if; 
                bit_cnt <= 7;                 
                data_rd <= data_rx;            --received data
              else                          
                bit_cnt <= bit_cnt - 1;    
                data_rd <= data_rx;                     
              end if;
              
            elsif(data_clk = '0' and data_clk_prev = '1') then
              data_rx(bit_cnt) <= sda; 
            end if;
          when slv_ack2 =>  
            data_tx <= data_wr; 
                          
            if(data_clk = '1' and data_clk_prev = '0') then 
              if(ena = '1') then               
                busy <= '0';                   
                addr_rw <= addr & rw;          
                data_tx <= data_wr;            
                if(addr_rw = addr & rw) then   
                  sda_int <= data_wr(bit_cnt); 
                end if;           
              end if;
            elsif(data_clk = '0' and data_clk_prev = '1') then
              if(sda /= '0' OR ack_error = '1') then  
                ack_error <= '1';                    
              end if;
            end if;
          when wr_pec =>
             if(data_clk = '1' and data_clk_prev = '0') then 
              busy <= '1';                     
              if(bit_cnt = 0) then             
                sda_int <= '1';                
                bit_cnt <= 7;                        
              else                             
                bit_cnt <= bit_cnt - 1;        
                sda_int <= calc_pec(bit_cnt-1);                  
              end if;
            end if;
          when mstr_ack =>      
            if(data_clk = '1' and data_clk_prev = '0') then 
              if(ena = '1') then                               
                addr_rw <= addr & rw;            
                if(addr_rw = addr & rw ) then   
                  sda_int <= '1';             
                end if;                    
              end if;
            end if;
          when rd_pec =>
            if(data_clk = '1' and data_clk_prev = '0') then 
              busy <= '1';     
              data_rd <= data_rx;                  
              if(bit_cnt = 0) then  
                calc_pec<=nextCRC8_D8(data_rx,calc_pec);           
                if(ena = '1' and addr_rw = addr & rw) then  --read with same address
                  sda_int <= '0';              
                else                          
                  sda_int <= '1';              
                end if; 
                bit_cnt <= 7;                 
                data_rd <= data_rx;            --received data
              else                          
                bit_cnt <= bit_cnt - 1;              
              end if;
            elsif(data_clk = '0' and data_clk_prev = '1') then
              data_rx(bit_cnt) <= sda; 
            end if;
          when mstr_ack2 =>
           if(data_clk = '1' and data_clk_prev = '0') then 
              if(ena = '1') then              
                busy <= '0';    
                if  calc_pec = "00000000"  then
                 ack_error <= '0' ;
                  else 
                 ack_error <= '1';   
                 end if;            
                addr_rw <= addr & rw;         
                data_tx <= data_wr;   
                if(addr_rw = addr & rw ) then   
                  sda_int <= '1';              --release sda from incoming date
                end if;                    
              end if;
            end if;
        
             
          when stop=>
            if(data_clk = '1' and data_clk_prev = '0') then 
              busy <= '0'; 
            elsif(data_clk = '0' and data_clk_prev = '1') then
               scl_ena <= '0';
            end if;
          end case;
       end if;
       --scl <= scl1;
       --sda <= sda1;
     end process;
     
    --set scl and sda 
    
  
     --set sda_ena
    with state select
      sda_ena_n <= data_clk_prev when start,--data_clk_prev when start,     
                   not data_clk_prev when stop,  
                   'U' when rd,
                   sda_int when others;          -- internal sda signal    
 
     --set scl and sda 
   scl <= '0' WHEN (scl_ena = '1' AND scl_clk = '0') ELSE 'Z';
   sda <= '0' WHEN sda_ena_n = '0' ELSE 'Z';
     
end behavior;
  










