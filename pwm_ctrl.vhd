
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
library work;

entity pwm_ctrl is
port(
    -- Inputs
        clk_50              : in std_logic; -- 50 MHz clock.
        reset               : in std_logic; -- Active high.

        duty_cycle_out      : out integer;
        prev_duty_out       : out integer;
        key_event_out       : out std_logic;

-- ///////////////// Block diagram A
    -- Key inputs will be pulsed high one clock pulse and key_up, key_down may be pulsed every 10 ms, indicating the key is being held.
        key_on              : in std_logic := '0'; -- Go back to previous DC (minimum 10%). Reset sets previous to 100%
        key_off             : in std_logic := '0'; -- Set current DC to 0%
        key_up              : in std_logic := '0'; -- Increase DC by 1%, 100% is maximum, minimum is 10%. If the unit is off, DC shall be set to 10% if this signal is received
        key_down            : in std_logic := '0'; -- Decrease DC by 1%, if unit is in the off state this signal is ignored

-- ///////////////// Block diagram C
    -- Inputs from the UART component. They have the same functionality as the key inputs but key inputs have priority.
        serial_on           : in std_logic := '0'; -- Go back to previous DC (minimum 10%). Reset sets previous to 100%
        serial_off          : in std_logic := '0'; -- Set current DC to 0%
        serial_up           : in std_logic := '0'; -- Increase DC by 1%, 100% is maximum, minimum is 10%. If the unit is off, DC shall be set to 10% if this signal is received
        serial_down         : in std_logic := '0'; -- Decrease DC by 1%, if unit is in the off state this signal is ignored

-- ///////////////// Block diagram D
    -- Outputs  
        current_dc          : out std_logic_vector(7 downto 0); -- A byte representing the current duty cycle. range 0 - 100
        current_dc_update   : out std_logic := '0'; -- A flag
-- PWM out
        ledg0               : out std_logic := '0' -- Output led. 1 ms period.
);
end entity pwm_ctrl;

architecture rtl of pwm_ctrl is

-- An enum to indicate wether the component is on or not. No modulation will be done when off.
    type t_power_state is (
        s_on,
        s_off
    );
    signal power_state      : t_power_state := s_off;

    constant c_period_time  : integer := 50000; -- One period. 1 ms at 50 MHz
    constant c_compare      : integer := 500; -- Two orders of magnitude less than the period, to avoid having to use division

    signal reset_1r         : std_logic := '0';
    signal reset_2r         : std_logic := '0';

    signal cnt_1ms_period   : integer range 0 to c_period_time := 0; -- A timer

    signal count_compare    : integer range 0 to c_period_time := 0; -- The value to be compared to the timer above

    signal duty_cycle       : integer range 0 to 100 := 0; -- Multiply count_compare with this value to get the number of clock cycles for the given duty cycle
                                                               -- Meaning count_compare * duty_cycle <= cnt_1ms_period
    signal previous_duty    : integer range 0 to 100 := 0; 

-- Some flags    
    signal pwm_gen_on_flag              : std_logic := '0';
    signal duty_cycle_valid_flag        : std_logic := '0';
    signal current_dc_update_delay_flag : std_logic := '0';

    signal key_input_1r     : std_logic_vector(3 downto 0) := (others => '0');
    signal key_input_2r     : std_logic_vector(3 downto 0) := (others => '0');
    signal serial_input_1r     : std_logic_vector(3 downto 0) := (others => '0');
    signal serial_input_2r     : std_logic_vector(3 downto 0) := (others => '0');

    signal input_event      : std_logic := '0';

begin

    duty_cycle_out <= duty_cycle;
    prev_duty_out <= previous_duty;

-- Sync inputs
    p_sync_inputs       : process(clk_50) is
    begin
        if rising_edge(clk_50) then
            reset_1r    <= reset;
            reset_2r    <= reset_1r;

            key_input_1r <= key_on & key_off & key_up & key_down;
            key_input_2r <= key_input_1r;

            serial_input_1r <= serial_on & serial_off & serial_up & serial_down;
            serial_input_2r <= serial_input_1r;
        end if;
    end process p_sync_inputs;

