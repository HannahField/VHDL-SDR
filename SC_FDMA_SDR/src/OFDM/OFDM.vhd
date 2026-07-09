library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity OFDM is
	generic (
	logN : integer := 10;  -- FFT size
	M : integer := 256;    -- Active data subcarriers
	k0 : integer := 22;    -- First active bin
	P : integer := 8;		  -- Amount of internal pilot waves
							     -- There will also be 2 edge pilots
	CP : integer := 8		  -- Length of cyclic prefix
	);							  
	port (
	CLK : in std_logic;
	INPUT_RE : in std_logic_vector(31 downto 0);
	INPUT_IM : in std_logic_vector(31 downto 0);
	
	OUTPUT_RE : out std_logic_vector(31 downto 0);
	OUTPUT_IM : out std_logic_vector(31 downto 0);
	
	VALID_IN : in std_logic;
	VALID_OUT : out std_logic;
	
	SOF : in std_logic;
	
	RST : in std_logic);
end entity;

architecture RTL of OFDM is

	constant N : integer := 2**logN;
	

	subtype word64 is std_logic_vector(63 downto 0);
	subtype word32 is std_logic_vector(31 downto 0);

	type ram_N is array (0 to N-1) of word64;

	
	-- Ping pong style ram for incoming / outgoing
	signal RAM_A : ram_N;
	signal RAM_B : ram_N;

	attribute ramstyle : string;
	attribute ramstyle of RAM_A : signal is "M20K";
	attribute ramstyle of RAM_B : signal is "M20K";
	
	
	signal RAM_WRT_SEL  : std_logic := '0'; -- 0 => A WRITE, 1 => B WRITE
	signal RAM_READ_SEL : std_logic := '0'; -- 0 => A READ,  1 => B READ
	
	signal FULL_A : std_logic := '0';
	signal FULL_B : std_logic := '0';

	signal WRT_PTR : integer range 0 to N-1 := 0;
	signal READ_PTR : integer range 0 to N-1 := N - CP;
	
	signal WRITE_BANK_FREE : std_logic := '1';
	
	signal READ_WORD_A : word64 := (others => '0');
	signal READ_WORD_B : word64 := (others => '0');
	signal READ_VALID : std_logic := '0';
	
	signal READ_SEL_DELAYED : std_logic := '0';
	
	
	signal FFT_IN_RE : std_logic_vector(31 downto 0);
	signal FFT_IN_IM : std_logic_vector(31 downto 0);
	
	
	signal FFT_OUT_RE : std_logic_vector(31 downto 0);
	signal FFT_OUT_IM : std_logic_vector(31 downto 0);
	
	
	signal FFT_VALID_IN : std_logic;
	signal FFT_VALID_OUT : std_logic;
	

	
	constant FFT_MODE : std_logic := '0';
	
	signal OUT_CNT : integer range 0 to (N+CP-1);
	
	constant FIFO_SIZE : integer := N;
	
	signal FIFO : ram_N;
	attribute ramstyle of FIFO : signal is "M20K";
	
	signal FIFO_WRT_PTR  : integer range 0 to FIFO_SIZE-1 := 0;
	signal FIFO_READ_PTR : integer range 0 to FIFO_SIZE-	1 := 0;
	
	signal FIFO_CNT : integer range 0 to FIFO_SIZE := 0;
	
	signal INPUT_IDX : integer range 0 to N := N;
	
	constant PILOT_VAL : std_logic_vector(31 downto 0) := x"002D413C"; -- 1/sqrt(2) in Q2.22
		

	subtype bin_code_t is std_logic_vector(1 downto 0);
	constant GUARD_C : bin_code_t := "00";
	constant PILOT_C : bin_code_t := "01";
	constant DATA_C  : bin_code_t := "10";

	type bin_lut is array(0 to N-1) of bin_code_t;
		
	function BIN_GENERATION return bin_lut is
		constant k_first : integer := k0 - 1;
		constant k_last  : integer := k0 + M + P;      -- inclusive
		constant span    : integer := k_last - k_first; -- = M + P + 1
		
		variable pilot_k : integer := 0; 

		variable bin_map : bin_lut;
	begin
		
		-- Mark everything as guard bins
		for i in 0 to N-1 loop
			bin_map(i) := GUARD_C;
		end loop;
		
		-- Mark occupied region as all data first
		for i in k_first to k_last loop
			bin_map(i) := DATA_C;
		end loop;
		
		for i in 1 to P loop
			pilot_k := k_first + (i*span)/(P+1);
			if (pilot_k > k_first and pilot_k < k_last) then
				bin_map(pilot_k) := PILOT_C;
			end if;
		end loop;
		
		bin_map(k_first) := PILOT_C;
		bin_map(k_last)  := PILOT_C;
		
		return bin_map;
	end BIN_GENERATION;
	
	constant BIN_MAP : bin_lut := BIN_GENERATION;
