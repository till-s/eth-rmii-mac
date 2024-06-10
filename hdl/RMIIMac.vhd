library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.RMIIMacPkg.all;

entity RMIIMac is
   port (
      clk         : in  std_logic;
      rst         : in  std_logic       := '0';

      txStrm      : in  RMIIMacStrmType := RMII_MAC_STRM_INIT_C;
      txRdy       : out std_logic       := '1';

      rxStrm      : out RMIIMacStrmType := RMII_MAC_STRM_INIT_C;
      rxRdy       : in  std_logic       := '1';
      rxAbort     : out std_logic       := '0';

      ctrl        : in  RMIIMacCtrlType := RMII_MAC_CTRL_INIT_C;

      rmiiTxDat   : out std_logic_vector(1 downto 0);
      rmiiTxEn    : out std_logic;
 
      rmiiRxDat   : in  std_logic_vector(1 downto 0);
      rmiiRxDV    : in  std_logic
   );
end entity RMIIMac;

architecture rtl of RMIIMac is
   signal rxRst          : std_logic := '0';
   signal txRst          : std_logic := '0';
   signal rxNotAccepted  : std_logic;
   signal rxAbortLoc     : std_logic;
begin

   rxAbortLoc       <= rxNotAccepted or ctrl.collision or not ctrl.linkOK;
   rxAbort          <= rxAbortLoc;
   rxRst            <= rxAbortLoc or rst;
   txRst            <= rst;

   U_RX : entity work.RMIIMacRx
      port map (
         clk        => clk,
         rst        => rxRst,

         -- FIFO/stream interface
         rxDat      => rxStrm.dat,
         rxVld      => rxStrm.vld,
         rxLst      => rxStrm.lst,
         rxRdy      => rxRdy,
         rxAbt      => rxNotAccepted,

         -- RMII interface
         rmiiDat    => rmiiRxDat,
         rmiiDV     => rmiiRxDV,

         -- addressing
         -- address **in LE format**, i.e., first octet on wire is [7:0]
         macAddr    => ctrl.macAddr,
         promisc    => ctrl.promisc,
         allmulti   => ctrl.allmulti,
         mcFilter   => ctrl.mcFilter,

         -- misc
         speed10    => ctrl.speed10,
         stripCRC   => ctrl.stripCRC
      );

   U_TX : entity work.RMIIMacTx
      port map (
         clk        => clk,
         rst        => txRst,

         -- FIFO/stream interface
         txDat      => txStrm.dat,
         txVld      => txStrm.vld,
         txLst      => txStrm.lst,
         txRdy      => txRdy,

         -- RMII interface
         rmiiDat    => rmiiTxDat,
         rmiiTxEn   => rmiiTxEn,

         -- abort/collision
         coll       => ctrl.collision,
         speed10    => ctrl.speed10,
         linkOK     => ctrl.linkOK,
         appendCRC  => ctrl.appendCRC
      );

end architecture rtl;
