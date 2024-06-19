-- Copyright Till Straumann, 2024. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.RMIIMacPkg.all;

entity RMIIMacRxTb is
end entity RMIIMacRxTb;

architecture sim of RMIIMacRxTb is
   signal clk        : std_logic := '0';
   signal rst        : std_logic := '0';
   signal rxDat      : std_logic_vector(7 downto 0) := (others => '0');
   signal rxVld      : std_logic := '0';
   signal rxLst      : std_logic := '0';
   signal rxRdy      : std_logic := '0';
   signal rxAbt      : std_logic;

   signal rmiiDat    : std_logic_vector(7 downto 0) := (others => '0');
   signal rmiiDV     : std_logic := '0';

   signal speed10    : std_logic := '0';
   signal stripCRC   : std_logic := '0';

   signal running    : boolean := true;

   signal nbits      : natural   := 0;
   signal shfReg     : std_logic_vector(7 downto 0);
   signal nxtShfReg  : std_logic_vector(7 downto 0);
   signal shfRegVld  : std_logic := '0';

   signal active     : std_logic := '0';

   signal mcFilter   : EthMulticastFilterType := ETH_MULTICAST_FILTER_INIT_C;

   subtype Slv9 is std_logic_vector(8 downto 0);
   type Slv9Array is array (natural range <>) of Slv9;
   subtype Slv10 is std_logic_vector(9 downto 0);
   type Slv10Array is array (natural range <>) of Slv10;
   subtype Slv11 is std_logic_vector(10 downto 0);
   type Slv11Array is array (natural range <>) of Slv11;

   constant EXP_NUM_PKTS_C : natural := 6 - 2; -- 2 dropped/filtered

   -- in LE byte order!
   constant MAC_ADDR_C : EthMacAddrType := x"efbeadde0040";

   constant txVec    : Slv11Array := (
      -- broadcast packet; good checksum
      "000" & x"d5", -- mini-preamble
      "000" & x"ff",
      "000" & x"ff",
      "000" & x"ff",
      "000" & x"ff",
      "000" & x"ff",
      "000" & x"ff",
      "000" & x"01",
      "000" & x"02",
      "000" & x"03",
      "000" & x"04",
      "000" & x"6e",
      "000" & x"b7",
      "000" & x"27",
      "001" & x"46",

       -- broadcast; bad checksum
      "000" & x"d5", -- mini-preamble
      "000" & x"ff",
      "000" & x"ff",
      "000" & x"ff",
      "000" & x"ff",
      "000" & x"ff",
      "000" & x"ff",
      "000" & x"01",
      "000" & x"02",
      "000" & x"03",
      "000" & x"04",
      "000" & x"6e",
      "000" & x"b6",
      "000" & x"27",
      "001" & x"46",

      -- unicast packet; good checksum; stripped
      "010" & x"d5", -- mini-preamble
      "010" & x"40",
      "010" & x"00",
      "010" & x"de",
      "010" & x"ad",
      "010" & x"be",
      "010" & x"ef",
      "010" & x"01",
      "010" & x"02",
      "010" & x"03",
      "010" & x"04",
      "010" & x"8c",
      "010" & x"bf",
      "010" & x"e7",
      "011" & x"55",

      -- non-matching unicast packet; good checksum; stripped
      "010" & x"d5", -- mini-preamble
      "010" & x"40",
      "010" & x"00",
      "010" & x"de",
      "010" & x"ad",
      "010" & x"be",
      "010" & x"ee",
      "010" & x"01",
      "010" & x"02",
      "010" & x"03",
      "010" & x"04",
      "010" & x"3c",
      "010" & x"96",
      "010" & x"87",
      "011" & x"68",

       -- mc address
      "010" & x"d5", -- mini-preamble
      "010" & x"01",
      "010" & x"1b",
      "010" & x"19",
      "010" & x"00",
      "010" & x"00",
      "010" & x"00",
      "010" & x"01",
      "010" & x"02",
      "010" & x"03",
      "010" & x"04",
      "010" & x"35",
      "010" & x"d1",
      "010" & x"51",
      "011" & x"d6",

       -- mc address address generates hash 0x09; filter
       -- selected by bit in txVec(tidx)
      "010" & x"d5", -- mini-preamble
      "110" & x"01",
      "110" & x"1b",
      "110" & x"19",
      "110" & x"00",
      "110" & x"00",
      "110" & x"00",
      "110" & x"01",
      "110" & x"02",
      "110" & x"03",
      "110" & x"04",
      "110" & x"35",
      "110" & x"d1",
      "110" & x"51",
      "111" & x"d6"
    );

   constant rxVec    : Slv10Array := (
      "00" & x"ff",
      "00" & x"ff",
      "00" & x"ff",
      "00" & x"ff",
      "00" & x"ff",
      "00" & x"ff",
      "00" & x"01",
      "00" & x"02",
      "00" & x"03",
      "00" & x"04",
      "00" & x"6e",
      "00" & x"b7",
      "00" & x"27",
      "01" & x"46",

      "00" & x"ff",
      "00" & x"ff",
      "00" & x"ff",
      "00" & x"ff",
      "00" & x"ff",
      "00" & x"ff",
      "00" & x"01",
      "00" & x"02",
      "10" & x"03",

      "00" & x"40",
      "00" & x"00",
      "00" & x"de",
      "00" & x"ad",
      "00" & x"be",
      "00" & x"ef",
      "00" & x"01",
      "00" & x"02",
      "00" & x"03",
      "01" & x"04",

-- we don't see filtered packets      "10" & x"00",

-- we don't see filtered packets      "10" & x"00",

      "00" & x"01",
      "00" & x"1b",
      "00" & x"19",
      "00" & x"00",
      "00" & x"00",
      "00" & x"00",
      "00" & x"01",
      "00" & x"02",
      "00" & x"03",
      "01" & x"04"
   );


   signal ridx       : natural := 0;
   signal tidx       : natural := 0;
   constant MIN_IPG_C: natural := 96/2;
   signal ipg        : integer := MIN_IPG_C;
   signal numPkts    : natural := 0;