begin

	assert k0 >= 1 and k0 + M + P <= (N-1)
	report "Occupied band out of FFT bounds"
	severity failure;

	
	
	FFT : entity work.FFT
		generic map(
		logN => logN
		)
		port map(
		CLK 			=> CLK,
		INPUT_RE 	=> FFT_IN_RE,
		INPUT_IM 	=> FFT_IN_IM,
		OUTPUT_RE	=> FFT_OUT_RE,
		OUTPUT_IM 	=> FFT_OUT_IM,
		VALID_IN		=> FFT_VALID_IN,
		VALID_OUT	=> FFT_VALID_OUT,
		RST			=> RST,
		MODE			=> FFT_MODE
		);


		WRITE_BANK_FREE <= '1' when ((RAM_WRT_SEL='0' and FULL_A='0') or
											  (RAM_WRT_SEL='1' and FULL_B='0'))
									  else '0';

		process(CLK)
			variable FIFO_DELTA : integer := 0;
		begin
			FIFO_DELTA := 0;
			if rising_edge(CLK) then
				if (RST = '1') then
					FFT_IN_RE <= (others => '0');
					FFT_IN_IM <= (others => '0');
					OUTPUT_RE <= (others => '0');
					OUTPUT_IM <= (others => '0');
					VALID_OUT <= '0';
					FFT_VALID_IN <= '0';
					OUT_CNT <= 0;
					INPUT_IDX <= N; -- N means idle
					FIFO_CNT <=  0;
					FIFO_WRT_PTR  <= 0;
					FIFO_READ_PTR <= 0;
					WRT_PTR 	<= 0;
					READ_PTR <= N - CP;
					RAM_WRT_SEL  <= '0';
					RAM_READ_SEL <= '0';
					READ_SEL_DELAYED <= '0';
					FULL_A		 <= '0';
					FULL_B		 <= '0';	
					READ_VALID   <= '0';
				else
								
					assert not (SOF='1' and INPUT_IDX < N and INPUT_IDX > 0)
					report "SOF asserted mid-symbol" severity failure;
					-- Write inputs into FIFO buffer
					if (VALID_IN = '1') then
						FIFO(FIFO_WRT_PTR) <= INPUT_RE & INPUT_IM;
						FIFO_DELTA := FIFO_DELTA + 1;
						FIFO_WRT_PTR <= (FIFO_WRT_PTR + 1) mod FIFO_SIZE;
					end if;
					-- If start of frame, reset input index
					if (SOF = '1') then
						INPUT_IDX <= 0;
					end if;
					-- If INPUT_IDX < N, check what type the bin is and pass that to the IFFT core
					-- If INPUT_IDX = N, do nothing, since we dont have any data to pass to the core
					-- INPUT_IDX resets when SOF = '1'
					
					if (INPUT_IDX < N and WRITE_BANK_FREE = '1') then
						case BIN_MAP(INPUT_IDX) is
							when GUARD_C =>
								FFT_IN_RE <= (others => '0');
								FFT_IN_IM <= (others => '0');
								FFT_VALID_IN <= '1';
								INPUT_IDX <= INPUT_IDX + 1;
							when PILOT_C =>
								FFT_IN_RE <= PILOT_VAL;
								FFT_IN_IM <= PILOT_VAL;
								FFT_VALID_IN <= '1';
								INPUT_IDX <= INPUT_IDX + 1;
							when DATA_C => 
							if (FIFO_CNT > 0) then
								FFT_IN_RE <= FIFO(FIFO_READ_PTR)(63 downto 32);
								FFT_IN_IM <= FIFO(FIFO_READ_PTR)(31 downto 0);
								FIFO_DELTA := FIFO_DELTA - 1;
								FIFO_READ_PTR <= (FIFO_READ_PTR + 1) mod FIFO_SIZE;
								FFT_VALID_IN <= '1';
								INPUT_IDX <= INPUT_IDX + 1;
							else
								FFT_VALID_IN <= '0';
							end if;
							when others =>
								FFT_IN_RE <= (others => '0');
								FFT_IN_IM <= (others => '0');
								FFT_VALID_IN <= '0';
								INPUT_IDX <= INPUT_IDX + 1;
						end case;
					else
						FFT_VALID_IN <= '0';
					end if;
					-- Update FIFO_CNT
					FIFO_CNT <= FIFO_CNT + FIFO_DELTA;
					
					if (FFT_VALID_OUT = '1') then
						if (RAM_WRT_SEL = '0') then
							RAM_A(WRT_PTR) <= FFT_OUT_RE & FFT_OUT_IM;
						else
							RAM_B(WRT_PTR) <= FFT_OUT_RE & FFT_OUT_IM;
						end if;
					
						if (WRT_PTR = (N-1)) then
							WRT_PTR <= 0;
							RAM_WRT_SEL <= not RAM_WRT_SEL;
							if (RAM_WRT_SEL = '0') then
								FULL_A <= '1';
							else
								FULL_B <= '1';
							end if;
						else
							WRT_PTR <= WRT_PTR + 1;
						end if;
					end if;
					
					if (RAM_READ_SEL = '0' and FULL_A = '1') then
						READ_VALID <= '1';
						if (OUT_CNT = (N + CP - 1)) then
							READ_PTR <= N - CP;
							OUT_CNT <= 0;
							RAM_READ_SEL <= not RAM_READ_SEL;
							FULL_A <= '0';
						else
							READ_PTR <= (READ_PTR + 1) mod N;
							OUT_CNT <= OUT_CNT + 1;
						end if;
					elsif (RAM_READ_SEL = '1' and FULL_B = '1') then
						READ_VALID <= '1';
						if (OUT_CNT = (N + CP - 1)) then
							READ_PTR <= N - CP;
							OUT_CNT <= 0;
							RAM_READ_SEL <= not RAM_READ_SEL;
							FULL_B <= '0';
						else
							READ_PTR <= (READ_PTR + 1) mod N;
							OUT_CNT <= OUT_CNT + 1;
						end if;
					else
						READ_VALID <= '0';
					end if;
					READ_WORD_A <= RAM_A(READ_PTR);
					READ_WORD_B <= RAM_B(READ_PTR);
					VALID_OUT <= READ_VALID;
					READ_SEL_DELAYED <= RAM_READ_SEL;
					if (READ_SEL_DELAYED = '0') then
						OUTPUT_RE <= READ_WORD_A(63 downto 32);
						OUTPUT_IM <= READ_WORD_A(31 downto 0 );
					else
						OUTPUT_RE <= READ_WORD_B(63 downto 32);
						OUTPUT_IM <= READ_WORD_B(31 downto 0 );
					end if;
				end if;
			end if;
		end process;

end RTL;