-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2UtilPkg.all;
use     work.Usb2Pkg.all;
use     work.Usb2EpGenericCtlPkg.all;
use     work.RMIIMacPkg.all;

entity Usb2Ep0MDIOCtlTb is
end entity Usb2Ep0MDIOCtlTb;

architecture sim of Usb2Ep0MDIOCtlTb is
   signal clk            : std_logic := '0';
   signal rst            : std_logic := '0';

   signal mdioClk        : std_logic;
   signal mdioDatOut     : std_logic;
   signal mdioDatInp     : std_logic;
   signal mdioDatHiZ     : std_logic;

   signal sreg           : std_logic_vector(31 downto 0) := (others => '1');
   signal nbits          : integer := -1;
   signal ncycles        : integer := 0;
   signal nreqs          : integer := 0;
   signal nwrite         : integer := 0;
   signal nstrm          : integer := 0;
   signal match          : boolean := true;

   signal tstReqVld      : std_logic_vector(0 to 3) := (others => '0');
   signal tstReqMsk      : std_logic_vector(0 to 3) := (others => '1');
   signal tstReqVldMskd  : std_logic_vector(0 to 3) := (others => '1');
   signal tstReqAck      : std_logic;
   signal tstReqErr      : std_logic;
   signal tstParamIb     : Usb2ByteArray(0 to 3);
   signal tstParamOb     : Usb2ByteArray(0 to 3);
   signal simReqParam    : Usb2CtlReqParamType := USB2_CTL_REQ_PARAM_INIT_C;
   signal status         : std_logic_vector(15 downto 0);

   signal regA           : std_logic_vector(15 downto 0) := x"ABCD";
   signal regB           : std_logic_vector(15 downto 0) := x"3210";

   signal rand           : natural := 0;

   type Slv11Array is array (natural range <>) of std_logic_vector(10 downto 0);

   constant tstVec       : Slv11Array := (
      "100" & x"02",
      "100" & x"03",
      "100" & x"04",
      "100" & x"05",
      "100" & x"06",
      "100" & x"07",
      "100" & x"a2",
      "100" & x"a3",
      "100" & x"a4",
      "100" & x"a5",
      "100" & x"a6",
      "101" & x"a7",
      "110" & x"00",

      "110" & x"00",

      "100" & x"02",
      "100" & x"03",
      "100" & x"04",
      "100" & x"05",
      "100" & x"06",
      "000" & x"00",
      "000" & x"00",
      "000" & x"00",
      "100" & x"07",
      "000" & x"00",
      "100" & x"a2",
      "100" & x"a3",
      "100" & x"a4",
      "100" & x"a5",
      "100" & x"a6",
      "101" & x"a7",
      "000" & x"00",
      "000" & x"00",
      "110" & x"00"
   );

   type Slv48Array is array (natural range <>) of EthMulticastFilterType;

   -- computed with python script
   constant cmpVec      : Slv48Array := (
     0 => (14 => '1', 42 => '1', others => '0'),
     1 => (                      others => '0'),
     2 => (14 => '1', 42 => '1', others => '0')
   );

   signal   tstVecIdx   : integer := 0;

   signal   mcFilter    : EthMulticastFilterType;
   signal   mcFilterUpd : std_logic;

