library ieee;
    use ieee.numeric_std.all;
    use ieee.std_logic_1164.all;
library work;

entity pwm_module is
generic (
    g_simulation        : boolean := true
);
port (
    clock_50        : in std_logic; 
-- Serial interface
    fpga_in_rx      : in std_logic;
    fpga_out_tx     : out std_logic;
    -- Key pushbutton inputs
    key_n           : in std_logic_vector(3 downto 0);   
    -- Switch input
    --sw                      => sw 
    -- 7 Segment display output
    hex0            : out std_logic_vector(6 downto 0);
    hex1            : out std_logic_vector(6 downto 0);
    hex2            : out std_logic_vector(6 downto 0);
    hex3            : out std_logic_vector(6 downto 0);
    -- Green led outputs
    ledg            : out std_logic_vector(7 downto 0);
    -- Red led outputs
    ledr            : out std_logic_vector(9 downto 0)
);
end entity pwm_module;

architecture rtl of pwm_module is

    signal clk_50   : std_logic := '0';
    signal pll_locked   : std_logic := '0';

    signal reset : std_logic := '0';

    signal key_on   : std_logic := '0';
    signal key_off  : std_logic := '0';
    signal key_up   : std_logic := '0';
    signal key_down : std_logic := '0';

    signal serial_on    : std_logic := '0';
    signal serial_off   : std_logic := '0';
    signal serial_up    : std_logic := '0';
    signal serial_down  : std_logic := '0';

-- D
    signal current_dc           : std_logic_vector(7 downto 0);
    signal current_dc_update    : std_logic := '0';

    signal transmit_ready       : std_logic := '0';
-- E
    signal transmit_data        : std_logic_vector(7 downto 0) := (others => '0');
    signal transmit_valid       : std_logic := '0';

-- B
    signal received_data        : std_logic_vector(7 downto 0) := (others => '0');
    signal received_data_valid  : std_logic := '0';

begin
   ledr(9 downto 1)     <= (others => '0');
   ledg(7 downto 1)     <= (others => '0');
  b_gen_pll : if (not g_simulation) generate
   -- Instance of PLL
      i_altera_pll : entity work.altera_pll
      port map(
         areset		=> '0',        -- Reset towards PLL is inactive
         inclk0		=> clock_50,   -- 50 MHz input clock
         c0		      => open,       -- 25 MHz output clock unused
         c1		      => clk_50,     -- 50 MHz output clock
         c2		      => open,       -- 100 MHz output clock unused
         locked		=> pll_locked);-- PLL Locked output signal
      i_reset_ctrl : entity work.reset_ctrl
      generic map(
         g_reset_hold_clk  => 127)
      port map(
         clk         => clk_50,
         reset_in    => '0',
         reset_in_n  => pll_locked, -- reset active if PLL is not locked
         reset_out   => reset,
         reset_out_n => open);
   end generate;
   b_sim_clock_gen : if g_simulation generate
      clk_50   <= clock_50;
      p_internal_reset : process
      begin
       reset    <= '1';
         wait until clock_50 = '1';
         wait for 1 us;
         wait until clock_50 = '1';
         reset    <= '0';
         wait;
      end process p_internal_reset;
   end generate;

    i_pwm_ctrl      : entity work.pwm_ctrl
    port map(
    -- Inputs
        clk_50              => clock_50,
        reset               => reset,

-- ///////////////// Block diagram A
    -- Key inputs will be pulsed high one clock pulse and key_up, key_down may be pulsed every 10 ms, indicating the key is being held.
        key_on              => key_on, -- Go back to previous DC (minimum 10%). Reset sets previous to 100%
        key_off             => key_off, -- Set current DC to 0%
        key_up              => key_up, -- Increase DC by 1%, 100% is maximum, minimum is 10%. If the unit is off, DC shall be set to 10% if this signal is received
        key_down            => key_down, -- Decrease DC by 1%, if unit is in the off state this signal is ignored

-- ///////////////// Block diagram C
    -- Inputs from the UART component. They have the same functionality as the key inputs but key inputs have priority.
        serial_on           => serial_on, -- Go back to previous DC (minimum 10%). Reset sets previous to 100%
        serial_off          => serial_off, -- Set current DC to 0%
        serial_up           => serial_up, -- Increase DC by 1%, 100% is maximum, minimum is 10%. If the unit is off, DC shall be set to 10% if this signal is received
        serial_down         => serial_down, -- Decrease DC by 1%, if unit is in the off state this signal is ignored

-- ///////////////// Block diagram D
    -- Outputs  
        current_dc          => current_dc, -- A byte representing the current duty cycle. range 0 - 100
        current_dc_update   => current_dc_update, -- A flag
-- PWM out
        ledg0             => ledg(0) -- Output led. 1 ms period.
    );

    i_key_ctrl      : entity work.key_ctrl
    port map(
        clk_50      => clock_50,
        reset       => reset, -- Active high.
        key_n       => key_n, -- 4 active low buttons.

    -- Outputs
        key_on      => key_on,
        key_off     => key_off,
        key_up      => key_up,
        key_down    => key_down
    ); 

    i_dc_disp       : entity work.dc_disp
    port map(
        clk_50              => clock_50,
        reset               => reset,
        transmit_ready      => transmit_ready,
    -- /////// D //////
        current_dc          => current_dc,
        current_dc_update   => current_dc_update,
    -- ////// E ///////
        transmit_data       => transmit_data,
        transmit_valid      => transmit_valid,
    -- Ouputs   
        hex0                => hex0,
        hex1                => hex1,
        hex2                => hex2
    );

    i_serial_ctrl   : entity work.serial_ctrl
    port map(
    -- Outputs
        serial_on           => serial_on,       -- Pulsed high when the input is x"31"
        serial_off          => serial_off,     -- Pulsed high when the input is x"30"
        serial_up           => serial_up,      -- Pulsed high when the input is x"55" or x"75"
        serial_down         => serial_down,    -- Pulsed high when the input is x"64" or x"44"
    -- Inputs
        clk_50              => clock_50, -- 50 MHz clock
		reset				=> reset, -- Active high
        received_data_valid => received_data_valid, -- Pulsed high one clock cycle
        received_data       => received_data -- An ASCII char, either u/U, d/D, 1 or 0
    );

    i_serial_uart   : entity work.serial_uart
    generic map(
        g_reset_active_state    => '1',
        g_serial_speed_bps      => 115200,
        g_clk_period_ns         => 20,      -- 100 MHz standard clock
        g_parity                => 0        -- 0 = no, 1 = odd, 2 = even
    )
    port map(
        clk                     => clock_50,
        reset                   => reset,    -- active high reset
        rx                      => fpga_in_rx,
        tx                      => fpga_out_tx,

        received_data           => received_data,
        received_valid          => received_data_valid,
        received_error          => ledr(0),            -- Stop bit was not high
        received_parity_error   => open,            -- Parity error detected

        transmit_ready          => transmit_ready,
        transmit_valid          => transmit_valid,
        transmit_data           => transmit_data
    );
end architecture;