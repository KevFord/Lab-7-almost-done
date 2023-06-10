library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
library work;

entity serial_ctrl is
port(
    -- Outputs
        serial_on           : out std_logic := '0'; -- Pulsed high when the input is x"31"
        serial_off          : out std_logic := '0'; -- Pulsed high when the input is x"30"
        serial_up           : out std_logic := '0'; -- Pulsed high when the input is x"55" or x"75"
        serial_down         : out std_logic := '0'; -- Pulsed high when the input is x"64" or x"44"
    -- Inputs
        clk_50              : in std_logic; -- 50 MHz clock
		reset				: in std_logic; -- Active high
        received_data_valid : in std_logic; -- Pulsed high one clock cycle
        received_data       : in std_logic_vector(7 downto 0) -- An ASCII char, either u/U, d/D, 1 or 0
);
end entity serial_ctrl;
 
architecture rtl of serial_ctrl is

    type t_output_state is (
		s_out_pulse, -- Pulse one of the ouputs based on the last valid input.
		s_out_idle -- Wait for a valid input, make a local copy of input then go to the pulse state.
	);
	signal output_state			: t_output_state := s_out_idle;

    signal reset_1r     : std_logic := '0';
    signal reset_2r     : std_logic := '0';

    signal received_data_cpy    : std_logic_vector(7 downto 0) := (others => '0');

    signal pulse_flag           : std_logic := '0';

begin

-- Sync inputs
    p_sync_inputs       : process(clk_50) is
    begin
        if rising_edge(clk_50) then
            reset_1r    <= reset;
            reset_2r    <= reset_1r;    
        end if;
    end process p_sync_inputs;

    p_output_control		: process(clk_50, reset) is
        begin
            if rising_edge(clk_50) then
                -- Default output assignments
                serial_down	<= '0';
                serial_off	<= '0';
                serial_on	<= '0';
                serial_up	<= '0';
            
                case output_state is
                    when s_out_idle	=> -- Wait for, and then copy, a valid input from the UART component.
                        if received_data_valid = '1' then
                            received_data_cpy <= received_data; -- Create a local copy of the latest valid input.
                            output_state <= s_out_pulse;
                        end if;
                    
                    when s_out_pulse => -- Check what the last valid input was and set outputs accordingly.
                        if pulse_flag = '1' then
                            case received_data_cpy is
                                when x"30" =>			-- Off
                                    serial_off <= '1';
    
                                when x"31" =>			-- On
                                    serial_on <= '1';
    
                                when x"75" | x"55" =>	-- Up
                                    serial_up <= '1';
    
                                when x"64" | x"44" =>	-- Down
                                    serial_down <= '1';
    
                                when others =>
                                    null; -- Do nothing
                            end case;
                            output_state <= s_out_idle; -- Go back to waiting for a valid input.
                        else
                        pulse_flag <=  '1';
                        end if;
                end case;
            end if;
    
            if reset_2r = '1' then
                serial_down	<= '0';
                serial_off	<= '0';
                serial_on	<= '0';
                serial_up	<= '0';

                pulse_flag <= '0';
            end if;
    
        end process p_output_control;
end architecture;