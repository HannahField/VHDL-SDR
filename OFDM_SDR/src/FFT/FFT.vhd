library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.fft_pkg.all;
entity FFT is
	generic(
	logN : integer := 12);
	port(
	CLK : in std_logic;
	INPUT_RE : in std_logic_vector(31 downto 0);
	INPUT_IM : in std_logic_vector(31 downto 0);
	OUTPUT_RE : out std_logic_vector(31 downto 0);
	OUTPUT_IM : out std_logic_vector(31 downto 0);
	VALID_IN : in std_logic;
	VALID_OUT : out std_logic;
	
	RST : in std_logic;
	MODE : in std_logic); -- DECIDES FFT (1) / IFFT (0)
end FFT;
architecture RTL of FFT is


-- Input samples are written in bit-reversed order
-- for a radix-2 DIT FFT/IFFT implementation,
-- so the final output can be produced in natural order.



constant N : integer := 2**logN;
constant STAGES : integer := logN;

type ram_N is array (0 to N-1) of word64;

signal RAM_A : ram_N;

signal RAM_B : ram_N;

attribute ramstyle : string;
attribute ramstyle of RAM_A : signal is "M20K";
attribute ramstyle of RAM_B : signal is "M20K";


signal RAM_WRT_SEL  : std_logic := '0'; -- 0 => A WRITE, 1 => B WRITE
signal RAM_READ_SEL : std_logic := '0'; -- 0 => A READ,  1 => B READ

signal READ_PTR : integer range 0 to N-1 := 0;
signal WRT_PTR : integer range 0 to N-1 := 0;

signal VALID_WRT : std_logic;

type c32_array is array (0 to STAGES) of complex_S32;
type sl_array  is array (0 to STAGES) of std_logic;

signal STAGE_DATA  : c32_array;
signal STAGE_VALID : sl_array  := (others => '0');

begin

	assert logN <= 12
	report "FFT: N exceeds twiddle table size"
	severity failure;


	gen_stages : for i in 0 to (logN-1) generate
    stage_i : entity work.FFT_stage
        generic map (
            S => i,
				logN => logN
        )
        port map (
            CLK       => CLK,
            MODE      => MODE,
            VALID_IN  => STAGE_VALID(i),
            VALID_OUT => STAGE_VALID(i+1),
            RST       => RST,
            DIN       => STAGE_DATA(i),
            DOUT      => STAGE_DATA(i+1)
        );
	end generate;
	process(CLK)
	variable w : word64;
	begin
		if rising_edge(CLK) then
			if (RST = '1') then
				READ_PTR <= 0;
				WRT_PTR <= 0;
				RAM_WRT_SEL <= '0';
				RAM_READ_SEL <= '0';
				VALID_WRT <= '0';
				VALID_OUT <= '0';
			else
			if (VALID_IN = '1') then
					if (RAM_WRT_SEL = '0') then
						RAM_A(bit_reverse(WRT_PTR,logN)) <= INPUT_RE & INPUT_IM;
					else
						RAM_B(bit_reverse(WRT_PTR,logN)) <= INPUT_RE & INPUT_IM;
					end if;
					if (WRT_PTR = (N-1)) then
						WRT_PTR <= 0;
						VALID_WRT <= '1';
						RAM_WRT_SEL <= not RAM_WRT_SEL;
					else
						WRT_PTR <= WRT_PTR + 1;
					end if;
				end if;
				
				
				if (VALID_WRT = '1') then
					if (RAM_READ_SEL = '0') then
						w := RAM_A(READ_PTR);
					else
						w := RAM_B(READ_PTR);
					end if;
					STAGE_DATA(0).re <= signed(w(63 downto 32));
					STAGE_DATA(0).im <= signed(w(31 downto 0));
					STAGE_VALID(0) <= '1';
					
					if (READ_PTR = (N-1)) then
						READ_PTR <= 0;
						RAM_READ_SEL <= not RAM_READ_SEL;
						if (WRT_PTR < (N-1)) then
							VALID_WRT <= '0';
						end if;
					else
						READ_PTR <= READ_PTR + 1;
					end if;
				else
					STAGE_VALID(0) <= '0';
				end if;
				
				if (STAGE_VALID(logN) = '1') then
					VALID_OUT <= '1';
					OUTPUT_RE <= std_logic_vector(STAGE_DATA(logN).re);
					OUTPUT_IM <= std_logic_vector(STAGE_DATA(logN).im);
				else
					VALID_OUT <= '0';
				end if;
			end if;
		end if;
	end process;
end RTL;