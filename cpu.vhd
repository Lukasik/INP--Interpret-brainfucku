-- cpu.vhd: Moje neprilis podarene reseni.
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
	CLK   : in std_logic;  -- hodinovy signal
	RESET : in std_logic;  -- asynchronni reset procesoru
	EN    : in std_logic;  -- povoleni cinnosti procesoru

	-- synchronni pamet ROM
	CODE_ADDR : out std_logic_vector(11 downto 0); -- adresa do pameti
	CODE_DATA : in std_logic_vector(7 downto 0);   -- CODE_DATA <- rom[CODE_ADDR] pokud CODE_EN='1'
	CODE_EN   : out std_logic;                     -- povoleni cinnosti

	-- synchronni pamet RAM
	DATA_ADDR  : out std_logic_vector(9 downto 0); -- adresa do pameti
	DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
	DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
	DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
	DATA_EN    : out std_logic;                    -- povoleni cinnosti

	-- vstupni port
	IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
	IN_VLD    : in std_logic;                      -- data platna
	IN_REQ    : out std_logic;                     -- pozadavek na vstup data

	-- vystupni port
	OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
	OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
	OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;



-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is
	type t_state is (ret, whileEndCondition, waitWhileEnd,waitExecuteRead, whileCntWait, fetch, fetchWait, handle, readDataInc, writeData, readDataDec, writeDataInc, readDataPrint, inDataRead, waitExecute, whileCondition, writeDataDec, whileConditionWait, justWait, whileEnd, whileConditionEndWait);
	signal presentState, nextState: t_state;
	signal POINTER: std_logic_vector(9 downto 0) := (others => '0');
	signal PC: std_logic_vector(11 downto 0) := (others => '0');
	signal STACK: std_logic_vector(191 downto 0) := (others => '0');
	signal IGNORE_INSTRUCTIONS: std_logic_vector(7 downto 0) := (others => '0');
	signal PC_INC, PC_LOAD, POINTER_INC, POINTER_DEC, DATA_INC, DATA_DEC, STACK_PUSH, STACK_POP, DATA_PRINT, DATA_LOAD: std_logic :=  '0';
