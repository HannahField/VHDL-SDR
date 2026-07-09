library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SDR is
	generic(
	logN : integer := 10; 		-- Size of IFFT for OFDM
	logM : integer := 8;			-- Amount of data carriers
	
	logQAM : integer := 4;		-- MQAM
	
	k0 : integer := 22;  	 	-- First active bin
	P : integer := 8;			-- Amount of pilot bins (excluding the two edge waves)
	
	CP : integer := 8;  			-- Length of cyclic prefix
	
	DAC_WIDTH : integer := 14; -- DAC resolution
	
	BACK_OFF : integer := -4	-- Extra back-off headroom
	);
	port(
	CLK : in std_logic;
	RST : in std_logic;
	
	TRIG : out std_logic;
	
	DA_MODE : out std_logic;
   POWER_ON : out std_logic;
	 
   PLL_OUT_DAC0 : out std_logic;
	PLL_OUT_DAC1 : out std_logic;
	 
   DA_WRTA : out std_logic;
   DA_WRTB : out std_logic;
	 
	 
   DA_DA : out std_logic_vector(13 downto 0) := (others => '0');
   DA_DB : out std_logic_vector(13 downto 0) := (others => '0')
	);

end SDR;

architecture RTL of SDR is

	constant N : integer := 2**logN;
	constant M : integer := 2**logM;

	signal SOURCE_OUT_RE : std_logic_vector((logQAM/2)-1 downto 0);
	signal SOURCE_OUT_IM : std_logic_vector((logQAM/2)-1 downto 0);
	
	signal SOURCE_VALID_IN : std_logic := '0';
	signal SOURCE_VALID_OUT : std_logic;
	
	signal SHAPER_OUT_RE : std_logic_vector(31 downto 0);
	signal SHAPER_OUT_IM : std_logic_vector(31 downto 0);
	
	signal SHAPER_VALID_OUT : std_logic;
	
	signal OFDM_OUT_RE : std_logic_vector(31 downto 0);
	signal OFDM_OUT_IM : std_logic_vector(31 downto 0);

	signal OFDM_VALID_OUT : std_logic;
	
	constant DATA_WIDTH : integer := logQAM/2;
	
	constant DAC_SCALE : integer := 24 - DAC_WIDTH + BACK_OFF; -- 24 is the size of the data. Scale down to 14 bits and add headroom
	
	signal CNT : integer range 0 to (N+CP-1) := 0; -- Used to control data flow over time
	
	signal SOF : std_logic := '0';
	
	signal SOF_OUT : std_logic;
	
	
	
	signal SHAPER_VALID_D : std_logic := '0'; -- Delayed Shaper_Valid_Out for SOF detection
	
begin
	
	SOURCE : entity work.DATA
	generic map(
	DATA_WIDTH 	=> DATA_WIDTH
	)
	port map(
	CLK			=> CLK,
	RST 			=> RST,
	
	RDY 			=> SOURCE_VALID_IN,
	VALID_OUT	=> SOURCE_VALID_OUT,
	OUTPUT_RE 	=> SOURCE_OUT_RE,
	OUTPUT_IM 	=> SOURCE_OUT_IM
	);

	SHAPER : entity work.Symbol_Shaper
	generic map(
	logQAM => logQAM
	)
	port map(
	CLK			=> CLK,
	RST 			=> RST,
	
	INPUT_RE		=> SOURCE_OUT_RE,
	INPUT_IM		=> SOURCE_OUT_IM,
	VALID_IN		=> SOURCE_VALID_OUT,
	
	OUTPUT_RE	=> SHAPER_OUT_RE,
	OUTPUT_IM	=> SHAPER_OUT_IM,
	VALID_OUT	=> SHAPER_VALID_OUT
	);
	
	OFDM : entity work.OFDM
	generic map(
	logN 			=> logN,
	M				=> M,
	k0				=> k0,
	P				=> P,
	CP				=> CP
	)
	port map(
	CLK			=> CLK,
	RST			=> RST,
	
	SOF 			=> SOF,
	SOF_OUT		=> SOF_OUT,
	
	INPUT_RE 	=> SHAPER_OUT_RE,
	INPUT_IM 	=> SHAPER_OUT_IM,
	VALID_IN		=> SHAPER_VALID_OUT,
	
	OUTPUT_RE	=> OFDM_OUT_RE,
	OUTPUT_IM	=> OFDM_OUT_IM,
	VALID_OUT	=> OFDM_VALID_OUT
	);
	
	
	DAC : entity work.DAC
	generic map(
	DAC_WIDTH => DAC_WIDTH
	)
	port map(
	CLK			=> CLK,
	RST			=> RST,
	
	INPUT_RE		=> OFDM_OUT_RE,
	INPUT_IM		=> OFDM_OUT_IM,
	VALID_IN		=> OFDM_VALID_OUT,
	
	SCALE			=> DAC_SCALE,
	
	DA_MODE		=> DA_MODE,
	POWER_ON		=> POWER_ON,
	
	PLL_OUT_DAC0=> PLL_OUT_DAC0,
	PLL_OUT_DAC1=> PLL_OUT_DAC1,
	
	DA_WRTA		=> DA_WRTA,
	DA_WRTB		=> DA_WRTB,
	
	DA_DA			=> DA_DA,
	DA_DB			=> DA_DB
	);
	
	SOF <= SHAPER_VALID_OUT and not SHAPER_VALID_D;
	
	process(CLK)
	
	begin
		if rising_edge(CLK) then
			if (RST = '1') then
				SOURCE_VALID_IN <= '0';
				SHAPER_VALID_D <= '0';
				CNT <= 0;
			else
				TRIG <= SOF_OUT;
				if (CNT < M) then
					SOURCE_VALID_IN <= '1';
				else
					SOURCE_VALID_IN <= '0';
				end if;
				CNT <= (CNT + 1) mod (N + CP);
				SHAPER_VALID_D <= SHAPER_VALID_OUT;
			end if;
		end if;
	end process;
end RTL;