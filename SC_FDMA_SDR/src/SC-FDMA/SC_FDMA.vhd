library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity SC_FDMA is
	generic (
	logN : integer := 10;  -- FFT size
	logM : integer := 8;   -- Active data subcarriers
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
	
	
	RST : in std_logic);
end entity;

architecture RTL of SC_FDMA is

	constant N : integer := 2**logN;
	constant M : integer := 2**logM;

	subtype word64 is std_logic_vector(63 downto 0);
	type FIFO_ram is array(0 to M-1) of word64;
	
	signal FIFO : FIFO_ram;
	
	attribute ramstyle : string;
	attribute ramstyle of FIFO : signal is "M20K";


	constant FIFO_SIZE : integer := M;
	signal FIFO_CNT : integer range 0 to FIFO_SIZE := 0;
	signal READ_PTR : integer range 0 to FIFO_SIZE-1 := 0;
	signal WRT_PTR  : integer range 0 to FIFO_SIZE-1 := 0;
	
	signal DRAIN : std_logic := '0';
	
	signal FFT_VALID_OUT : std_logic;
	signal FFT_VALID_IN : std_logic := '0';
	
	signal FFT_INPUT_RE : std_logic_vector(31 downto 0);
	signal FFT_INPUT_IM : std_logic_vector(31 downto 0);
	
	signal FFT_OUTPUT_RE : std_logic_vector(31 downto 0);
	signal FFT_OUTPUT_IM : std_logic_vector(31 downto 0);
	
	signal OFDM_VALID_IN : std_logic;
	
	signal OFDM_INPUT_RE : std_logic_vector(31 downto 0);
	signal OFDM_INPUT_IM : std_logic_vector(31 downto 0);
	
	signal SOF : std_logic := '0';
	
	constant FFT_MODE : std_logic := '1';
	
	constant SCALE : natural := logM/2;
 	
begin

	   DFT : entity work.FFT
		generic map(
		logN => logM
		)
		port map(
		CLK 			=> CLK,
		INPUT_RE 	=> FFT_INPUT_RE,
		INPUT_IM 	=> FFT_INPUT_IM,
		OUTPUT_RE	=> FFT_OUTPUT_RE,
		OUTPUT_IM 	=> FFT_OUTPUT_IM,
		VALID_IN		=> FFT_VALID_IN,
		VALID_OUT	=> FFT_VALID_OUT,
		RST			=> RST,
		MODE			=> FFT_MODE
		);
		
		
		OFDM : entity work.OFDM
		generic map(
		logN => logN,
		M => M,
		k0 => k0,
		P => P,
		CP => CP
		)
		port map(
		CLK 			=> CLK,
		INPUT_RE 	=> OFDM_INPUT_RE,
		INPUT_IM 	=> OFDM_INPUT_IM,
		OUTPUT_RE	=> OUTPUT_RE,
		OUTPUT_IM 	=> OUTPUT_IM,
		VALID_IN		=> OFDM_VALID_IN,
		VALID_OUT	=> VALID_OUT,
		RST			=> RST,
		SOF			=> SOF
		);

		assert logN >= logM
		report "SC_FDMA: logN must be >= logM for post-DFT scaling"
		severity failure;
		
		process(CLK)
			variable FIFO_DELTA : integer range -1 to 1 := 0;
		begin
			if rising_edge(CLK) then
			FIFO_DELTA := 0;
			
				if (RST = '1') then
					FIFO_CNT <= 0;
					READ_PTR <= 0;
					WRT_PTR  <= 0;
					
					DRAIN <= '0';
				
					FFT_VALID_IN <= '0';
					FFT_INPUT_RE <= (others => '0');
					FFT_INPUT_IM <= (others => '0');
					
					SOF <= '0';
					OFDM_VALID_IN <= '0';
					
					
				else
				
					FFT_VALID_IN <= VALID_IN;
					FFT_INPUT_RE <= INPUT_RE;
					FFT_INPUT_IM <= INPUT_IM;
						
					-- DEFAULTS
					SOF <= '0';

				
					if (FFT_VALID_OUT = '1') then
						FIFO(WRT_PTR) <= std_logic_vector(shift_right(signed(FFT_OUTPUT_RE), SCALE)) 
											& std_logic_vector(shift_right(signed(FFT_OUTPUT_IM), SCALE));
						FIFO_DELTA := FIFO_DELTA + 1;
						if (WRT_PTR = M-1) then
							DRAIN <= '1';
							WRT_PTR <= 0;
						else
							WRT_PTR <= WRT_PTR + 1;
						end if;
					end if;
					
					if (DRAIN = '1') then
						
						OFDM_INPUT_RE <= FIFO(READ_PTR)(63 downto 32);
						OFDM_INPUT_IM <= FIFO(READ_PTR)(31 downto 0 );
						OFDM_VALID_IN <= '1';
						FIFO_DELTA := FIFO_DELTA - 1;
						
						if (READ_PTR = M - 1) then
							READ_PTR <= 0;
							DRAIN <= '0';
						elsif (READ_PTR = 0) then
							READ_PTR <= READ_PTR + 1;
							SOF <= '1';
							report "SOF = '1'";
							report integer'image(FIFO_CNT);
						else
							READ_PTR <= READ_PTR + 1;
							SOF <= '0';
						end if;
					else
						OFDM_VALID_IN <= '0';
					
					end if;
					
					FIFO_CNT <= FIFO_CNT + FIFO_DELTA;
					
					assert not (FIFO_CNT = M and FIFO_DELTA = 1)
					report "FIFO overflowing"
					severity failure;
					
					assert not (FIFO_CNT = 0 and FIFO_DELTA = -1)
					report "FIFO underflowing"
					severity failure;
					
					assert not (FFT_VALID_OUT = '1' and DRAIN = '1')
					report "FFTing while still draining"
					severity failure;
					
										
					assert not (VALID_IN='1' and DRAIN='1')
					report "Receiving inputs while draining"
					severity failure;



				end if;
			end if;
		end process;
end RTL;