begin

	nsl: process (CLK, RESET, nextState, EN)
	begin
		if RESET = '1' then
			presentState <= fetch;
		elsif rising_edge(CLK) and EN = '1' then
			presentState <= nextState;
		end if;
	end process;

	fsm: process (CLK, presentState,OUT_BUSY, IN_VLD, CODE_DATA, DATA_RDATA, IGNORE_INSTRUCTIONS)
	begin
			CODE_EN <= '0';
			DATA_EN <= '0';
			PC_INC <= '0';
			PC_LOAD <= '0';
			POINTER_DEC <= '0';
			POINTER_INC <= '0';
			DATA_INC <= '0';
			DATA_DEC <= '0';
			DATA_LOAD <= '0';
			DATA_PRINT <= '0';
			STACK_POP <= '0';
			STACK_PUSH <= '0';
			DATA_RDWR <= '1';
			IN_REQ <= '0';
			nextState <= ret;
			IGNORE_INSTRUCTIONS <= IGNORE_INSTRUCTIONS;

			case presentState is
				-- načtení instrukce
				when fetch =>
					CODE_EN <= '1';
					nextState <= fetchWait;

				-- čekám až se načte instrukce
				when fetchWait => nextState <= handle;

				-- čekám na data které budu inkrementovat
				when readDataInc =>
					DATA_RDWR <= '1';
					DATA_EN <= '1';
					DATA_INC <= '1';
					nextState <= writeDataInc;

				-- čekám na data které budu dekrementovat
				when readDataDec =>
					DATA_RDWR <= '1';
					DATA_EN <= '1';
					DATA_DEC <= '1';
					nextState <= writeDataDec;

				-- zapíšu inkrementovaná data
				when writeDataInc =>
					DATA_RDWR <= '0';
					DATA_INC <= '1';
					DATA_EN <= '1';
					nextState <= waitExecute;

				-- zapíšu dekrementovaná data
				when writeDataDec =>
					DATA_RDWR <= '0';
					DATA_DEC <= '1';
					DATA_EN <= '1';
					nextState <= waitExecute;

				-- čekám na data které budu tisknout
				when readDataPrint =>
					DATA_RDWR <= '1';
					DATA_EN <= '1';
					nextState <= readDataPrint;

					if OUT_BUSY = '0' then
						nextState <= waitExecute;
						DATA_PRINT <= '1';
					end if;

				-- čekám až dostanu správná data z klávesnice
				when inDataRead =>
					nextState <= inDataRead;

					if IN_VLD = '1' then
						DATA_LOAD <= '1';
						IN_REQ <= '0';
						nextState <= waitExecuteRead;
					end if;

				when waitExecuteRead =>
					DATA_EN <= '1';
					DATA_RDWR <= '0';
					nextState <= waitExecute;


				-- čekám na dokončení instrukce a připravuji si čtení další
				when waitExecute =>
					PC_INC <= '1';
					nextState <= fetch;

				when whileConditionWait => nextState <= whileCondition;
				when whileConditionEndWait => nextState <= whileEndCondition;

				when whileEndCondition =>
					if DATA_RDATA = "00000000" then
						STACK_POP <= '1';
						nextState <= waitExecute;
					else
						PC_LOAD <= '1';
						nextState <= justWait;
					end if;

				when justWait =>
					STACK_POP <= '1';
					nextState <=fetch;

				when whileCondition =>
					if DATA_RDATA = "00000000" then
						IGNORE_INSTRUCTIONS <= "00000001";
					else
						STACK_PUSH <= '1';
					end if;

					nextState <= waitExecute;

				-- return, nic se neděje
				when ret => null;

				-- rozpoznání instrukce
				when handle =>
					if IGNORE_INSTRUCTIONS /= "00000000"
					then
						if CODE_DATA = X"5B" then
							IGNORE_INSTRUCTIONS <= IGNORE_INSTRUCTIONS + 1;
						elsif CODE_DATA = X"5D" then
							IGNORE_INSTRUCTIONS <= IGNORE_INSTRUCTIONS - 1;
						end if;

						nextState <= waitExecute;
					else
						case CODE_DATA is

							--inkrementace ukazatele
							when X"3E" =>
								POINTER_INC <= '1';
								nextState <= waitExecute;

							--dekrementace ukazatele
							when X"3C" =>
								POINTER_DEC <= '1';
								nextState <= waitExecute;

							--inkrementace hodnoty
							when X"2B" =>
								DATA_RDWR <= '1';
								DATA_EN <= '1';
								nextState <= readDataInc;

							--dekrementace hodnoty
							when X"2D" =>
								DATA_RDWR <= '1';
								DATA_EN <= '1';
								nextState <= readDataDec;

							--tisk znaku
							when X"2E" =>
								DATA_RDWR <= '1';
								DATA_EN <= '1';
								nextState <= readDataPrint;

							-- čtení znaku z klávesnice
							when X"2C" =>
								IN_REQ <= '1';
								nextState <= inDataRead;

							-- začátek while
							when X"5B" =>
								DATA_RDWR <= '1';
								DATA_EN <= '1';

								nextState <= whileConditionWait;

							-- konec while
							when X"5D" =>
								DATA_RDWR <= '1';
								DATA_EN <= '1';

								nextState <= whileConditionEndWait;

							--return
							when X"00" =>
								nextState <= ret;

							--neznámý kód, přeskočit
							when others =>
								nextState <= waitExecute;
						end case;
					end if;
				when others => null;
			end case;
	end process;

	pPC: process (RESET, CLK, PC_INC,PC_LOAD, STACK, PC)
	begin
		if RESET = '1' then
			PC <= (others => '0');
			CODE_ADDR <= (others => '0');
		elsif rising_edge(CLK) then
			if PC_INC = '1' then
				PC <= PC + 1;
				CODE_ADDR <= PC + 1;
			elsif PC_LOAD = '1' then
				PC <= STACK(191 downto 180);
				CODE_ADDR <= STACK(191 downto 180);
			end if;
		end if;
	end process;

	pSTACK: process (CLK, RESET, STACK, PC, STACK_PUSH, STACK_POP)
	begin
		if RESET = '1' then
			STACK <= (others => '0');
		elsif rising_edge(CLK) then
			if STACK_PUSH = '1' then
				STACK <= PC & STACK(191 downto 12);
			elsif STACK_POP = '1' then
				STACK <= STACK(179 downto 0) & "000000000000";
			end if;
		end if;
	end process;

	pPOINTER: process(CLK, RESET, POINTER, POINTER_INC, POINTER_DEC)
	begin
		if RESET = '1' then
			POINTER <= (others => '0');
			DATA_ADDR <= (others => '0');
		elsif rising_edge(CLK) then
			if POINTER_INC = '1' then
				POINTER <= POINTER + 1;
				DATA_ADDR <= POINTER + 1;
			elsif POINTER_DEC = '1' then
				POINTER <= POINTER - 1;
				DATA_ADDR <= POINTER - 1;
			end if;
		end if;
	end process;

	pDATA: process(CLK, DATA_RDATA, IN_DATA, DATA_INC, DATA_DEC, DATA_PRINT, DATA_LOAD)
	begin
		if rising_edge(CLK) then
			OUT_WE <= '0';

			if DATA_INC = '1' then
				DATA_WDATA <= DATA_RDATA + 1;
			elsif DATA_DEC = '1' then
				DATA_WDATA <= DATA_RDATA - 1;
			elsif DATA_PRINT = '1' then
				OUT_DATA <= DATA_RDATA;
				OUT_WE <= '1';
			elsif DATA_LOAD = '1' then
				DATA_WDATA <= IN_DATA;
			end if;
		end if;
	end process;

end behavioral;
