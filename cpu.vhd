-- cpu.vhd: Simple 8-bit CPU (BrainLove interpreter)
-- Copyright (C) 2021 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Ekaterina Krupenko, xkrupe00
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet ROM
   CODE_ADDR : out std_logic_vector(11 downto 0); -- adresa do pameti
   CODE_DATA : in std_logic_vector(7 downto 0);   -- CODE_DATA <- rom[CODE_ADDR] pokud CODE_EN='1'
   CODE_EN   : out std_logic;                     -- povoleni cinnosti
   
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(9 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- ram[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_WREN  : out std_logic;                    -- cteni z pameti (DATA_WREN='0') / zapis do pameti (DATA_WREN='1')
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA obsahuje stisknuty znak klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna pokud IN_VLD='1'
   IN_REQ    : out std_logic;                     -- pozadavek na vstup dat z klavesnice
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- pokud OUT_BUSY='1', LCD je zaneprazdnen, nelze zapisovat,  OUT_WREN musi byt '0'
   OUT_WREN : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

	signal pc_out : std_logic_vector (11 downto 0);
	signal pc_inc: std_logic;
	signal pc_dec: std_logic;
	
	signal cnt_out: std_logic_vector (7 downto 0);
	signal cnt_inc: std_logic;
	signal cnt_dec: std_logic;
	
	signal ptr_out: std_logic_vector (9 downto 0); 
	signal ptr_inc: std_logic;
	signal ptr_dec: std_logic;

	type instructions is(
		inc_ptr,
		dec_ptr,
		inc_val,
		dec_val,
		while_start,
		while_end,
		putchar,
		getchar,
		return_null,
		other);

	signal decode : instructions;
    
	type fsm_states is(
		-- state_idle,
		state_fetch,
		state_decode,
		state_inc_ptr,
		state_dec_ptr,
		state_inc_val,
		state_dec_val,
		state_inc_val_do,
		state_dec_val_do,
		state_while_start,
		state_while_start_do,
		state_while_begin,
		state_while_get,
		state_while_continue,
		state_return_begin,
		state_while_end,
		state_while_end_do,
		state_putchar,
		state_putchar_do,
		state_getchar,
		state_getchar_do,
		state_return_null);

	signal present_state, next_state : fsm_states;

 -- zde dopiste potrebne deklarace signalu

begin
	CODE_ADDR <= pc_out;
	DATA_ADDR <= ptr_out;
	
	--conditions for switch states
	fsm_pesent_state: process (RESET,CLK)
	begin
		if (RESET = '1') then
			present_state <= state_fetch;
		elsif (CLK'event) and (CLK = '1') then
			if (EN = '1') then
				present_state <= next_state;
			end if;
		end if;
	end process fsm_pesent_state;
	
	--The PC register is a program counter ( a pointer to the program memory ROM)
	pc: process(RESET, CLK, pc_inc, pc_dec)
	begin
		if (RESET = '1') then
			pc_out <= "000000000000";
		elsif (CLK'event) and (CLK = '1') then
			if (pc_inc = '1') then
				pc_out <= pc_out + 1;
			elsif (pc_dec = '1') then
				pc_out <= pc_out - 1;
			end if;
		end if;
		
	end process pc;
    
	--The PTR register is a pointer to the data memory RAM
	ptr: process(RESET, CLK, ptr_inc, ptr_dec)
	begin
		if (RESET = '1') then
			ptr_out <= "0000000000";
		elsif (CLK'event) and (CLK = '1') then
			if (ptr_inc = '1') then
				ptr_out <= ptr_out + 1;
			elsif (ptr_dec = '1') then
				ptr_out <= ptr_out - 1;
			end if;
		end if;
	end process ptr;

    --the CNT register is used to correctly determine the corresponding start / end of the instruction while
	cnt: process(RESET, CLK, cnt_inc, cnt_dec)
	begin
		if (RESET = '1') then
			cnt_out <= "00000000";
		elsif (CLK'event) and (CLK = '1') then
			if (cnt_inc = '1') then
				cnt_out <= cnt_out + 1;
			elsif (cnt_dec = '1') then
				cnt_out <= cnt_out - 1;
			end if;
		end if;
	end process cnt;
	
	--decodeng instructions
	fsm_proc: process (CODE_DATA)
	begin
		case (CODE_DATA) is
			when X"3E"	=> decode <= inc_ptr;	    -- '>'
			when X"3C"	=> decode <= dec_ptr;	    -- '<'
			when X"2B"	=> decode <= inc_val;	    -- '+'
			when X"2D"	=> decode <= dec_val;	    -- '-'
			when X"5B"	=> decode <= while_start;	-- '['
			when X"5D"	=> decode <= while_end;	    -- ']'
			when X"2E"	=> decode <= putchar;		-- '.'
			when X"2C"	=> decode <= getchar;		-- ','
			when X"00"	=> decode <= return_null;	-- null
			when others	=> decode <= other;			-- other
		end case;
	end process fsm_proc;
	
	fsm_next_state: process(CODE_DATA, DATA_RDATA, EN, IN_DATA, IN_VLD, OUT_BUSY, present_state, decode)
	begin
	
		next_state <= state_fetch;
		
		DATA_WREN  <= '0'; 
		DATA_WDATA <= X"00";
		OUT_WREN   <= '0';
		IN_REQ     <= '0';
		DATA_EN    <= '0';
		CODE_EN    <= '0';
		pc_dec     <= '0'; 
		pc_inc     <= '0';
		cnt_inc    <= '0';
		cnt_dec    <= '0';
		ptr_inc    <= '0'; 
		ptr_dec    <= '0';
		
		case present_state is 		
			--load instructions into CODE_DATA
			when state_fetch =>
				CODE_EN <= '1';
				next_state <= state_decode;
			--intruction to states in fsm
			when state_decode =>
				case decode is
			        when return_null => next_state  <= state_return_null;
					when inc_ptr     => next_state  <= state_inc_ptr;
					when dec_ptr     => next_state  <= state_dec_ptr;
					when inc_val     => next_state  <= state_inc_val;
					when dec_val     => next_state  <= state_dec_val;
					when putchar     => next_state  <= state_putchar;
					when getchar     => next_state  <= state_getchar;		
					when while_start => next_state  <= state_while_start;
					when while_end   => next_state  <= state_while_end;
					--other characters not use for decoding
					when other =>
						next_state <= state_fetch;
						pc_inc <= '1';
					when others =>
						pc_inc <= '1';
				end case;
				
			--increment of the pointer value
			when state_inc_ptr =>
				pc_inc <= '1';
				ptr_inc <= '1';
				next_state <= state_fetch;

			--decrement of the pointer value
			when state_dec_ptr =>
				ptr_dec <= '1';
				pc_inc <= '1';
				next_state <= state_fetch;

			--value incrementation
			when state_inc_val =>
				DATA_EN <= '1';
				DATA_WREN <= '0';

				next_state <= state_inc_val_do;

			when state_inc_val_do =>
				DATA_WDATA <= DATA_RDATA + 1;
				DATA_WREN <= '1';
				DATA_EN <= '1';

				pc_inc <= '1';
				next_state <= state_fetch;
			
		    --value decrementation
			when state_dec_val =>
				DATA_EN <= '1';
				DATA_WREN <= '0';

				next_state <= state_dec_val_do;

			when state_dec_val_do =>
				DATA_EN <= '1';
				DATA_WREN <= '0';
				DATA_WDATA <= DATA_RDATA - 1;
				DATA_EN <= '1';
				DATA_WREN <= '1';
				pc_inc <= '1';
				next_state <= state_fetch;

            --the start of cycle
			when state_while_start =>
				DATA_EN <= '1';
				DATA_WREN <= '0';
				next_state <= state_while_start_do;

			when state_while_start_do =>
				if (DATA_RDATA = 0) then
					pc_inc <= '1';
					cnt_inc <= '1';
					next_state <= state_while_continue;
				else
					pc_inc <= '1';
					next_state <= state_fetch;
				end if;
			
			--skipping to the end
			when state_while_begin =>
				if (decode = while_end) then
					pc_inc <= '1';
					next_state <= state_fetch;
				else
					pc_inc <= '1';
					next_state <= state_while_continue;
				end if;
				
			--cycle slowdown
			when state_while_continue=>
				CODE_EN <= '1';
				next_state <= state_while_begin;
				
			--the end of cycle
			when state_while_end =>
				DATA_EN <= '1';
				DATA_WREN <= '0';
				next_state <= state_while_end_do;

			when state_while_end_do =>
				if (DATA_RDATA = 0) then
					pc_inc <= '1';
					next_state <= state_fetch;
				else
					pc_dec <= '1';
					next_state <= state_while_get;
				end if;
				
			--skipping to the start
			when state_return_begin =>
				if (decode = while_start) then
					next_state <= state_fetch;
				else
					pc_dec<='1';
					next_state <= state_while_get;
				end if;
				
			--cycle slowdown
			when state_while_get =>
				CODE_EN <= '1';
				next_state <= state_return_begin;
				
			--print the current value 
			when state_putchar =>
				DATA_EN <= '1';
				DATA_WREN <= '0';
				next_state <= state_putchar_do;
				
			when state_putchar_do =>
				if (OUT_BUSY = '0') then
					OUT_DATA <= DATA_RDATA;
					OUT_WREN <= '1';
					pc_inc <= '1';
					next_state <= state_fetch;
				else
					DATA_EN <= '1';
					DATA_WREN <= '0';
					next_state <= state_putchar_do;
				end if;

			--read the value and save it
			when state_getchar =>
				IN_REQ <= '1';
				next_state <= state_getchar_do;
				
			
			when state_getchar_do =>
				if (IN_VLD='1') then
					
					DATA_WDATA <= IN_DATA;
					DATA_WREN <= '1';
					DATA_EN <= '1';
					
					pc_inc <= '1';
					next_state <= state_fetch;
				else
					IN_REQ <= '1';
					next_state <= state_getchar_do;
				end if;
			
			--the end
			when state_return_null =>
				next_state <= state_return_null;
			when others =>
		end case;
	end process;

end behavioral;

