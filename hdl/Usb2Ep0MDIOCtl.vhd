library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2UtilPkg.all;
use     work.Usb2Pkg.all;
use     work.Usb2EpGenericCtlPkg.all;
use     work.RMIIMacPkg.all;

entity Usb2Ep0MDIOCtl is
   generic (
      -- vendor-specific request 0 to this interface (host2dev) returns
      -- the command-set version;
      CMD_SET_VERSION_G : std_logic_vector(31 downto 0) := x"deadbeef";
      -- switch auto-polling off by setting to 0
      POLL_STATUS_PER_G : natural := 20;
      MDC_PRESCALER_G   : positive;
      NO_PREAMBLE_G     : boolean := false;
      PHY_ID_G          : natural := 1;
      SUPPORT_MC_FILT_G : boolean := true;
      -- simulate w/o actual USB stuff
      SIMULATE_G        : boolean := false
   );
   port (
      usb2Clk           : in  std_logic;
      usb2Rst           : in  std_logic;

      usb2CtlReqParam   : in  usb2CtlReqParamType := USB2_CTL_REQ_PARAM_INIT_C;
      usb2CtlExt        : out Usb2CtlExtType      := USB2_CTL_EXT_NAK_C;

      usb2EpIb          : in  Usb2EndpPairObType  := USB2_ENDP_PAIR_OB_INIT_C;
      usb2EpOb          : out Usb2EndpPairIbType  := USB2_ENDP_PAIR_IB_INIT_C;

      mdioClk           : out std_logic;
      mdioDatOut        : out std_logic;
      mdioDatHiZ        : out std_logic;
      mdioDatInp        : in  std_logic;

      speed10           : out std_logic := '0';
      duplexFull        : out std_logic := '0';
      linkOk            : out std_logic := '1';
      -- full contents; above bits are for convenience
      statusRegPolled   : out std_logic_vector(15 downto 0);
      mcFilter          : out EthMulticastFilterType := ETH_MULTICAST_FILTER_ALL_C;
      mcFilterUpd       : out std_logic              := '0';

      dbgReqVld         : in  std_logic_vector( 0 to 3 ) := (others => '0');
      dbgReqAck         : out std_logic := '1';
      dbgReqErr         : out std_logic := '1';
      dbgParamIb        : out Usb2ByteArray( 0 to 3 ) := (others => (others => '0'));
      dbgParamOb        : in  Usb2ByteArray( 0 to 3 ) := (others => (others => '0'))

   );
end entity Usb2Ep0MDIOCtl;