-- Increment and reset the counter as needed.
    p_counter       : process(clk_50, reset_2r) is
    begin
        if rising_edge(clk_50) then
            if cnt_1ms_period = c_period_time then
                cnt_1ms_period <= 0;
            else
                cnt_1ms_period <= cnt_1ms_period + 1;    
            end if;
        end if;

        if reset_2r = '1' then
            cnt_1ms_period <= 0;
        end if;
    end process p_counter;

    p_key_event : process(clk_50) is
    begin
        if rising_edge(clk_50) then
            if input_event = '1' then
                key_event_out <= '1';
            else 
                key_event_out <= '0';
            end if;
        end if;
    end process p_key_event;

    p_output_duty_cycle         : process(clk_50, reset_2r) is -- Update output signal at the end of each period. Reset ouputs 0%
    begin
        if rising_edge(clk_50) then
            current_dc_update <= '0';
            current_dc <= std_logic_vector(to_unsigned(duty_cycle, current_dc'length));
            --if cnt_1ms_period = c_period_time then -- Updates sent once per ms.
            if input_event = '1' then -- Updates are sent once per change in duty cycle.
                --current_dc <= std_logic_vector(to_unsigned(duty_cycle, current_dc'length));
                current_dc_update <= '1';
            end if;
        end if;
        if reset_2r = '1' then
            current_dc <= std_logic_vector(to_unsigned(0, current_dc'length));
            current_dc_update <= '1';
        end if;
    end process p_output_duty_cycle;


-- Contol the duty cycle. Checks if the component is on or not, and sets the duty cycle as specified in the specification.    
    p_duty_cycle_control    : process(clk_50, reset_2r, key_input_2r, serial_input_2r) is
    begin
        if rising_edge(clk_50) then
            
        input_event <= '0';

    -- Rework:

            case serial_input_2r is
                when "1000" => -- On

                    input_event <= '1';

                    if previous_duty < 10 then
                        duty_cycle <= 10;
                        previous_duty <= 10;
                    else 
                        duty_cycle <= previous_duty;
                    end if;

                when "0100" => -- Off
                
                input_event <= '1';

                    duty_cycle <= 0;

                when "0010" => -- Up
                
                input_event <= '1';

                    case duty_cycle is
                        when 100 =>
                            null;
                        when 0 =>
                            duty_cycle <= 10;
                            previous_duty <= 10;
                        when others =>
                            duty_cycle <= duty_cycle + 1;
                            previous_duty <= duty_cycle + 1;
                    end case;

                when "0001" => -- Down
                
                input_event <= '1';

                    case duty_cycle is
                        when 0 =>
                            null;
                        when 10 =>
                            null;
                        when others =>
                            duty_cycle <= duty_cycle - 1;
                            previous_duty <= duty_cycle - 1;
                    end case;

                when others =>
                    null;

            end case;

            case key_input_2r is
                when "1000" => -- On
                
                input_event <= '1';

                    if previous_duty < 10 then
                        duty_cycle <= 10;
                        previous_duty <= 10;
                    else 
                        duty_cycle <= previous_duty;
                    end if;

                when "0100" => -- Off
                
                input_event <= '1';

                    duty_cycle <= 0;

                when "0010" => -- Up
                
                input_event <= '1';

                    case duty_cycle is
                        when 100 =>
                            null;
                        when 0 =>
                            duty_cycle <= 10;
                            previous_duty <= 10;

                        when others =>
                            duty_cycle <= duty_cycle + 1;
                            previous_duty <= duty_cycle + 1;
                    end case;

                when "0001" => -- Down
                
                input_event <= '1';

                    case duty_cycle is
                        when 0 =>
                            null;
                        when 10 =>
                            null;
                        when others =>
                            duty_cycle <= duty_cycle - 1;
                            previous_duty <= duty_cycle - 1;
                    end case;

                when others =>
                    null;
            end case;
        end if;
 
        if reset_2r = '1' then 
            previous_duty <= 100;
            duty_cycle <= 0;
        end if;
    end process p_duty_cycle_control;

    p_pwm_generation        : process(clk_50, reset_2r) is
    begin
        if rising_edge(clk_50) then
            ledg0 <= '0';
            if cnt_1ms_period < count_compare then
                ledg0 <= '1';
            elsif cnt_1ms_period = c_period_time then
                count_compare <= c_compare * duty_cycle;
            end if;
        end if;

        if reset_2r = '1' then
            ledg0 <= '0';
            count_compare <= 0;
        end if;
    end process p_pwm_generation;

end architecture;
