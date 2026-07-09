library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Pulse is
	generic(
		SCALE : natural := 15
	);
	port (
		CLK : in std_logic;
		RST : in std_logic;
		TRIG : out std_logic;
		
		INPUT_RE : in std_logic_vector(31 downto 0);
		INPUT_IM : in std_logic_vector(31 downto 0);
		
		VALID_IN : in std_logic;
		
		OUTPUT_RE : out std_logic_vector(31 downto 0);
		OUTPUT_IM : out std_logic_vector(31 downto 0);
		
		VALID_OUT : out std_logic
	);
end Pulse;

architecture RTL of Pulse is

	
	subtype signed64 is signed(63 downto 0);
	subtype signed32 is signed(31 downto 0);
	subtype signed16 is signed(15 downto 0);

	type coef_vec_16 is array (0 to 6) of signed16;
	type coef_phases is array (0 to 9) of coef_vec_16;
	
	
	constant C : coef_phases := (

    0 => (to_signed(-264,16), to_signed(592,16),  to_signed(-878,16), to_signed(11356,16), to_signed(-878,16), to_signed(592,16),  to_signed(-264,16)),
    1 => (to_signed(-262,16), to_signed(347,16),  to_signed(117,16),  to_signed(11118,16), to_signed(-1548,16),to_signed(712,16),  to_signed(0,16)),
    2 => (to_signed(-204,16), to_signed(-14,16),  to_signed(1407,16), to_signed(10423,16), to_signed(-1895,16),to_signed(714,16),  to_signed(0,16)),
    3 => (to_signed(-89,16),  to_signed(-460,16), to_signed(2930,16), to_signed(9327,16),  to_signed(-1948,16),to_signed(620,16),  to_signed(0,16)),
    4 => (to_signed(74,16),   to_signed(-943,16), to_signed(4597,16), to_signed(7916,16),  to_signed(-1761,16),to_signed(458,16),  to_signed(0,16)),
    5 => (to_signed(266,16),  to_signed(-1401,16),to_signed(6300,16), to_signed(6300,16),  to_signed(-1401,16),to_signed(266,16),  to_signed(0,16)),
    6 => (to_signed(458,16),  to_signed(-1761,16),to_signed(7916,16), to_signed(4597,16),  to_signed(-943,16), to_signed(74,16),   to_signed(0,16)),
    7 => (to_signed(620,16),  to_signed(-1948,16),to_signed(9327,16), to_signed(2930,16),  to_signed(-460,16), to_signed(-89,16),  to_signed(0,16)),
    8 => (to_signed(714,16),  to_signed(-1895,16),to_signed(10423,16),to_signed(1407,16),  to_signed(-14,16),  to_signed(-204,16), to_signed(0,16)),
    9 => (to_signed(712,16),  to_signed(-1548,16),to_signed(11118,16),to_signed(117,16),   to_signed(347,16),  to_signed(-262,16), to_signed(0,16))
	);
	
	type sym_vec is array(0 to 6) of signed32;
	
	signal SYMS_RE : sym_vec := (others => (others => '0'));
	signal SYMS_IM : sym_vec := (others => (others => '0'));
	
	
	signal PHASE_CNT : integer range 0 to 9 := 0;
	
	
	begin
	
process(CLK)
  variable ACC_RE			: signed64;
  variable ACC_IM			: signed64;
  variable SYMS_RE_V		: sym_vec;   -- variable shadow of SH
  variable SYMS_IM_V		: sym_vec;   -- variable shadow of SH
begin
	if rising_edge(CLK) then
		if (RST = '1') then
			PHASE_CNT <= 0;
			VALID_OUT <= '0';
			SYMS_RE <= (others => (others => '0'));
			SYMS_IM <= (others => (others => '0'));
			OUTPUT_RE <= (others => '0');
			OUTPUT_IM <= (others => '0');

		else
			if VALID_IN = '1' or PHASE_CNT > 0 then
				VALID_OUT <= '1';
				SYMS_RE_V := SYMS_RE;
				SYMS_IM_V := SYMS_IM;
			
				if PHASE_CNT = 0 then
					for k in 6 downto 1 loop
						SYMS_RE_V(k) := SYMS_RE_V(k-1);
						SYMS_IM_V(k) := SYMS_IM_V(k-1);
					end loop;

					SYMS_RE_V(0) := signed(INPUT_RE);
					SYMS_IM_V(0) := signed(INPUT_IM);
				end if;
			
				ACC_RE := (others => '0');
				ACC_IM := (others => '0');
				for k in 0 to 6 loop
					ACC_RE := ACC_RE + (C(PHASE_CNT)(k) * SYMS_RE_V(k));
					ACC_IM := ACC_IM + (C(PHASE_CNT)(k) * SYMS_IM_V(k));
				end loop;

				OUTPUT_RE <= std_logic_vector(resize(shift_right(ACC_RE,SCALE),32));
				OUTPUT_IM <= std_logic_vector(resize(shift_right(ACC_IM,SCALE),32));

				SYMS_RE <= SYMS_RE_V;
				SYMS_IM <= SYMS_IM_V;
				
				PHASE_CNT <= (PHASE_CNT + 1) mod 10;
				
				if (PHASE_CNT = 2) then
					TRIG <= '1';
				else
					TRIG <= '0';
				end if;
			else
				VALID_OUT <= '0';
			end if;
		end if;
	end if;
end process;
end RTL;