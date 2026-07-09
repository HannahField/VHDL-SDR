library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.fft_pkg.all;

entity FFT_stage is

   generic (
   S : integer;
	logN : integer);
	port (
	CLK : in std_logic;
	MODE : in std_logic; -- DECIDES FFT (1) / IFFT (0)
	VALID_IN : in std_logic;
	VALID_OUT : out std_logic;
	RST : in std_logic;
	DIN : in complex_S32;
	DOUT : out complex_S32);
	
end FFT_stage;

architecture RTL of FFT_stage is
constant DELAY : integer := 2**S;
constant N : integer := 2**logN;
constant STRIDE : integer := N/(2*DELAY);

constant FIFO_SIZE : integer := DELAY;

type delay_ram_t is array (0 to DELAY-1) of word64;
type FIFO_ram_t is array (0 to FIFO_SIZE-1) of word64;
signal DELAY_MEM : delay_ram_t;

signal FIFO : FIFO_ram_t;

attribute ramstyle : string;
attribute ramstyle of DELAY_MEM : signal is "M20K";
attribute ramstyle of FIFO : signal is "M20K";

signal SAMPLE_CNT : integer range 0 to (2*DELAY-1);

signal WRT_PTR  : integer range 0 to FIFO_SIZE-1 := 0;
signal READ_PTR : integer range 0 to FIFO_SIZE-1 := 0;

signal FIFO_CNT : integer range 0 to FIFO_SIZE := 0;

begin
	assert S < logN
	report "FFT_stage: S must be < logN"
	severity failure;
	
	process(CLK)
		variable A  : complex_S32;
		variable B  : complex_S32;
		variable T  : complex_S32;
		variable W  : complex_S16;
		
		variable Y0 : complex_S32;
		variable Y1 : complex_S32;
		
		variable FIFO_DELTA : integer range -1 to 2 := 0;
		
		variable TW_CNT : integer range 0 to (DELAY-1) := 0;
		
		variable bw : word64;
		variable fw : word64;
	
	begin
		if rising_edge(CLK) then
			FIFO_DELTA := 0;
			-- RESET LOGIC
			if RST = '1' then
				SAMPLE_CNT <= 0;
				VALID_OUT <= '0';
				DOUT <= (re => (others => '0'), im => (others => '0'));
				WRT_PTR <= 0;
				READ_PTR <= 0;
				FIFO_CNT <= 0;
			else
				if (VALID_IN = '1') then
					-- DELAY THE FIRST HALF OF SAMPLES
					if (SAMPLE_CNT < DELAY) then
						DELAY_MEM(SAMPLE_CNT) <= std_logic_vector(DIN.re) & std_logic_vector(DIN.im);
					else
						TW_CNT := SAMPLE_CNT - DELAY;
						bw := DELAY_MEM(TW_CNT);
						A.re := signed(bw(63 downto 32));
						A.im := signed(bw(31 downto 0));
						B := DIN;
						W := twiddle(TW_CNT * STRIDE, MODE, N);
						T := multc(B,W);
						
						-- SHIFT RIGHT IF IFFT TO SCALE DOWN
						if MODE = '0' then
							Y0 := shift_right_c32(add_c32(A,T),1);
							Y1 := shift_right_c32(sub_c32(A,T),1);
						else
							Y0 := add_c32(A,T);
							Y1 := sub_c32(A,T);
						end if;
						
						DOUT.re <= Y0.re;
						DOUT.im <= Y0.im;
						
						FIFO(WRT_PTR)  <= std_logic_vector(Y1.re) & std_logic_vector(Y1.im);
						
						WRT_PTR <= (WRT_PTR + 1) mod FIFO_SIZE;
						
						FIFO_DELTA := FIFO_DELTA + 1;
						VALID_OUT <= '1';
					end if;
					SAMPLE_CNT <= (SAMPLE_CNT + 1) mod (2*DELAY);
				end if;
				
				
				-- OUTPUT LOGIC
				if (SAMPLE_CNT < DELAY or VALID_IN = '0') then
					if (FIFO_CNT > 0) then
						
						DOUT.re <= signed(FIFO(READ_PTR)(63 downto 32));
						DOUT.im <= signed(FIFO(READ_PTR)(31 downto 0));

						VALID_OUT <= '1';
						FIFO_DELTA := FIFO_DELTA - 1;
						READ_PTR <= (READ_PTR + 1) mod FIFO_SIZE;
					else
						VALID_OUT <= '0'; 
					end if;
				end if;
				assert FIFO_CNT + FIFO_DELTA <= FIFO_SIZE
				report "FFT FIFO overflow"
				severity failure;
				
				assert FIFO_CNT + FIFO_DELTA >= 0
				report "FFT FIFO underflow"
				severity failure;


					FIFO_CNT <= FIFO_CNT + FIFO_DELTA;
			end if;
		end if;
	end process;
end RTL;