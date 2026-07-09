library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Symbol_Shaper is
	generic(
	logQAM : integer := 4 -- Which QAM. Default 16QAM
	);
	port(
	CLK : in std_logic;
	RST : in std_logic;
	
	INPUT_RE : in std_logic_vector((logQAM/2)-1 downto 0);
	INPUT_IM : in std_logic_vector((logQAM/2)-1 downto 0);
	VALID_IN : in std_logic;
	
	OUTPUT_RE : out std_logic_vector(31 downto 0);
	OUTPUT_IM : out std_logic_vector(31 downto 0);
	VALID_OUT : out std_logic
	);

end entity;

architecture RTL of Symbol_Shaper is

	constant MQAM : integer := 2**logQAM;
	constant L : integer := 2**(logQAM/2);

	subtype Q2_22_t is signed(23 downto 0);
	
	type QAM is array (natural range <>) of Q2_22_t; -- Stored as Q2.22, so 1 signed bit, 1 integer bit and 22 fractional bits
	constant QAM16 : QAM(0 to 3) := (
	to_signed(-3979065, 24), to_signed(-1326355, 24), to_signed(1326355, 24), to_signed(3979065, 24));
	
	constant QAM64 : QAM(0 to 7) := (
	to_signed(-4530365, 24), to_signed(-3235975, 24), to_signed(-1941585, 24), to_signed(-647195, 24), 
	to_signed(647195, 24), to_signed(1941585, 24), to_signed(3235975, 24), to_signed(4530365, 24));

	constant QAM256 : QAM(0 to 15) := (
	to_signed(-4825325, 24), to_signed(-4181949, 24), to_signed(-3538572, 24), to_signed(-2895195, 24), 
	to_signed(-2251818, 24), to_signed(-1608442, 24), to_signed(-965065, 24), to_signed(-321688, 24), 
	to_signed(321688, 24), to_signed(965065, 24), to_signed(1608442, 24), to_signed(2251818, 24), 
	to_signed(2895195, 24), to_signed(3538572, 24), to_signed(4181949, 24), to_signed(4825325, 24));	
	constant QAM1024 : QAM(0 to 31) := (
	to_signed(-4978853, 24), to_signed(-4657637, 24), to_signed(-4336420, 24), to_signed(-4015204, 24), 
	to_signed(-3693988, 24), to_signed(-3372771, 24), to_signed(-3051555, 24), to_signed(-2730339, 24), 
	to_signed(-2409122, 24), to_signed(-2087906, 24), to_signed(-1766690, 24), to_signed(-1445473, 24), 
	to_signed(-1124257, 24), to_signed(-803041, 24), to_signed(-481824, 24), to_signed(-160608, 24), 
	to_signed(160608, 24), to_signed(481824, 24), to_signed(803041, 24), to_signed(1124257, 24), 
	to_signed(1445473, 24), to_signed(1766690, 24), to_signed(2087906, 24), to_signed(2409122, 24), 
	to_signed(2730339, 24), to_signed(3051555, 24), to_signed(3372771, 24), to_signed(3693988, 24), 
	to_signed(4015204, 24), to_signed(4336420, 24), to_signed(4657637, 24), to_signed(4978853, 24));
	
	constant QAM4096 : QAM(0 to 63) := (
	to_signed(-5057304, 24), to_signed(-4896754, 24), to_signed(-4736205, 24), to_signed(-4575656, 24), 
	to_signed(-4415106, 24), to_signed(-4254557, 24), to_signed(-4094008, 24), to_signed(-3933458, 24), 
	to_signed(-3772909, 24), to_signed(-3612360, 24), to_signed(-3451810, 24), to_signed(-3291261, 24), 
	to_signed(-3130712, 24), to_signed(-2970162, 24), to_signed(-2809613, 24), to_signed(-2649064, 24), 
	to_signed(-2488514, 24), to_signed(-2327965, 24), to_signed(-2167416, 24), to_signed(-2006867, 24), 
	to_signed(-1846317, 24), to_signed(-1685768, 24), to_signed(-1525219, 24), to_signed(-1364669, 24), 
	to_signed(-1204120, 24), to_signed(-1043571, 24), to_signed(-883021, 24), to_signed(-722472, 24), 
	to_signed(-561923, 24), to_signed(-401373, 24), to_signed(-240824, 24), to_signed(-80275, 24), 
	to_signed(80275, 24), to_signed(240824, 24), to_signed(401373, 24), to_signed(561923, 24), 
	to_signed(722472, 24), to_signed(883021, 24), to_signed(1043571, 24), to_signed(1204120, 24), 
	to_signed(1364669, 24), to_signed(1525219, 24), to_signed(1685768, 24), to_signed(1846317, 24), 
	to_signed(2006867, 24), to_signed(2167416, 24), to_signed(2327965, 24), to_signed(2488514, 24), 
	to_signed(2649064, 24), to_signed(2809613, 24), to_signed(2970162, 24), to_signed(3130712, 24), 
	to_signed(3291261, 24), to_signed(3451810, 24), to_signed(3612360, 24), to_signed(3772909, 24), 
	to_signed(3933458, 24), to_signed(4094008, 24), to_signed(4254557, 24), to_signed(4415106, 24), 
	to_signed(4575656, 24), to_signed(4736205, 24), to_signed(4896754, 24), to_signed(5057304, 24));
	
	
	function gray_to_binary(g : std_logic_vector) return unsigned is
		 variable b : unsigned(g'range);
	begin
		 b(g'high) := g(g'high);
		 for i in g'high-1 downto g'low loop
			  b(i) := b(i+1) xor g(i);
		 end loop;
		 return b;
	end function;

begin

	process(CLK)
		variable RE : integer range 0 to L-1 := 0;
		variable IM : integer range 0 to L-1 := 0;
	begin
		if rising_edge(CLK) then
			if (RST = '1') then
				OUTPUT_RE <= (others => '0');
				OUTPUT_IM <= (others => '0');
				VALID_OUT <= '0';
			else
				if (VALID_IN = '1') then
					RE := to_integer(gray_to_binary(INPUT_RE));
					IM := to_integer(gray_to_binary(INPUT_IM));
					case MQAM is
						when 16 =>
							OUTPUT_RE <= std_logic_vector(resize(QAM16(RE),32));
							OUTPUT_IM <= std_logic_vector(resize(QAM16(IM),32));
							VALID_OUT <= '1';
						when 64 => 
							OUTPUT_RE <= std_logic_vector(resize(QAM64(RE),32));
							OUTPUT_IM <= std_logic_vector(resize(QAM64(IM),32));
							VALID_OUT <= '1';
						when 256 => 
							OUTPUT_RE <= std_logic_vector(resize(QAM256(RE),32));
							OUTPUT_IM <= std_logic_vector(resize(QAM256(IM),32));
							VALID_OUT <= '1';
						when 1024 => 
							OUTPUT_RE <= std_logic_vector(resize(QAM1024(RE),32));
							OUTPUT_IM <= std_logic_vector(resize(QAM1024(IM),32));
							VALID_OUT <= '1';
						when 4096 => 
							OUTPUT_RE <= std_logic_vector(resize(QAM4096(RE),32));
							OUTPUT_IM <= std_logic_vector(resize(QAM4096(IM),32));
							VALID_OUT <= '1';
						when others => -- Something broke, output zeros
							OUTPUT_RE <= (others => '0');
							OUTPUT_IM <= (others => '0');
							VALID_OUT <= '0';
					end case;
				else
					OUTPUT_RE <= (others => '0');
					OUTPUT_IM <= (others => '0');
					VALID_OUT <= '0';
				end if;
			end if;
		end if;
	end process;
end RTL;