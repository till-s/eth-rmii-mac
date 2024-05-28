library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity RMIIMacTxTb is
end entity RMIIMacTxTb;

architecture sim of RMIIMacTxTb is
   signal clk        : std_logic := '0';
   signal rst        : std_logic := '0';
   signal txDat      : std_logic_vector(7 downto 0) := (others => '0');
   signal txVld      : std_logic := '0';
   signal txLst      : std_logic := '0';
   signal txRdy      : std_logic;

   signal rmiiDat    : std_logic_vector(1 downto 0);
   signal rmiiTxEn   : std_logic;

   signal coll       : std_logic := '0';
   signal speed10    : std_logic := '0';
   signal linkOK     : std_logic := '1';
   signal appendCRC  : std_logic := '0';

   signal running    : boolean := true;

   signal nbits      : natural   := 0;
   signal shfReg     : std_logic_vector(7 downto 0);
   signal nxtShfReg  : std_logic_vector(7 downto 0);
   signal shfRegVld  : std_logic := '0';

   signal active     : std_logic := '0';

   subtype Slv9 is std_logic_vector(8 downto 0);
   type Slv9Array is array (natural range <>) of Slv9;
   subtype Slv10 is std_logic_vector(9 downto 0);
   type Slv10Array is array (natural range <>) of Slv10;

   constant EXP_NUM_PKTS_C : natural := 2;

   constant txVec    : Slv10Array := (
      -- padded packet
      "00" & x"ff",
      "01" & x"ff",
      -- packet with checksum
      "10" & x"ff",
      "11" & x"ff"
   );

   constant rxVec    : Slv9Array := (
      '0' & x"ff", '0' & x"ff", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", 
      '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", 
      '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", 
      '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", 
      '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", 
      '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", 
      '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", 
      '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '1' & x"00",

      '0' & x"ff", '0' & x"ff", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", 
      '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", 
      '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", 
      '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", 
      '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", 
      '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", 
      '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", 
      '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"00", '0' & x"FC", '0' & x"09", '0' & x"e1", '1' & x"7b"
   );


   signal ridx       : natural := 0;
   signal tidx       : natural := 0;
   constant MIN_IPG_C: natural := 96/2;
   signal ipg        : natural := MIN_IPG_C;
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

   nxtShfReg <= rmiiDat & shfReg(7 downto 2);

   P_OBS : process ( clk ) is
   begin
      if ( rising_edge ( clk ) ) then
         shfRegVld <= '0';

         if ( active = '1' ) then
            if ( rmiiTxEn = '1' ) then
               shfReg <= nxtShfReg;
               nbits  <= nbits + 2;
               if ( nbits = 6 ) then
                  nbits     <= 0;
                  shfRegVld <= '1';
               end if;
            end if;
            if ( rmiiTxEn = '0' ) then
               assert nbits = 0 report "number of bits sent not a multiple of 8" severity failure;
               active <= '0';
               ipg    <=  1; -- already one clock expired
            end if;
         else
            if ( rmiiTxEn = '1' ) then
               assert ipg >= MIN_IPG_C report "IPG violation" severity failure;
               if ( rmiiDat = "11" ) then -- SOF
                  active <= '1';
               end if;
            else
               ipg <= ipg + 1;
            end if;
         end if;

         if ( shfRegVld = '1' ) then
            assert shfReg = rxVec(ridx)(7 downto 0) report "data mismatch @" & integer'image(ridx) severity failure;
            assert ( not rmiiTxEn and active ) = rxVec(ridx)(8) report "last flag mismatch"  severity failure;
            if ( rxVec(ridx)(8) = '1' ) then
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

   txDat     <= txVec(tidx)(7 downto 0);
   txLst     <= txVec(tidx)(8);
   appendCRC <= txVec(tidx)(9);

   P_SND : process (clk) is
   begin
      if ( rising_edge( clk ) ) then
         txVld <= '1';
         if ( ( txVld and txRdy ) = '1' ) then
            if ( tidx = txVec'high ) then
               txVld <= '0';
            else
               tidx  <= tidx + 1;
            end if;
         end if;
      end if;
   end process P_SND;

   U_DUT : entity work.RMIIMacTx
      port map (
         clk        => clk,
         rst        => rst,

         txDat      => txDat,
         txVld      => txVld,
         txLst      => txLst,
         txRdy      => txRdy,

         rmiiDat    => rmiiDat,
         rmiiTxEn   => rmiiTxEn,

         coll       => coll,
         speed10    => speed10,
         linkOK     => linkOK,
         appendCRC  => appendCRC
      );

end architecture sim;
