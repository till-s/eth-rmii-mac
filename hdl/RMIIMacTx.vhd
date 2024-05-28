library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.RMIIMacPkg.all;

entity RMIIMacTx is
   port (
      clk        : in  std_logic;
      rst        : in  std_logic := '0';

      -- FIFO/stream interface
      txDat      : in  std_logic_vector(7 downto 0);
      txVld      : in  std_logic;
      txLst      : in  std_logic;
      txRdy      : out std_logic;

      -- RMII interface
      rmiiDat    : out std_logic_vector(1 downto 0);
      rmiiTxEn   : out std_logic;

      -- abort/collision
      coll       : in  std_logic := '0';
      speed10    : in  std_logic := '0';
      linkOK     : in  std_logic := '1';
      appendCRC  : in  std_logic := '0'
   );
end entity RMIIMacTx;

architecture rtl of RMIIMacTx is

   subtype TimerType is signed(LD_SLOT_BIT_TIME_C + LD_MAX_BACKOFF_C - LD_RMII_BITS_C downto 0);
   subtype BoffType  is unsigned(LD_MAX_BACKOFF_C - 1 downto 0);

   constant BOFF_SLOT_SHIFT_C     : signed(LD_SLOT_BIT_TIME_C - LD_RMII_BITS_C - 1 downto 0) := (others => '0');

   constant TIMER_OFF_C           : TimerType := (others => '1');

   function toTimer(constant x : in integer)
   return TimerType is
   begin
      return to_signed( x - 2, TimerType'length );
   end function toTimer;

   type StateType is (IDLE, PREAMBLE, SEND, PAD, CRC);

   type RegType is record
      state     : StateType;
      timer     : TimerType;
      presc     : signed(4 downto 0);
      phase     : unsigned(1 downto 0);
      txEn      : std_logic;
      crc       : std_logic_vector(31 downto 0);
      boffRand  : BoffType;
      boffMsk   : BoffType;
      lstColl   : std_logic;
      appendCRC : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state     => IDLE,
      timer     => TIMER_OFF_C,
      presc     => (others => '1'),
      phase     => (others => '0'),
      txEn      => '0',
      crc       => (others => '1'),
      boffRand  => (others => '0'),
      boffMsk   => (others => '0'),
      lstColl   => '0',
      appendCRC => '0'
   );

   signal r     : RegType := REG_INIT_C;
   signal rin   : RegType;
begin

   P_COMB : process (r, txDat, txVld, txLst, coll, speed10, linkOK, appendCRC) is
      variable v          : RegType;
      variable rmiiDatMux : std_logic_vector(1 downto 0);
      variable crcDatMux  : std_logic_vector(1 downto 0);
      variable crcNext    : std_logic_vector(31 downto 0);
   begin

      v          := r;
      txRdy      <= '0';
      v.lstColl  := coll;
      v.boffRand := r.boffRand + 1;

      -- rmiiDat mux must select all the time (i.e., when prescaler is counting)
      -- txRdy is asserted '1' below which is in effect only for 1 clock cycle

      if    ( r.phase = "00" ) then
         crcDatMux := txDat(1 downto 0);
      elsif ( r.phase = "01" ) then
         crcDatMux := txDat(3 downto 2);
      elsif ( r.phase = "10" ) then
         crcDatMux := txDat(5 downto 4);
      else
         crcDatMux := txDat(7 downto 6);
      end if;
      if ( r.state = PAD ) then
         crcDatMux := "00";
      end if;

      crcNext := crc32LE2Bit( r.crc, crcDatMux );

      case ( r.state ) is
         when PREAMBLE =>
            rmiiDatMux(0) := '1';
            -- SOF bit is '1' during the last cycle 
            rmiiDatMux(1) := r.timer(r.timer'left);
            -- latch CRC;  input value could change
            -- if we are padding and the next packet
            -- is already ready and has a different crc mode...
            v.appendCRC   := appendCRC;

         when PAD =>
            rmiiDatMux    := "00";

         when CRC =>
            rmiiDatMux    := not r.crc(1 downto 0);

         when others =>
            rmiiDatMux    := crcDatMux;
      end case;

      if ( r.presc < 0 ) then

         if ( speed10 = '1' ) then
            v.presc := to_signed( 10 - 2, v.presc'length );
         end if;

         if ( r.timer >= 0 ) then
            v.timer := r.timer - 1;
         end if;

         case ( r.state ) is
            when IDLE =>
               if ( txVld = '1' and r.timer < 0 ) then
                  v.state := PREAMBLE;
                  -- use timer to count preamble pairs
                  -- last pair is emitted when the counter
                  -- is down to -1
                  v.timer := toTimer( 7*4 );
                  v.txEn  := '1';
               end if;
               v.crc := ETH_CRC_INIT_LE_C;

            when PREAMBLE =>
               if ( r.timer < 0 ) then
                  v.state := SEND;
                  if ( r.appendCRC = '1' ) then
                     v.timer := toTimer( (64 - 4)*4 );
                  else
                     v.timer := toTimer( 64*4 );
                  end if;
               end if;

            when SEND | PAD =>
               v.phase := r.phase + 1;
               v.crc   := crcNext;
               if ( r.phase = 3 ) then
                  if ( r.state = SEND ) then
                     txRdy <= '1';
                  end if;
                  if ( (txLst = '1' ) or (r.state = PAD) ) then
                     if ( r.timer < 0 ) then
                        if ( r.appendCRC = '1' ) then
                           v.state   := CRC;
                           v.timer   := toTimer( r.crc'length / RMII_BITS_C );
                        else
                           v.txEn    := '0';
                           -- successful transmission; reset backoff interval to min.
                           v.boffMsk := (others => '0');
                           v.state   := IDLE; 
                           v.timer   := toTimer( IPG_BIT_TIME_C / RMII_BITS_C );
                        end if;
                     else
                        v.state := PAD;
                     end if;
                  end if;
               end if;

               when CRC =>
                  v.crc := std_logic_vector(shift_right(unsigned(r.crc), RMII_BITS_C));
                  if ( r.timer < 0 ) then
                    v.txEn    := '0';
                    -- successful transmission; reset backoff interval to min.
                    v.boffMsk := (others => '0');
                    v.state   := IDLE; 
                    v.timer   := toTimer( IPG_BIT_TIME_C / RMII_BITS_C );
                  end if;

         end case;

      end if; -- r.presc < 0

      if ( ( coll or r.lstColl or not linkOk ) = '1' ) then
         v.state := IDLE;
         v.txEn  := '0';
         v.phase := (others => '0');
         v.presc := (others => '1');
      end if;

      if ( coll = '1' ) then
         if ( r.lstColl = '0' ) then
            v.boffMsk := r.boffMsk(r.boffMsk'left - 1 downto 0) & '1';
         end if;
      elsif ( r.lstColl = '1' ) then
         if ( ( r.boffRand and r.boffMsk ) = 0 ) then
            v.timer := toTimer( IPG_BIT_TIME_C / RMII_BITS_C );
         else
            v.timer := '0' & signed( r.boffRand and r.boffMsk ) & BOFF_SLOT_SHIFT_C;
         end if;
      end if;

      rmiiDat <= rmiiDatMux;
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

   rmiiTxEn <= r.txEn;

end architecture rtl;

