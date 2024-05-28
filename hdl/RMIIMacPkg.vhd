library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

package RMIIMacPkg is

   constant ETH_CRC_INIT_LE_C     : std_logic_vector(31 downto 0) := x"FFFFFFFF";
   constant ETH_CRC_POLY_LE_C     : std_logic_vector(31 downto 0) := x"EDB88320";
   constant ETH_CRC_CHECK_LE_C    : std_logic_vector(31 downto 0) := x"DEBB20e3";

   function crcLETbl(
      constant c : in std_logic_vector;
      constant x : in std_logic_vector;
      constant p : in std_logic_vector
   ) return std_logic_vector;

   function crc32LE2Bit(
      constant c : in std_logic_vector(31 downto 0);
      constant x : in std_logic_vector(1 downto 0)
   ) return std_logic_vector;

   subtype EthMulticastHashType is unsigned(5 downto 0);

   constant ETH_MULTICAST_HASH_INIT_C : EthMulticastHashType := (others => '0');
   constant ETH_MULTICAST_HASH_POLY_C : EthMulticastHashType := "110011";

   function ethMultiCastHash(
      constant h : in EthMultiCastHashType;
      constant x : in std_logic_vector(1 downto 0)
   ) return EthMulticastHashType;

   constant SLOT_BIT_TIME_C       : natural := 512;
   constant LD_SLOT_BIT_TIME_C    : natural := 9;
   constant IPG_BIT_TIME_C        : natural := 96;
   constant LD_MAX_BACKOFF_C      : natural := 10;
   constant LD_RMII_BITS_C        : natural := 1;
   constant RMII_BITS_C           : natural := 2;

   subtype EthMacAddrType is std_logic_vector(47 downto 0);

   subtype EthMulticastFilterType is std_logic_vector( 2**EthMulticastHashType'length - 1 downto 0);

   constant ETH_MULTICAST_FILTER_INIT_C : EthMulticastFilterType := ( others => '0' );

end package RMIIMacPkg;

package body RMIIMacPkg is

   function crcLETbl(
      constant c : in std_logic_vector;
      constant x : in std_logic_vector;
      constant p : in std_logic_vector
   ) return std_logic_vector is
      variable v : std_logic_vector(c'range);
      variable s : boolean;
   begin
      v          := (others => '0');
      v(x'range) := (x xor c(x'range));
      for i in 1 to x'length loop
         s := (v(0) = '1');
         v := '0' & v(v'left downto 1);
         if ( s ) then
            v := v xor p;
         end if;
      end loop;
      v := v xor std_logic_vector( shift_right( unsigned( c ), x'length ) );
      return v;
   end function crcLETbl;
   
   function crc32LE2Bit(
      constant c : in std_logic_vector(31 downto 0);
      constant x : in std_logic_vector(1 downto 0)
   )
   return std_logic_vector is
   begin
      return crcLETbl(c, x, ETH_CRC_POLY_LE_C);
   end function crc32LE2Bit;

   function ethMultiCastHash(
      constant h : in EthMultiCastHashType;
      constant x : in std_logic_vector(1 downto 0)
   ) return EthMulticastHashType is
      variable v : std_logic_vector( EthMulticastHashType'range );
   begin
      v := crcLETbl( std_logic_vector( h ), x, std_logic_vector( ETH_MULTICAST_HASH_POLY_C ) );
      return EthMulticastHashType( v );
   end function ethMulticastHash;

end package body RMIIMacPkg;
