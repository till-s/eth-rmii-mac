library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity EthMDIOTb is
end entity EthMDIOTb;

architecture sim of EthMDIOTb is

   constant PRESCALER_C   : positive := 1;
   constant NO_PREAMBLE_C : boolean  := true;

   signal clk           : std_logic := '0';
   signal rst           : std_logic := '0';

   signal MClk          : std_logic;
   signal MDInp         : std_logic;
   signal MDOut         : std_logic;
   signal MDHiZ         : std_logic;

   signal req           : std_logic := '0';
   signal ack           : std_logic;
   -- no response from device
   signal err           : std_logic;
   signal rdnwr         : std_logic := '0';
   signal devAddr       : std_logic_vector( 4 downto 0) := "10010";
   signal regAddr       : std_logic_vector( 4 downto 0) := "01011";
   signal wDat          : std_logic_vector(15 downto 0) := x"dead";
   signal rDat          : std_logic_vector(15 downto 0);

   signal resp          : std_logic_vector(31 downto 0) := x"fffe3ca2";

   signal ackd          : std_logic_vector(3 downto 0)  := (others => '0');
   signal respin        : std_logic := '1';

begin

   P_CLK : process is
   begin
      if ( ackd(0) = '1' ) then
         wait;
      else
         wait for 5 ns;
         clk <= not clk;
      end if;
   end process P_CLK;

   P_ACK : process (clk) is
      variable cnt : natural := 2;
   begin
      if ( rising_edge( clk ) ) then
         if ( req = '0' ) then
            if ( cnt > 0 ) then
               req <= '1';
            end if;
         elsif ( ack = '1' ) then
            req <= '0';
            cnt := cnt - 1;
         end if;
         if ( cnt = 0 ) then
            ackd <= ack & ackd(ackd'left downto 1);
         else
            ackd <= '0' & ackd(ackd'left downto 1);
         end if;
      end if;
   end process P_ACK;

   P_DRV : process (MClk, resp, MDOut) is
      variable run : boolean := false;
   begin
      if ( rising_edge( MClk ) ) then
         respin <= MDOut;
         if ( MDOut = '0' ) then
            run := true;
         end if;
      end if;
      if ( falling_edge( MClk ) ) then
         if ( run ) then
            resp <= resp( resp'left - 1 downto 0 ) & respin;
         end if;
      end if;
      if ( MDHiZ = '1' ) then
         MDInp <= resp(resp'left - 1);
      else
         MDInp <= MDOut;
      end if;
   end process P_DRV;

   U_DUT : entity work.EthMDIO
      generic map (
         PRESCALER_G   => PRESCALER_C,
         NO_PREAMBLE_G => NO_PREAMBLE_C
      )
      port map (
         clk           => clk,
         rst           => rst,

         MClk          => MClk,
         MDInp         => MDInp,
         MDOut         => MDOut,
         MDHiZ         => MDHiZ,

         req           => req,
         ack           => ack,
         -- no response from device
         err           => err,
         rdnwr         => rdnwr,
         devAddr       => devAddr,
         regAddr       => regAddr,
         wDat          => wDat,
         rDat          => rDat
      );
end architecture sim;
