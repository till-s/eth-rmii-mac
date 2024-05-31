library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity EthMDIO is
   generic (
      PRESCALER_G   : positive := 1;
      NO_PREAMBLE_G : boolean  := false
   );
   port (
      clk           : in  std_logic;
      rst           : in  std_logic := '0';

      MClk          : out std_logic;
      MDInp         : in  std_logic;
      MDOut         : out std_logic;
      MDHiZ         : out std_logic;

      req           : in  std_logic := '0';
      ack           : out std_logic;
      -- no response from device
      err           : out std_logic;
      rdnwr         : in  std_logic := '1';
      devAddr       : in  std_logic_vector( 4 downto 0) := (others => '0');
      regAddr       : in  std_logic_vector( 4 downto 0) := (others => '0');
      wDat          : in  std_logic_vector(15 downto 0) := (others => '0');
      rDat          : out std_logic_vector(15 downto 0)
   );
end entity EthMDIO;

architecture rtl of EthMDIO is

   function nbits(constant x : natural) return natural is
      variable v : natural;
      variable p : natural;
   begin
      v := 0;
      p := 1;
      while p <= 2 loop
         p := p*2;
         v := v + 1;
      end loop;
      return v;
   end function nbits;

   type     StateType    is (PREAMBLE, IDLE, SHIFT);

   subtype  PrescType    is unsigned( nbits(PRESCALER_G - 1) - 1 downto 0 );

   constant PRESC_INIT_C :  PrescType := to_unsigned( PRESCALER_G - 1, PrescType'length );

   subtype CounterType   is signed(5 downto 0);

   -- count from N-2 downto -1
   function toCounter(constant x : in natural) return CounterType is
   begin
      return to_signed( x - 2, CounterType'length );
   end function toCounter;

   type RegType is record
      state          : StateType;
      sreg           : std_logic_vector(31 downto 0);
      oreg           : std_logic;
      zreg           : std_logic;
      nbits          : CounterType;
      ack            : std_logic;
      rdnwr          : std_logic;
      hiz            : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state          => PREAMBLE,
      sreg           => (others => '1'),
      oreg           => '1',
      zreg           => '1',
      nbits          => toCounter( 32 ),
      ack            => '0',
      rdnwr          => '1',
      hiz            => '1'
   );

   signal r          : RegType   := REG_INIT_C;
   signal rin        : RegType;
   signal hiz        : std_logic := '1';

   signal presc      : PrescType := PRESC_INIT_C;
   signal mclkRise   : std_logic;
   signal mclkFall   : std_logic;
   signal errLoc     : std_logic;

begin

   P_COMB : process ( r, MDInp, req, rdnwr, devAddr, regAddr, wDat, mclkRise, mclkFall, hiz, errLoc ) is
      variable v      : RegType;
      variable newHiz : std_logic;
   begin
      v     := r;

      -- half-presc delay for output signals
      -- (results in no delay with logic below in the
      -- case there is no prescaler)
      if ( mclkFall = '1' ) then
         v.oreg := r.sreg(r.sreg'left);
         v.zreg := hiz;
      end if;

      -- reset ack; in back-to-back cycles ack is set during the
      -- first IDLE cycle
      v.ack   := '0';

      -- combinatorial - unaffected by prescaler
      newHiz  := r.rdnwr and (not r.nbits(4) or r.nbits(5));

      if ( mclkRise = '1' ) then

         -- bit counter
         if ( r.nbits >= 0 ) then
            v.nbits := r.nbits - 1;
         end if;

         v.hiz := '1';

         case ( r.state ) is 

            when PREAMBLE =>
               if ( r.nbits < 0 ) then
                  v.state := IDLE;
               end if;

            when IDLE =>
               if ( req = '1' ) then
                  v.sreg  := "01" & rdnwr & not rdnwr & devAddr & regAddr & '1' & rdnwr & wDat;
                  if ( rdnwr = '1' ) then
                     -- for peace of mind
                     v.sreg(15 downto 0) := (others => '1');
                  end if;
                  v.nbits := toCounter( 31 );
                  v.state := SHIFT;
                  v.rdnwr := rdnwr;
               end if;

            when SHIFT =>
               v.sreg := r.sreg(r.sreg'left - 1 downto 0) & (not hiz or MDInp);
               v.hiz  := newHiz;

               if ( r.nbits < 0 ) then
                  v.ack := '1';
                  -- sreg(15) must be '0' if there is someone
                  -- responding to a read
                  if ( NO_PREAMBLE_G and ( errLoc = '0' ) ) then
                     v.state := IDLE;
                  else
                     v.state := PREAMBLE;
                     v.nbits := toCounter( 32 );
                  end if;
               end if;

         end case;

      end if;

      if ( r.state = SHIFT ) then
         hiz   <= newHiz;
      else
         hiz   <= r.hiz;
      end if;

      rin   <= v;
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

   G_NO_PRESC : if ( PRESCALER_G = 1 ) generate
      MClk     <= clk;
      MDOut    <= r.sreg(r.sreg'left);
      MDHiZ    <= hiz;
      mclkRise <= '1';
      mclkFall <= '1';
   end generate G_NO_PRESC;

   G_WITH_PRESC : if ( PRESCALER_G > 1 ) generate

      MClk     <= presc(presc'left);
      MDOut    <= r.oreg;
      MDHiZ    <= r.zreg;

      P_PRESC : process ( clk, presc ) is
         variable nxtPresc : PrescType;
      begin

         -- combinatorial to compute next clock level
         if ( presc = 0 ) then
            nxtPresc := PRESC_INIT_C;
         else
            nxtPresc := presc - 1;
         end if;

         mclkRise <=     nxtPresc(nxtPresc'left) and not presc(presc'left);
         mclkFall <= not nxtPresc(nxtPresc'left) and     presc(presc'left);

         if ( rising_edge( clk ) ) then
            if ( rst = '1' ) then
               presc <= PRESC_INIT_C;
            else
               presc <= nxtPresc;
            end if;
         end if;
      end process P_PRESC;

   end generate G_WITH_PRESC;

   ack     <= r.ack;
   errLoc  <= r.sreg(16) and r.rdnwr; -- read response should have pulled low
   err     <= errLoc;
   rDat    <= r.sreg(15 downto 0);

end architecture rtl;
