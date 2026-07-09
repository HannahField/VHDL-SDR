library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SDR is
	generic(
	
	logQAM : integer := 4;			-- MQAM
	
	PULSE_SCALE : natural := 14;  -- Shift factor for pulse shaper
	
	FREQ_STEP : integer := 410;	-- Frequency shifter step size
	
	DAC_WIDTH : natural := 14; 	-- DAC resolution
	
	BACK_OFF : integer := -1		-- Extra back-off headroom
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

	signal SOURCE_OUT_RE : std_logic_vector((logQAM/2)-1 downto 0);
	signal SOURCE_OUT_IM : std_logic_vector((logQAM/2)-1 downto 0);
	
	signal SOURCE_VALID_IN : std_logic := '0';
	signal SOURCE_VALID_OUT : std_logic;
	
	signal SHAPER_OUT_RE : std_logic_vector(31 downto 0);
	signal SHAPER_OUT_IM : std_logic_vector(31 downto 0);
	
	signal SHAPER_VALID_OUT : std_logic;
	
	signal PULSE_OUT_RE : std_logic_vector(31 downto 0);
	signal PULSE_OUT_IM : std_logic_vector(31 downto 0);
	
	signal PULSE_VALID_OUT : std_logic;

	signal FREQ_OUT_RE : std_logic_vector(31 downto 0);
	signal FREQ_OUT_IM : std_logic_vector(31 downto 0);

	signal FREQ_VALID_OUT : std_logic;
	
	constant DATA_WIDTH : integer := logQAM/2;
	constant DAC_SCALE : integer := 24 - DAC_WIDTH + BACK_OFF; -- 24 is the size of the data. Scale down to 14 bits and add headroom
	
	signal CNT : integer range 0 to 9 := 0;
	
	
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
	logM => logQAM
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
	
	PULSE : entity work.Pulse
	generic map(
	SCALE 		=> PULSE_SCALE
	)
	port map(
	CLK			=> CLK,
	RST			=> RST,
	TRIG			=> TRIG,
	
	INPUT_RE		=> SHAPER_OUT_RE,
	INPUT_IM		=> SHAPER_OUT_IM,
	VALID_IN		=> SHAPER_VALID_OUT,
	
	OUTPUT_RE	=> PULSE_OUT_RE,
	OUTPUT_IM	=> PULSE_OUT_IM,
	VALID_OUT	=> PULSE_VALID_OUT
	);
	
	FREQ : entity work.FREQ
	generic map(
	STEP => FREQ_STEP
	)
	port map(
	CLK			=> CLK,
	RST			=> RST,
	
	INPUT_RE		=> PULSE_OUT_RE,
	INPUT_IM		=> PULSE_OUT_IM,
	VALID_IN		=> PULSE_VALID_OUT,
	
	OUTPUT_RE	=> FREQ_OUT_RE,
	OUTPUT_IM	=> FREQ_OUT_IM,
	VALID_OUT	=> FREQ_VALID_OUT
	);
	
	DAC : entity work.DAC
	generic map(
	DAC_WIDTH => DAC_WIDTH
	)
	port map(
	CLK			=> CLK,
	RST			=> RST,
	
	INPUT_RE		=> FREQ_OUT_RE,
	INPUT_IM		=> FREQ_OUT_IM,
	VALID_IN		=> FREQ_VALID_OUT,
	
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
	
	
	process(CLK)
	begin
		if rising_edge(CLK) then
			if (RST = '1') then
				CNT <= 0;
				SOURCE_VALID_IN <= '0';
			else
				if (CNT = 0) then
					SOURCE_VALID_IN <= '1';
				else
					SOURCE_VALID_IN <= '0';
				end if;
				CNT <= (CNT + 1) mod 10;
			end if;
		end if;
	end process;	
end RTL;