begin

   process is
   begin
      if ( ncycles > 3 and nreqs > 20 and nwrite > 4 and nstrm > 2*cmpVec'length ) then
         report "Test PASSED";
         wait;
      else
         wait for 10 ns;
         clk <= not clk;
      end if;
   end process;

   process (clk) is
      variable cmp : std_logic_vector(15 downto 0);
      variable val : unsigned(15 downto 0) := unsigned( regA );
   begin
      if ( rising_edge( clk ) ) then
         if ( ncycles > 1 ) then
            assert status = x"dead" report "status mismatch" severity failure;
         end if;
         rand <= rand + 1;
         tstReqMsk <= (others => '1');
         if ( tstReqVld = "0000" ) then 
            if ( rand mod 13 = 0 ) then
               tstReqVld(1)        <= '1';
               simReqParam.value   <= x"01" & x"10"; -- PHY_ID - REGISTER
               simReqParam.reqType <= USB2_REQ_TYP_TYPE_VENDOR_C;
            elsif ( rand mod 17 = 0 ) then
               tstReqVld(1)        <= '1';
               simReqParam.value   <= x"01" & x"0A"; -- PHY_ID - REGISTER
               simReqParam.reqType <= USB2_REQ_TYP_TYPE_VENDOR_C;
            elsif ( rand mod 11 = 0 ) then
               tstReqVld(2)        <= '1';
               simReqParam.value   <= x"01" & x"0A"; -- PHY_ID - REGISTER
               simReqParam.reqType <= USB2_REQ_TYP_TYPE_VENDOR_C;
               val                 := val + x"0101";
               tstParamOb(1)       <= std_logic_vector( val(15 downto 8) );
               tstParamOb(0)       <= std_logic_vector( val( 7 downto 0) );
            elsif ( rand mod 7 = 0 ) then
               tstReqVld(3)        <= '1';
               -- stream
               tstParamOb(1)       <= x"00";
               simReqParam.reqType <= USB2_REQ_TYP_TYPE_CLASS_C;
               tstParamOb(USB2_EP_GENERIC_STRM_DAT_IDX_C) <= tstVec(tstVecIdx)(7 downto 0);
               tstParamOb(USB2_EP_GENERIC_STRM_LST_IDX_C)
                         (USB2_EP_GENERIC_STRM_LST_BIT_C) <= tstVec(tstVecIdx)(8);
               tstParamOb(USB2_EP_GENERIC_STRM_DON_IDX_C)
                         (USB2_EP_GENERIC_STRM_DON_BIT_C) <= tstVec(tstVecIdx)(9);
               tstReqMsk(3)                               <= tstVec(tstVecIdx)(10);
               if ( tstVecIdx = tstVec'high ) then
                  tstVecIdx <= 0;
               else
                  tstVecIdx <= tstVecIdx + 1; 
               end if;
            end if;
         elsif ( tstReqVld(3) = '1' ) then
            -- stream
            tstParamOb(USB2_EP_GENERIC_STRM_DAT_IDX_C) <= tstVec(tstVecIdx)(7 downto 0);
            tstParamOb(USB2_EP_GENERIC_STRM_LST_IDX_C)
                      (USB2_EP_GENERIC_STRM_LST_BIT_C) <= tstVec(tstVecIdx)(8);
            tstParamOb(USB2_EP_GENERIC_STRM_DON_IDX_C)
                      (USB2_EP_GENERIC_STRM_DON_BIT_C) <= tstVec(tstVecIdx)(9);
            tstReqMsk(3)                               <= tstVec(tstVecIdx)(10);
            if ( usb2EpGenericStrmDon( tstParamOb ) = '1' ) then
               tstReqVld(3) <= '0';
            else
               if ( tstVecIdx = tstVec'high ) then
                  tstVecIdx <= 0;
               else
                  tstVecIdx <= tstVecIdx + 1; 
               end if;
            end if;
         elsif ( tstReqAck = '1' ) then
            tstReqVld  <= (others => '0');
            tstParamOb <= (others => (others => '0'));
            if ( tstReqVld(1) = '1' ) then
               if    ( simReqParam.value(7 downto 0) = x"10" ) then
                  cmp := x"dead";
               elsif ( simReqParam.value(7 downto 0) = x"0A" ) then
                  cmp := regA;
                  assert std_logic_vector( val ) = regA report "write-date mismatch" severity failure;
               else
                  assert false report "should not be here" severity failure;
               end if;
               assert tstReqErr = '0' report "unexpected err" severity failure;
               assert tstParamIb(1) & tstParamIb(0) = cmp report "data mismatch" severity failure;
               nreqs  <= nreqs + 1;
            else
               nwrite <= nwrite + 1;
            end if;
         end if;
         if ( mcFilterUpd = '1' ) then
            assert mcFilter = cmpVec(nstrm mod cmpVec'length) report "MC filter mismatch" severity failure;
            nstrm <= nstrm + 1;
         end if;
      end if;
   end process;

   process ( mdioClk ) is
      variable mdin  : std_logic;
      variable wrenA : boolean := false;
      variable wrenB : boolean := false;
   begin
      if ( rising_edge( mdioClk ) ) then
         mdin := (mdioDatHiZ or mdioDatOut);
      end if;
      if ( falling_edge( mdioClk ) ) then
         if ( nbits < 0 ) then
            if (  mdin = '0' ) then
               nbits <= 1;
               sreg  <= x"fffffffe";
            end if;
         else
            sreg <= sreg(sreg'left - 1 downto 0) & mdin;
            if ( nbits = 31 ) then
               nbits   <= -1;
               ncycles <= ncycles + 1;
               if ( wrenA ) then
                  regA  <= sreg(14 downto 0) & mdin;
                  wrenA := false;
               end if;
               if ( wrenB ) then
                  regB  <= sreg(14 downto 0) & mdin;
                  wrenB := false;
               end if;
            else
               nbits <= nbits + 1;
            end if;
            if ( nbits = 13 ) then
               sreg(31 downto 14) <= "11" & x"ffff";

               if    ( sreg(12 downto 0) & mdin = "0110" & "00001" & "10000" ) then
                  sreg(31 downto 14) <= "10" & x"dead";
               elsif ( sreg(12 downto 0) & mdin = "0110" & "00001" & "01010" ) then
                  sreg(31 downto 14) <= "10" & regA;
               elsif ( sreg(12 downto 0) & mdin = "0110" & "00001" & "01011" ) then
                  sreg(31 downto 14) <= "10" & regB;
               elsif ( sreg(12 downto 0) & mdin = "0101" & "00001" & "01010" ) then
                  wrenA := true;
               elsif ( sreg(12 downto 0) & mdin = "0101" & "00001" & "01011" ) then
                  wrenB := true;
               end if;
            end if;
         end if;
      end if;
   end process;

   process ( mdioDatOut, sreg, mdioDatHiZ ) is
   begin
      mdioDatInp <= sreg(sreg'left);
      if ( mdioDatHiZ = '0' ) then
         mdioDatInp <= mdioDatOut;
      end if;
   end process;

   U_DUT : entity work.Usb2Ep0MDIOCtl
      generic map (
         MDC_PRESCALER_G => 1,
         SIMULATE_G      => true
      )
      port map (
         usb2Clk           => clk,
         usb2Rst           => rst,

         usb2CtlReqParam   => simReqParam,
         usb2CtlExt        => open, --: out Usb2CtlExtType;

         usb2EpIb          => open, --: in  Usb2EndpPairObType  := USB2_ENDP_PAIR_OB_INIT_C;
         usb2EpOb          => open, --: out Usb2EndpPairIbType;

         mdioClk           => mdioClk,
         mdioDatOut        => mdioDatOut,
         mdioDatHiZ        => mdioDatHiZ,
         mdioDatInp        => mdioDatInp,

         speed10           => open, -- out std_logic := '0';
         duplexFull        => open, -- out std_logic := '0';
         linkOk            => open, -- out std_logic := '1';
         mcFilter          => mcFilter,
         mcFilterUpd       => mcFilterUpd,
         -- full contents; above bits are for convenience
         statusRegPolled   => status,
         dbgReqVld         => tstReqVldMskd,
         dbgReqAck         => tstReqAck,
         dbgReqErr         => tstReqErr,
         dbgParamIb        => tstParamIb,
         dbgParamOb        => tstParamOb
      );

   tstReqVldMskd <= (tstReqVld and tstReqMsk);

end architecture sim;
