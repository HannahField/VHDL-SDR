library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity DAC is
	generic (
	DAC_WIDTH : natural := 14);
	port (
   CLK : in  std_logic;
	RST : in std_logic;
	 
	INPUT_RE : in std_logic_vector(31 downto 0);
	INPUT_IM : in std_logic_vector(31 downto 0);
	 
	VALID_IN : in std_logic;
	
	SCALE : in natural range 0 to 31;
	
   DA_MODE : out std_logic;
   POWER_ON : out std_logic;
	 
   PLL_OUT_DAC0 : out std_logic;
	PLL_OUT_DAC1 : out std_logic;
	 
   DA_WRTA : out std_logic;
   DA_WRTB : out std_logic;
	 
	 
   DA_DA : out std_logic_vector(13 downto 0) := (others => '0');
   DA_DB : out std_logic_vector(13 downto 0) := (others => '0'));
end DAC;

architecture RTL of DAC is

	subtype dac_uint_t is unsigned(DAC_WIDTH-1 downto 0);
	subtype dac_int_t is signed(DAC_WIDTH-1 downto 0);
	

	function signed_to_offset(x : dac_int_t) return dac_uint_t is
		variable u : signed(DAC_WIDTH downto 0);
	begin
		u := resize(x,DAC_WIDTH+1) + to_signed(2**(DAC_WIDTH-1),DAC_WIDTH+1); -- +8192
		return resize(unsigned(u),DAC_WIDTH);
	end;
  
	function scale_to_dac (x : signed; s : natural) return dac_int_t is
		variable u : signed(x'length-1 downto 0);
	begin
		u := shift_right(x,s);
		if u > to_signed(2**(DAC_WIDTH-1) - 1,x'length) then
			return to_signed(2**(DAC_WIDTH-1)-1,DAC_WIDTH);
		elsif (u < to_signed(-2**(DAC_WIDTH-1),x'length)) then
			return to_signed(-2**(DAC_WIDTH-1),DAC_WIDTH);
		else
			return resize(u,DAC_WIDTH);
		end if;
	end;

begin

	PLL_OUT_DAC0 <= CLK;
	PLL_OUT_DAC1 <= CLK;
	
	DA_WRTA <= not CLK; 
	DA_WRTB <= not CLK;

	
	DA_MODE <= '1'; -- Dual Channel Mode
	POWER_ON <= '1'; -- On/Off

	
	process(CLK)
	variable DATA_RE : signed(31 downto 0);
	variable DATA_IM : signed(31 downto 0);
	
	variable DATA_A : dac_uint_t;
	variable DATA_B : dac_uint_t;
	
	constant ZERO : dac_uint_t := signed_to_offset((others => '0'));
	
	begin
		if rising_edge(CLK) then
			if (RST = '1') then
				DATA_A := ZERO;
				DATA_B := ZERO;
			else
			
				DATA_RE := signed(INPUT_RE);
				DATA_IM := signed(INPUT_IM);
			
				if (VALID_IN = '1') then
					DATA_A := signed_to_offset(scale_to_dac(DATA_RE,SCALE));
					DATA_B := signed_to_offset(scale_to_dac(DATA_IM,SCALE));
				else
					DATA_A := ZERO;
					DATA_B := ZERO;
				end if;
			end if;
			DA_DA <= std_logic_vector(DATA_A);
			DA_DB <= std_logic_vector(DATA_B);
		end if;
	end process;
	
end RTL;
