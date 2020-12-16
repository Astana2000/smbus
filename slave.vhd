library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity smbus_slave is
  generic (
    SLAVE_ADDR : std_logic_vector(6 downto 0) );
  port (
   
    clk              : in    std_logic;
    reset_n          : in    std_logic;
    pec              : in   std_logic;
    read_req         : out   std_logic;
    data_to_master   : in    std_logic_vector(7 downto 0);
    data_valid       : out   std_logic;
    --data_from_master : out   std_logic_vector(7 downto 0);
    scl              : inout std_logic;
    sda              : inout std_logic);
    
end entity smbus_slave;
------------------------------------------------------------
architecture arch of smbus_slave is
  type state_t is (ready, command,slv_ack1, wr,wr_pec,rd, rd_pec,smbus_answer_ack_start,smbus_read_ack_start,
                   smbus_read_ack_got_rising, stop);
  --  state management
  signal state_reg          : state_t              ;
  signal cmd_reg            : std_logic            := '0';
  signal bits_processed_reg : integer range 0 to 8 := 0;
  signal continue_reg       : std_logic            := '0';
  signal start_reg       : std_logic := '0';
  signal stop_reg        : std_logic := '0';
  signal scl_rising_reg  : std_logic := '0';
  signal scl_falling_reg : std_logic := '0';
  signal calc_pec      : std_logic_vector(7 downto 0)  := "00000000";

  signal addr_reg : std_logic_vector(6 downto 0) := (others => '0');
  signal data_reg : std_logic_vector(7 downto 0) := (others => '0');
  signal pec_reg : std_logic_vector(7 downto 0) := (others => '0');

  -- Delayed SCL (by 1 clock cycle, and by 2 clock cycles)
  signal scl_reg      : std_logic := '1';
  signal scl_prev_reg : std_logic := '1';
  -- Slave writes on scl
  signal scl_wen_reg  : std_logic := '0';
  signal scl_o_reg    : std_logic := '0';
  -- Delayed SDA (1 clock cycle, and 2 clock cycles)
  signal sda_reg      : std_logic := '1';
  signal sda_prev_reg : std_logic := '1';
  -- Slave writes on sda
  signal sda_wen_reg  : std_logic := '0';
  signal sda_o_reg    : std_logic := '0';

  
  signal data_valid_reg     : std_logic                    := 'W';
  signal read_req_reg       : std_logic                    := '0';
  signal data_to_master_reg : std_logic_vector(7 downto 0) ;
  
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


  process (clk) is
  begin
    if rising_edge(clk) then
      -- Delay SCL by 1 and 2 clock cycles
      if scl ='H' then
         scl_reg <= '1';
      else 
         scl_reg <= '0';
      end if;
      scl_prev_reg   <= scl_reg;
      -- Delay SDA by 1 and 2 clock cycles
      if sda ='H' then
         sda_reg <= '1';
      else 
         sda_reg <= '0';
      end if;
      sda_prev_reg   <= sda_reg;
      -- Detect rising and falling SCL
      scl_rising_reg <= '0';
      if scl_prev_reg = '0' and (scl_reg ='1') then
        scl_rising_reg <= '1';
      end if;
      scl_falling_reg <= '0';
      if ( scl_prev_reg='1') and scl_reg = '0' then
        scl_falling_reg <= '1';
      end if;

      --  START condition
      start_reg <= '0';
      stop_reg  <= '0';
      if scl_reg = '1' and scl_prev_reg = '1' and
        sda_prev_reg = '1' and sda_reg = '0' then
        start_reg <= '1';
        stop_reg  <= '0';
      end if;

      --  STOP condition
      if scl_prev_reg = '1' and scl_reg = '1' and
        sda_prev_reg = '0' and sda_reg = '1' then
        start_reg <= '0';
        stop_reg  <= '1';
      end if;

    end if;
  end process;

  state_process: process(clk) is
  begin
  if rising_edge(clk) then
  case state_reg is
        when ready =>
          if start_reg = '1' then
            state_reg   <= command;
          end if;
        when command =>
         if bits_processed_reg = 8 and scl_falling_reg = '1' then
            if addr_reg = SLAVE_ADDR then 
              state_reg <= slv_ack1;
            else
              state_reg <= ready;
            end if;
          end if;
        when slv_ack1 =>
          if scl_falling_reg = '1' then
            if cmd_reg = '0' then
              state_reg <= wr;
            else
              state_reg <= rd;
            end if;
          end if;
       when wr =>
        if scl_falling_reg = '1' and bits_processed_reg = 8 then
            state_reg          <= smbus_answer_ack_start; 
        end if;
       when smbus_answer_ack_start => 
       if data_valid_reg = '1' then
         if scl_falling_reg = '1' then
            if continue_reg = '0' then
              state_reg <=stop;
            end if;
          end if;
       else
        if scl_falling_reg = '1' then
         if pec = '1' then
            state_reg  <= wr_pec;
         else
            state_reg <=wr;
         end if;
        end if;
       end if;
       when wr_pec =>
        if scl_falling_reg = '1' and bits_processed_reg = 8 then
            state_reg          <= smbus_answer_ack_start; -- что здесь происходит?
        end if;
       when rd =>
         if scl_falling_reg = '1' and bits_processed_reg = 7 then
           state_reg          <= smbus_read_ack_start;
         end if;
       when rd_pec =>
         if scl_falling_reg = '1' and bits_processed_reg = 7 then
           state_reg          <= smbus_read_ack_start;
         end if;
       when smbus_read_ack_start =>
         if scl_rising_reg = '1' then
            state_reg <= smbus_read_ack_got_rising;
         end if;
       when smbus_read_ack_got_rising =>
          if scl_rising_reg = '1' then
           if pec ='1' then
             state_reg<=rd_pec;
            elsif continue_reg = '1' then
              if cmd_reg = '1' then
                state_reg <= rd;
              end if;
            else
              state_reg <=ready;
            end if;
          end if;
         when others =>
           if start_reg = '1' then
             state_reg          <= command;
           end if;

          if stop_reg = '1' then
             state_reg          <= ready;
          end if;
         end case;
    end if;
  end process;
         
         
         
         
  smbus_main:process(clk) is 
  begin
  if rising_edge(clk) then
      -- Default assignments
      sda_o_reg      <= '0';
      sda_wen_reg    <= '0';
      -- User interface
      data_valid_reg<='L';
      read_req_reg   <= '0';
  case state_reg is
   when ready =>
          if start_reg = '1' then
            bits_processed_reg <= 0;
            calc_pec <="00000000";
          end if;
   when command =>
      if scl_rising_reg = '1' then
            if bits_processed_reg < 7 then
              bits_processed_reg             <= bits_processed_reg + 1;
              addr_reg(6-bits_processed_reg) <= sda_reg;
            elsif bits_processed_reg = 7 then
              bits_processed_reg <= bits_processed_reg + 1;
              cmd_reg <= sda_reg;
            end if;
       end if;
       if bits_processed_reg = 8 and scl_falling_reg = '1' then
            bits_processed_reg <= 0;
            if addr_reg = SLAVE_ADDR then  -- check req address
              if cmd_reg = '1' then  -- issue read request 
                read_req_reg       <= '1';
                data_to_master_reg <= data_to_master;
              end if;
            end if;
        end if;
    when slv_ack1 =>
          sda_wen_reg <= '1';
          sda_o_reg   <= '0';
          if scl_rising_reg = '1' then
          calc_pec<=nextCRC8_D8(addr_reg & cmd_reg ,calc_pec);   
          end if;
    when wr =>
          if scl_rising_reg = '1' then
            if bits_processed_reg <= 7 then
              data_reg(7-bits_processed_reg) <= sda_reg;
              bits_processed_reg             <= bits_processed_reg + 1;
            end if;
          end if;
          if scl_falling_reg = '1' and bits_processed_reg = 8 then
            bits_processed_reg <= 0;
          end if;
    when smbus_answer_ack_start =>    
          if calc_pec="00000000" then
            data_valid_reg <= '1';
          end if; 
         sda_wen_reg <= '1';
         sda_o_reg   <= '0';
         if scl_rising_reg = '1' and  data_valid_reg /= '1' then
          calc_pec<=nextCRC8_D8(data_reg,calc_pec);   
         end if; 
    when wr_pec =>
         if scl_rising_reg = '1' then
            if bits_processed_reg <= 7 then
              pec_reg(7-bits_processed_reg) <= sda_reg;
              bits_processed_reg             <= bits_processed_reg + 1;
            end if;
          end if;
          if scl_falling_reg = '1' and bits_processed_reg = 8 then
           calc_pec<=nextCRC8_D8(pec_reg,calc_pec);  
            bits_processed_reg <= 0;
          end if;
    when rd =>
          sda_wen_reg <= '1';
          sda_o_reg   <= data_to_master_reg(7-bits_processed_reg);
          if scl_falling_reg = '1' then
            if bits_processed_reg < 7 then
              bits_processed_reg <= bits_processed_reg + 1;
            elsif bits_processed_reg = 7 then
              bits_processed_reg <= 0;
            end if;
          end if; 
    when smbus_read_ack_start => 
          if scl_rising_reg = '1' then
            calc_pec<=nextCRC8_D8(data_to_master,calc_pec); 
            if sda_reg = '1' then       -- nack = stop read
              continue_reg <= '0';
            else                   -- ack = continue read
              continue_reg       <= '1';
              read_req_reg       <= '1';  -- request reg byte
              data_to_master_reg <= data_to_master;
            end if;
          end if;
     when rd_pec =>
          sda_wen_reg <= '1';
          sda_o_reg   <= calc_pec(7-bits_processed_reg);
          if scl_falling_reg = '1' then
            if bits_processed_reg < 7 then
              bits_processed_reg <= bits_processed_reg + 1;
            elsif bits_processed_reg = 7 then
              bits_processed_reg <= 0;
              continue_reg <= '0';
            end if;
          end if; 
    when smbus_read_ack_got_rising=>
          continue_reg <= '0';
    when others =>
          null;
    end case;
    end if; 
  end process;

  sda <= sda_o_reg when sda_wen_reg = '1' else
         'Z';
  scl <= scl_o_reg when scl_wen_reg = '1' else
         'Z';
 
  -- Master writes
  data_valid       <= data_valid_reg;
  --data_from_master <= data_reg;
  -- Master reads
  read_req         <= read_req_reg;
end architecture arch;














