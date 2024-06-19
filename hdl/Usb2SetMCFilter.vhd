-- Copyright Till Straumann, 2024. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2UtilPkg.all;
use     work.Usb2Pkg.all;
use     work.Usb2DescPkg.all;
use     work.RMIIMacPkg.all;

entity Usb2SetMCFilter is
   generic (
      DESCRIPTORS_G    : Usb2ByteArray;
      SIMULATE_G       : boolean := false
   );
   port (
      clk              : in  std_logic;
      rst              : in  std_logic := '0';

      mcFilterStrmDat  : in  Usb2ByteType;
      mcFilterStrmVld  : in  std_logic;
      mcFilterStrmDon  : in  std_logic;

      mcFilter         : out EthMulticastFilterType := ETH_MULTICAST_FILTER_ALL_C;
      mcFilterUpd      : out std_logic              := '0'
   );
end entity Usb2SetMCFilter;

architecture rtl of Usb2SetMCFilter is

   type StateType is (IDLE, RUN);

   subtype McCntType is signed(4 downto 0);

   function toMcCnt(constant x : integer) return McCntType is
   begin
      return to_signed( x - 2, McCntType'length );
   end function toMcCnt;

   type RegType   is record
      state       : StateType;
      mcCnt      : McCntType;
      mcFilter   : EthMulticastFilterType;
      mcUpd      : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state       => IDLE,
      mcCnt       => toMcCnt(6),
      mcFilter    => ETH_MULTICAST_FILTER_INIT_C,
      mcUpd       => '0'
   );

begin

   G_RTL : if ( SIMULATE_G or usb2GetNumMCFilters( DESCRIPTORS_G, USB2_IFC_SUBCLASS_CDC_NCM_C ) > 0 ) generate
      signal r                : RegType := REG_INIT_C;
      signal rin              : RegType;

      signal mcHash           : EthMulticastHashType := ETH_MULTICAST_HASH_INIT_C;
      signal mcHashIn         : EthMulticastHashType;
      signal mcHashCen        : std_logic;

   begin

      P_HASH : process ( clk ) is
      begin
         if ( rising_edge( clk ) ) then
            if ( rst = '1' ) then
               mcHash <= ETH_MULTICAST_HASH_INIT_C;
            elsif ( mcHashCen = '1' ) then
               mcHash <= ethMulticastHash( mcHashIn, mcFilterStrmDat );
            end if;
         end if;
      end process P_HASH;

      P_COMB : process ( r, mcFilterStrmDat, mcFilterStrmVld, mcFilterStrmDon, mcHash ) is
         variable v : RegType;
      begin
         v       := r;
         v.mcUpd := (mcFilterStrmVld and mcFilterStrmDon);

         mcHashCen <= '0';

         if ( ( r.state = IDLE ) or ( r.mcCnt < 0 ) ) then
            mcHashIn  <= ETH_MULTICAST_HASH_INIT_C;
         else
            mcHashIn  <= mcHash;
         end if;

         case ( r.state ) is
            when IDLE =>
               v.mcCnt := toMcCnt( 6 );
               if ( mcFilterStrmVld = '1' ) then
                  v.mcFilter := ETH_MULTICAST_FILTER_INIT_C;
                  if ( mcFilterStrmDon /= '1' ) then
                     mcHashCen <= '1';
                     v.state   := RUN;
                  end if;
               end if;

            when RUN =>
               if ( mcFilterStrmVld = '1' ) then
                  if ( mcFilterStrmDon = '1' ) then
                     v.state := IDLE;
                  else
                     mcHashCen <= '1';
                     -- if the count is already negative
                     -- then this is remedied below
                     v.mcCnt   := r.mcCnt - 1;
                  end if;
               end if;
         end case;

         -- do this regardless of state etc., mops up during the 'don'
         -- cycle. Must only advance while VLD because the mcHashIn
         -- mux looks at mcCnt < 0.
         if ( ( r.mcCnt < 0 ) and ( mcFilterStrmVld = '1' ) ) then
            v.mcFilter( to_integer( mcHash ) ) := '1';
            v.mcCnt                            := toMcCnt(6);
         end if;

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

      mcFilter    <= r.mcFilter;
      mcFilterUpd <= r.mcUpd;

   end generate G_RTL;

end architecture rtl;
