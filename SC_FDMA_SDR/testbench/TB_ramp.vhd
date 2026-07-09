library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use std.textio.all;
 
 entity TB_ramp is
 end entity;
 
 architecture Testbench of TB_ramp is
 
 
	constant CLK_PERIOD : time := 20 ns;
	
	signal CLK : std_logic := '0';
	signal RST : std_logic := '1';
	
	
	signal INPUT_RE : std_logic_vector(31 downto 0);
	signal INPUT_IM : std_logic_vector(31 downto 0);
	
	signal OUTPUT_RE : std_logic_vector(31 downto 0);
	signal OUTPUT_IM : std_logic_vector(31 downto 0);	
	constant logN : integer := 10;  -- FFT size
	constant logM : integer := 8;   -- Active data subcarriers
	constant k0 : integer := 22;    -- First active bin
	constant P : integer := 8;		  -- Amount of internal pilot waves
											  -- There will also be 2 edge pilots
	constant CP : integer := 8;
	constant N : integer := 2**logN;
	constant M : integer := 2**logM;
 
	signal SOF : std_logic := '0';
	
	signal VALID_IN : std_logic := '0';
	signal VALID_OUT : std_logic;
	
	signal CNT : integer range 0 to M := 0;
	
	file outfile : text open write_mode is "ramp_out.txt";
	
	constant SLOPE : signed := to_signed(262143,32);
	
	begin
	
		DUT : entity work.SC_FDMA
			generic map(
			logN => logN,
			logM => logM,
			k0 => k0,
			P => P,
			CP => CP
			)
			port map(
			CLK => CLK,
			RST => RST,
			INPUT_RE => INPUT_RE,
			INPUT_IM => INPUT_IM,
			OUTPUT_RE => OUTPUT_RE,
			OUTPUT_IM => OUTPUT_IM,
			VALID_IN => VALID_IN,
			VALID_OUT => VALID_OUT
			);
			
		
		CLK <= not CLK after CLK_PERIOD/2;

		
		reset_process : process
		begin
			RST <= '1';
			wait for 5 * CLK_PERIOD;
			RST <= '0';
			wait; -- never ends the process
		end process;
		
		stim : process(CLK)
		begin
			if rising_edge(CLK) then
				if (RST = '0') then
					if (CNT < M) then
						INPUT_RE <= std_logic_vector(resize(SLOPE * CNT, 32));
						INPUT_IM <= std_logic_vector(resize(SLOPE * CNT, 32));
						VALID_IN <= '1';
						CNT <= CNT + 1;
					else
						VALID_IN <= '0';						
						INPUT_RE <= (others => '0');
						INPUT_IM <= (others => '0');
					end if;
				end if;
			end if;
		end process;
		
		capture : process(CLK)
			variable L : line;
		begin
			if rising_edge(CLK) then
				if VALID_OUT = '1' then
					write(L, integer'image(to_integer(signed(output_re))));
					write(L, string'(", "));
					write(L, integer'image(to_integer(signed(output_im))));
					writeline(outfile, L);
				end if;
			end if;
		end process;
	
 end Testbench;