begin

   P_CLK : process is
   begin
      if ( not running ) then 
         assert numPkts = EXP_NUM_PKTS_C report "unexpected number of packets" severity failure;
         report "TEST PASSED";
         wait;
      end if;
      wait for 10 ns;
      clk <= not clk;
   end process P_CLK;

   P_OBS : process ( clk ) is
   begin
      if ( rising_edge ( clk ) ) then
         rxRdy <= '1';
         if ( (rxAbt or (rxRdy and rxVld)) = '1' ) then
            if ( rxAbt = '1' ) then
               assert ( rxVec(ridx)(9) = '1' ) report "unexpected abort" severity failure;
            else
               assert( rxVec(ridx)(7 downto 0) = rxDat ) report "data mismatch" severity failure;
               assert( rxVec(ridx)(9) = '0' ) report "missed abort" severity failure;
               assert RxLst = rxVec(ridx)(8) report "LST mismatch" severity failure;
            end if;

            if ( (rxAbt or rxLst) = '1' ) then
               numPkts <= numPkts + 1;
            end if;
            if ( ridx = rxVec'high ) then
               running <= false;
            else
               ridx <= ridx + 1;
            end if;
         end if;
      end if;
   end process P_OBS;

   stripCRC  <= txVec(tidx)(9);
   mcFilter(9) <= txVec(tidx)(10);

   P_SND : process (clk) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rmiiDV = '0' ) then
            if ( ipg = 0 ) then
               rmiiDV  <= '1';
               rmiiDat <= txVec(tidx)(7 downto 0);
               nbits   <= 6;
            elsif (ipg > 0 ) then
               ipg <= ipg - 1;
            end if;
         else
            if ( nbits = 0 ) then
               nbits <= 6;
               if ( txVec(tidx)(8) = '1' ) then
                  rmiiDV <= '0';
               end if;
               if ( tidx < txVec'high ) then
                  rmiiDat <= txVec(tidx + 1)(7 downto 0);
                  tidx    <= tidx + 1;
                  ipg     <= MIN_IPG_C;
               else
                  ipg   <= -1;
               end if;
            else
               rmiiDat <= "00" & rmiiDat(rmiiDat'left downto 2);
               nbits   <= nbits - 2;
            end if;
         end if;
      end if;
   end process P_SND;

   U_DUT : entity work.RMIIMacRx
      port map (
         clk        => clk,
         rst        => rxAbt,

         rxDat      => rxDat,
         rxVld      => rxVld,
         rxLst      => rxLst,
         rxRdy      => rxRdy,
         rxAbt      => rxAbt,

         rmiiDat    => rmiiDat(1 downto 0),
         rmiiDV     => rmiiDV,

         macAddr    => MAC_ADDR_C,
         mcFilter   => mcFilter,

         promisc    => '0',
         speed10    => speed10,
         stripCRC   => stripCRC
      );

end architecture sim;
