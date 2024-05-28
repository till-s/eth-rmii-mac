library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

package RMIIMacPkg is

   constant ETH_CRC_INIT_LE_C     : std_logic_vector(31 downto 0) := x"FFFFFFFF";
   constant ETH_CRC_POLY_LE_C     : std_logic_vector(31 downto 0) := x"EDB88320";
   constant ETH_CRC_CHECK_LE_C    : std_logic_vector(31 downto 0) := x"DEBB20e3";

   function crc32LE2Bit(
      constant c : in std_logic_vector(31 downto 0);
      constant x : in std_logic_vector(1 downto 0)
   ) return std_logic_vector;

   constant SLOT_BIT_TIME_C       : natural := 512;
   constant LD_SLOT_BIT_TIME_C    : natural := 9;
   constant IPG_BIT_TIME_C        : natural := 96;
   constant LD_MAX_BACKOFF_C      : natural := 10;
   constant LD_RMII_BITS_C        : natural := 1;
   constant RMII_BITS_C           : natural := 2;

end package RMIIMacPkg;

package body RMIIMacPkg is

   function crc32LE2Bit(
      constant c : in std_logic_vector(31 downto 0);
      constant x : in std_logic_vector(1 downto 0)
   )
   return std_logic_vector is
      variable v : std_logic_vector(31 downto 0);
      variable s : boolean;
   begin
      v          := (others => '0');
      v(x'range) := (x xor c(x'range));
      for i in 1 to 2 loop
         s := (v(0) = '1');
         v := '0' & v(v'left downto 1);
         if ( s ) then
            v := v xor ETH_CRC_POLY_LE_C;
         end if;
      end loop;
      v := v xor ("00" & c(c'left downto 2));
      return v;
   end function crc32LE2Bit;

end package body RMIIMacPkg;
