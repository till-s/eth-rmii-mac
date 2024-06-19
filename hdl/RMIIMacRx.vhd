-- Copyright Till Straumann, 2024. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.RMIIMacPkg.all;

entity RMIIMacRx is
   port (
      clk        : in  std_logic;
      rst        : in  std_logic := '0';

      -- FIFO/stream interface
      rxDat      : out std_logic_vector(7 downto 0);
      rxVld      : out std_logic;
      rxLst      : out std_logic;
      rxRdy      : in  std_logic;
      rxAbt      : out std_logic;

      -- RMII interface
      rmiiDat    : in  std_logic_vector(1 downto 0);
      rmiiDV     : in  std_logic;

      -- addressing
      -- address **in LE format**, i.e., first octet on wire is [7:0]
      macAddr    : in  EthMacAddrType;
      promisc    : in  std_logic := '1';
      allmulti   : in  std_logic := '1';
      mcFilter   : in  EthMulticastFilterType := ETH_MULTICAST_FILTER_INIT_C;

      -- misc
      speed10    : in  std_logic;
      stripCRC   : in  std_logic := '0'
   );
end entity RMIIMacRx;

architecture rtl of RMIIMacRx is

   type StateType is (IDLE, PREAMBLE, ADDR, RECEIVE, TAIL, DROP);

   -- delay data so that we can strip the CRC
   -- simply hold off for the length of the mac address
   -- so we can also filter before sending data out... 
   subtype DelayType is EthMacAddrType;

   type RegType is record
      state     : StateType;
      presc     : signed(4 downto 0);
      phase     : unsigned(1 downto 0);
      cnt       : signed(5 downto 0);
      crc       : std_logic_vector(31 downto 0);
      mcHash    : EthMulticastHashType;
      isBcst    : boolean;
      isUcst    : boolean;
      stripCRC  : std_logic;
      delayReg  : DelayType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state     => DROP,
      presc     => (others => '1'),
      phase     => (others => '0'),
      cnt       => (others => '0'),
      crc       => ETH_CRC_INIT_LE_C,
      mcHash    => ETH_MULTICAST_HASH_INIT_C,
      isBcst    => true,
      isUcst    => true,
      stripCRC  => '0',
      delayReg  => (others => '0')
   );

   signal r     : RegType := REG_INIT_C;
   signal rin   : RegType;
begin

   P_COMB : process (r, rxRdy, rmiiDat, rmiiDV, macAddr, promisc, allmulti, mcFilter, speed10, stripCRC ) is
      variable v          : RegType;
   begin

      v       := r;

      rxAbt   <= '0';
      rxVld   <= '0';
      rxLst   <= '0';

      if ( r.presc < 0 ) then

         v.crc      := crc32LE2Bit( r.crc, rmiiDat );
         v.mcHash   := ethMulticastHash( r.mcHash, rmiiDat );
         v.delayReg := rmiiDat & r.delayReg( r.delayReg'left downto 2 );
         v.cnt      := r.cnt - 1;

         if ( speed10 = '1' ) then
            v.presc := to_signed( 10 - 2, v.presc'length );
         end if;

         rxAbt <= not rmiiDV or not rxRdy;

         case ( r.state ) is
            when DROP =>
               rxAbt <= '0';
               if ( rmiiDV = '0' ) then
                  v.state := IDLE;
               end if;

            when IDLE =>
               -- lift abort condition
               rxAbt <= '0';

               v.stripCRC := stripCRC;
               if ( rmiiDV = '1' ) then
                  if ( rxRdy = '1' ) then
                     v.state    := PREAMBLE;
                  else
                     v.state    := DROP;
                  end if;
               end if;

            when PREAMBLE =>
               v.delayReg := macAddr;
               v.cnt      := to_signed( macAddr'length/RMII_BITS_C - 1, r.cnt'length );
               if ( rmiiDat = "11" ) then
                  -- SOF
                  v.crc    := ETH_CRC_INIT_LE_C;
                  v.mcHash := ETH_MULTICAST_HASH_INIT_C;
                  v.state  := ADDR;
                  v.isBcst := true;
                  v.isUcst := true;
               end if;

            when ADDR =>
               v.isBcst := r.isBcst and (rmiiDat = "11");
               v.isUcst := r.isUcst and (rmiiDat = r.delayReg(1 downto 0) );
               if ( r.cnt < 0 ) then
                  if (   (promisc = '1')
                       or r.isBcst
                       or r.isUcst
                       -- delayReg holds the multicast/broadcast bit
                       or (not r.isBcst and ( (r.delayReg(0) and (allmulti or mcFilter( to_integer( r.mcHash ))) ) = '1' ) )
                     ) then
                     rxVld   <= '1';
                     v.state := RECEIVE;
                     v.cnt   := to_signed( 8/RMII_BITS_C - 2, r.cnt'length );
                  else
                     -- no need to raise rxAbt; nothing has made it out yet...
                     v.state := DROP;
                  end if;
               end if;

            when RECEIVE=>
               if ( r.cnt < 0 ) then
                  v.cnt := to_signed( 8/RMII_BITS_C - 2, r.cnt'length );
                  rxVld <= '1';
                  -- complete byte has been shifted in; check if
                  -- DV has been deasserted:
                  if ( rmiiDV = '0' ) then
                     if ( r.crc = ETH_CRC_CHECK_LE_C ) then
                        -- OK
                        rxAbt   <= '0';
                        v.state := TAIL;
                        -- least significant byte is being sent right now;
                        -- 5 remain in the shift reg.
                        if ( r.stripCRC = '1' ) then
                           v.cnt := to_signed( (r.delayReg'length - 8 - r.crc'length) / RMII_BITS_C - 2, r.cnt'length );
                        else
                           v.cnt := to_signed( (r.delayReg'length - 8) / RMII_BITS_C - 2, r.cnt'length );
                        end if;
                     else
                        v.state := DROP;
                        -- rxAbt has been asserted above
                     end if;
                  end if;
               end if;

            when TAIL =>
               if ( r.cnt(1 downto 0) = "11" ) then
                  rxVld <= '1';
               end if;
               rxAbt <= '0';
               if ( r.cnt < 0 ) then
                  rxLst   <= '1';
                  v.state :=  DROP; -- in cast rmiiDV is already asserted
               end if;
         end case;

      end if; -- r.presc < 0

      rin     <= v;
   end process P_COMB;

   P_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   rxDat <= r.delayReg(7 downto 0);

end architecture rtl;

