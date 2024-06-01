library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2UtilPkg.all;
use     work.Usb2Pkg.all;

entity Usb2Ep0MDIOCtlTb is
end entity Usb2Ep0MDIOCtlTb;

architecture sim of Usb2Ep0MDIOCtlTb is
   signal clk            : std_logic := '0';
   signal rst            : std_logic := '0';

   signal mdioClk        : std_logic;
   signal mdioDatOut     : std_logic;
   signal mdioDatInp     : std_logic;
   signal mdioDatHiZ     : std_logic;
   signal running        : boolean := true;

   signal sreg           : std_logic_vector(31 downto 0) := (others => '1');
   signal nbits          : integer := -1;
   signal ncycles        : integer := 0;
   signal nreqs          : integer := 0;
   signal nwrite         : integer := 0;
   signal match          : boolean := true;

   signal tstReqVld      : std_logic_vector(0 to 3) := (others => '0');
   signal tstReqAck      : std_logic;
   signal tstReqErr      : std_logic;
   signal tstParamIb     : Usb2ByteArray(0 to 7);
   signal tstParamOb     : Usb2ByteArray(0 to 7);
   signal simReqParam    : Usb2CtlReqParamType := USB2_CTL_REQ_PARAM_INIT_C;
   signal status         : std_logic_vector(15 downto 0);

   signal regA           : std_logic_vector(15 downto 0) := x"ABCD";
   signal regB           : std_logic_vector(15 downto 0) := x"3210";

   signal rand           : natural := 0;
begin

   process is
   begin
      if ( ncycles > 3 and nreqs > 20 and nwrite > 4 ) then
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
         if ( tstReqVld = "0000" ) then 
            if ( rand mod 13 = 0 ) then
               tstReqVld(1)      <= '1';
               simReqParam.value <= x"01" & x"10"; -- PHY_ID - REGISTER
            elsif ( rand mod 17 = 0 ) then
               tstReqVld(1)      <= '1';
               simReqParam.value <= x"01" & x"0A"; -- PHY_ID - REGISTER
            elsif ( rand mod 11 = 0 ) then
               tstReqVld(2)      <= '1';
               simReqParam.value <= x"01" & x"0A"; -- PHY_ID - REGISTER
               val               := val + x"0101";
               tstParamOb(1)     <= std_logic_vector( val(15 downto 8) );
               tstParamOb(0)     <= std_logic_vector( val( 7 downto 0) );
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
         -- full contents; above bits are for convenience
         statusRegPolled   => status,
         dbgReqVld         => tstReqVld,
         dbgReqAck         => tstReqAck,
         dbgReqErr         => tstReqErr,
         dbgParamIb        => tstParamIb,
         dbgParamOb        => tstParamOb
      );

end architecture sim;