architecture rtl of Usb2Ep0MDIOCtl is
   constant USB2_REQ_VENDOR_GET_VERSION_C : Usb2CtlRequestCodeType := x"00";
   constant USB2_REQ_VENDOR_MDIO_C        : Usb2CtlRequestCodeType := x"01";
   constant USB2_REQ_VENDOR_SET_MC_FILT_C : Usb2CtlRequestCodeType := x"02";

   constant PHY_STATUS_REG_C              : std_logic_vector(4 downto 0) := "10000";

   constant BASIC_REQS_C                  : Usb2EpGenericReqDefArray := (
      0 => usb2MkEpGenericReqDef(
         dev2Host => '1',
         request  =>  USB2_REQ_VENDOR_GET_VERSION_C,
         dataSize =>  4
      ),
      1 => usb2MkEpGenericReqDef(
         dev2Host => '1',
         request  =>  USB2_REQ_VENDOR_MDIO_C,
         dataSize =>  2
      ),
      2 => usb2MkEpGenericReqDef(
         dev2Host => '0',
         request  =>  USB2_REQ_VENDOR_MDIO_C,
         dataSize =>  2
      )
   );

   constant MC_REQ_C : Usb2EpGenericReqDefArray := (
      0 => usb2MkEpGenericReqDef(
         dev2Host => '0',
         request  =>  USB2_REQ_VENDOR_SET_MC_FILT_C,
         dataSize =>  0,
         stream   =>  true
      )
   );

   constant CTL_REQS_C   : Usb2EpGenericReqDefArray :=
      concat( BASIC_REQS_C, ite( SUPPORT_MC_FILT_G, MC_REQ_C ) );

   constant MC_INIT_C    : EthMulticastFilterType   :=
      ite( SUPPORT_MC_FILT_G, ETH_MULTICAST_FILTER_INIT_C, ETH_MULTICAST_FILTER_ALL_C );


   type StateType is ( IDLE, BUSY, POLL );

   subtype McCntType is signed(4 downto 0);

   function toMcCnt(constant x : integer) return McCntType is
   begin
      return to_signed( x - 2, McCntType'length );
   end function toMcCnt;

   type RegType is record
      state      : StateType;
      ctlReq     : std_logic;
      ctlRdnwr   : std_logic;
      ctlDevAddr : std_logic_vector(4 downto 0);
      ctlRegAddr : std_logic_vector(4 downto 0);
      ctlwDat    : std_logic_vector(15 downto 0);
      poll       : integer range -1 to POLL_STATUS_PER_G - 2;
      pollVal    : std_logic_vector(15 downto 0);
      mcLst      : std_logic;
      mcCnt      : McCntType;
      mcFilter   : EthMulticastFilterType;
      mcUpd      : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state      => IDLE,
      ctlReq     => '0',
      ctlRdnwr   => '1',
      ctlDevAddr => (others => '0'),
      ctlRegAddr => (others => '0'),
      ctlwDat    => (others => '1'),
      poll       => -1,
      pollVal    => (others => '0'),
      mcLst      => '1',
      mcCnt      => (others => '0'),
      mcFilter   => MC_INIT_C,
      mcUpd      => '0'
   );

   signal r                : RegType   := REG_INIT_C;
   signal rin              : RegType   := REG_INIT_C;
      
   signal epReqVld         : std_logic_vector( CTL_REQS_C'range );
   signal epReqAck         : std_logic := '1';
   signal epReqErr         : std_logic := '1';

   signal paramIb          : Usb2ByteArray( 0 to maxParamSize( CTL_REQS_C ) - 1 );
   signal paramOb          : Usb2ByteArray( 0 to maxParamSize( CTL_REQS_C ) - 1 );

   signal ctlAck           : std_logic;
   signal ctlErr           : std_logic;
   signal ctlRDat          : std_logic_vector(15 downto 0);

   signal mcHash           : EthMulticastHashType := ETH_MULTICAST_HASH_INIT_C;
   signal mcHashIn         : EthMulticastHashType;
   signal mcHashCen        : std_logic;

begin

   G_SIM : if ( SIMULATE_G ) generate
      epReqVld   <= dbgReqVld;
      dbgReqAck  <= epReqAck;
      dbgReqErr  <= epReqErr;
      dbgParamIb <= paramIb;
      paramOb    <= dbgParamOb;
   end generate G_SIM;

   G_NO_SIM : if ( not SIMULATE_G ) generate

   U_EP_GENERIC_CTL : entity work.Usb2EpGenericCtl
      generic map (
         CTL_IFC_NUM_G     => -1,
         HANDLE_REQUESTS_G => CTL_REQS_C
      )
      port map (
         usb2Clk           => usb2Clk,
         usb2Rst           => usb2Rst,

         usb2CtlReqParam   => usb2CtlReqParam,
         usb2CtlExt        => usb2CtlExt,

         usb2EpIb          => usb2EpIb,
         usb2EpOb          => usb2EpOb,

         -- handshake. Note that ctlReqVld is *not* identical
         -- with usb2CtlReqParam.vld' the former signal communicates
         -- that this entity is ready to receive the inbound
         -- parameters or has the outbound parameters available;
         -- the bit corresponding to the associated HANDLE_REQUESTS_G
         -- alement is asserted:
         --  - for 'dev2Host' requests: when 'vld' is asserted
         --    prepare the 'paramIb' and assert 'ack' once the
         --    response is ready; 'err' concurrently with 'ack
         --    signals that the control endpoint should reply
         --    with 'STALL'
         --  - for host2dev requests; when 'vld' is asserted
         --    inspect the usb2CtlReqParam and paramOb and
         --    set 'ack' and 'err' (during the same cycle).
         --    If 'err' is set then the request is STALLed.
         --    Note that 'ctlReqVld' may never been asserted
         --    (this happens if the host does not send the
         --    correct amount of data). The user must then
         --    ignore the entire request.
         ctlReqVld         => epReqVld,
         ctlReqAck         => epReqAck,
         ctlReqErr         => epReqErr,

         paramIb           => paramIb,
         paramOb           => paramOb
      );

   end generate G_NO_SIM;

   U_MDIO_CTL : entity work.EthMDIO
      generic map (
         PRESCALER_G   => MDC_PRESCALER_G,
         NO_PREAMBLE_G => NO_PREAMBLE_G
      )
      port map (
         clk           => usb2Clk,
         rst           => usb2Rst,

         MClk          => mdioClk,
         MDInp         => mdioDatInp,
         MDOut         => mdioDatOut,
         MDHiZ         => mdioDatHiZ,

         req           => r.ctlReq,
         ack           => ctlAck,
         -- no response from device
         err           => ctlErr,
         rdnwr         => r.ctlRdnwr,
         devAddr       => r.ctlDevAddr,
         regAddr       => r.ctlRegAddr,
         wDat          => r.ctlWDat,
         rDat          => ctlRDat
      );

   G_HASH : if ( SUPPORT_MC_FILT_G ) generate

      P_HASH : process ( usb2Clk ) is
      begin
         if ( rising_edge( usb2Clk ) ) then
            if ( usb2Rst = '1' ) then
               mcHash <= ETH_MULTICAST_HASH_INIT_C;
            elsif ( mcHashCen = '1' ) then
               mcHash <= ethMulticastHash( mcHashIn, usb2EpGenericStrmDat( paramOb ) );
            end if;
         end if;
      end process P_HASH;

   end generate G_HASH;

   P_COMB : process ( r, usb2CtlReqParam, epReqVld, paramOb, ctlAck, ctlErr, ctlRDat, mcHash ) is
      variable v : RegType;
   begin
      v        := r;

      epReqAck  <= '1';
      epReqErr  <= '1';
      mcHashCen <= '0';
      if ( ( r.mcLst = '1' ) or ( r.mcCnt < 0 ) ) then
         mcHashIn  <= ETH_MULTICAST_HASH_INIT_C;
      else
         mcHashIn  <= mcHash;
      end if;

      v.mcUpd  := '0';

      paramIb                <= (others => (others => '0'));
      paramIb(0)             <= CMD_SET_VERSION_G( 7 downto  0);
      paramIb(1)             <= CMD_SET_VERSION_G(15 downto  8);
      paramIb(2)             <= CMD_SET_VERSION_G(23 downto 16);
      paramIb(3)             <= CMD_SET_VERSION_G(31 downto 24);

      if ( epReqVld(1) = '1' ) then
         paramIb(0)             <= ctlRDat( 7 downto 0);
         paramIb(1)             <= ctlRDat(15 downto 8);
      end if;

      if ( SUPPORT_MC_FILT_G ) then
         -- do this regardless of epReqVld; mops up the last stream byte
         if ( r.mcCnt < 0 ) then
            v.mcCnt                              := toMcCnt( 6 );
            v.mcFilter( to_integer( mcHash ) )   := '1';
            v.mcUpd                              := r.mcLst;
         end if;
      end if;

      if    ( epReqVld( 0 ) = '1' ) then
         epReqAck                         <= '1';
         epReqErr                         <= '0';
      elsif ( SUPPORT_MC_FILT_G and (epReqVld( 3 ) = '1') ) then
         v.mcLst   := usb2EpGenericStrmLst( paramOb );
         mcHashCen <= '1';
         if ( r.mcLst = '1' ) then
            -- new request; clear filters
            v.mcFilter := ETH_MULTICAST_FILTER_INIT_C;
         end if;
         if ( ( r.mcLst = '1' ) or ( r.mcCnt < 0 ) ) then
            v.mcCnt  := toMcCnt( 6 );
         else
            v.mcCnt  := r.mcCnt - 1;
         end if;
      end if;

      case ( r.state ) is

         when IDLE =>

            if ( ( epReqVld( 1 ) or epReqVld(2) ) = '1'  ) then

               epReqAck <= '0';
               epReqErr <= ctlErr;

               if ( r.ctlReq = '0' ) then
                  v.ctlReq     := '1';
                  v.ctlRdnwr   := epReqVld(1); -- read
                  v.ctlDevAddr := usb2CtlReqParam.value(12 downto 8);
                  v.ctlRegAddr := usb2CtlReqParam.value( 4 downto 0);
                  v.ctlWDat    := paramOb(1) & paramOb(0);
                  if ( v.ctlRdnwr = '0' ) then
                     -- posted write;
                     epReqAck <= '1';
                     v.state  := BUSY;
                  end if;
               end if;

            elsif ( POLL_STATUS_PER_G > 0 ) then
               if ( r.poll < 0 ) then
                  v.poll       := POLL_STATUS_PER_G - 2;

                  v.ctlReq     := '1';
                  v.ctlRdnwr   := '1';
                  v.ctlDevAddr := std_logic_vector( to_unsigned( PHY_ID_G, 5 ) );
                  v.ctlRegAddr := PHY_STATUS_REG_C;
                  v.state      := POLL;
               else
                  v.poll := r.poll - 1;
               end if;
            end if;

         when BUSY | POLL =>
            if ( ( epReqVld( 1 ) or epReqVld(2) ) = '1'  ) then
               -- hold off new request
               epReqAck <= '0';
            end if;

      end case;

      if ( ctlAck = '1' ) then
         v.ctlReq := '0';
         v.state  := IDLE;
         if ( r.state = BUSY or r.state = POLL ) then
            -- posted write or polling ended; posted write was already acked to the endpoint
            if ( r.state = POLL ) then
               v.pollVal := ctlRDat;
            end if;
         else
            epReqAck <= '1';
            epReqErr <= '0';
         end if;
      end if;

      rin    <= v;
   end process P_COMB;

   P_SEQ : process ( usb2Clk ) is
   begin
      if ( rising_edge( usb2Clk ) ) then
        if ( usb2Rst = '1' ) then
          r <= REG_INIT_C;
         else
          r <= rin;
         end if;
      end if;
   end process P_SEQ;

   linkOK          <= r.pollVal(0);
   speed10         <= r.pollVal(1);
   duplexFull      <= r.pollVal(2);
   statusRegPolled <= r.pollVal;
   mcFilter        <= r.mcFilter;
   mcFilterUpd     <= r.mcUpd;
      
end architecture rtl;

