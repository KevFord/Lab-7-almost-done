library ieee;
    use ieee.numeric_std.all;
    use ieee.std_logic_1164.all;

entity dc_disp is
port (
        clk_50              : in std_logic;
        reset               : in std_logic := '0';
        transmit_ready      : in std_logic := '0';
    -- /////// D //////
        current_dc          : in std_logic_vector(7 downto 0) := (others => '0');
        current_dc_update   : in std_logic := '0';

    -- ////// E ///////
        transmit_data       : out std_logic_vector(7 downto 0);-- := (others => '0');
        transmit_valid      : out std_logic := '0';

    -- Ouputs   
        hex0                : out std_logic_vector(6 downto 0) := (others => '1');
        hex1                : out std_logic_vector(6 downto 0) := (others => '1');
        hex2                : out std_logic_vector(6 downto 0) := "1000000"
);
end entity dc_disp;

architecture rtl of dc_disp is

    type t_7seg_number is array(0 to 10) of std_logic_vector(6 downto 0);
    constant c_7seg_number      : t_7seg_number := (
        "1000000", -- 0
        "1111001", -- 1
        "0100100", -- 2
        "0110000", -- 3
        "0011001", -- 4
        "0010010", -- 5
        "0000010", -- 6
        "1111000", -- 7
        "0000000", -- 8
        "0011000", -- 9
        "1111111"  -- Blank
    );

    type t_ascii_values is array(0 to 12) of std_logic_vector(7 downto 0);
    constant c_ascii_values     : t_ascii_values := (
        x"30", -- 0
        x"31", -- 1
        x"32", -- 2
        x"33",
        x"34",
        x"35",
        x"36",
        x"37",
        x"38",
        x"39", -- 9
        x"20", -- Space
        x"25", -- %
        x"0d"  -- Carrage Return
    );

    type t_bcd_transform_step is (
        s_bcd_ready,
        s_bcd_busy,
        s_bcd_valid_out,
        s_bcd_reset
    );
    signal bcd_transform_step   : t_bcd_transform_step := s_bcd_ready;

    type t_subtraction_step is (
        s_sub_idle,
        s_sub_hundreds,
        s_sub_tens,
        s_sub_ones,
        s_sub_done
    );
    signal subtraction_step     : t_subtraction_step := s_sub_idle;

    type t_output_result_step is (
        s_output_idle,
        s_output_hundreds, 
        s_output_tens,
        s_output_ones,
        s_output_percent,
        s_output_carrage,
        s_output_reset
    );
    signal output_result_step   : t_output_result_step := s_output_idle;

    signal dc_in                : integer range 0 to 100 := 0; -- A local copy of the last valid duty cycle.

    signal new_dc_in            : unsigned(7 downto 0) := (others => '1');
    signal new_dc_flag          : std_logic := '0';
    signal new_dc_update        : std_logic := '0';

    signal dc_hundred           : integer range 0 to 1 := 0; -- Will hold the number in the relevant location. 
    signal dc_tens              : integer range 0 to 9 := 0; -- Will hold the number in the relevant location.
    signal dc_ones              : integer range 0 to 9 := 0; -- Will hold the number in the relevant location.

    signal dc_hundred_cpy       : integer range 0 to 1 := 0;
    signal dc_tens_cpy          : integer range 0 to 9 := 0;
    signal dc_ones_cpy          : integer range 0 to 9 := 0;

    signal reset_1r             : std_logic := '0';
    signal reset_2r             : std_logic := '0';

    signal transmit_flag        : std_logic := '0'; -- A flag which is set once the BCD transform is done. When this flag is '1' the 
                                                    -- p_transmit_result process will make a copy of the dc_* values and transmit each as
                                                    -- a ascii byte to the uart component.
    
    signal transmit_valid_delay : std_logic := '0';

    signal output_reset_valid_cnt   : integer range 0 to 5 := 0;

    constant c_7seg_blank       : integer := 10;

    signal reset_flag           : std_logic := '1'; -- Ensure the first reset signal is handled properly

begin

-- Sync inputs
    p_sync_inputs       : process(clk_50) is
        begin
            if rising_edge(clk_50) then
                reset_1r    <= reset;
                reset_2r    <= reset_1r;    
            end if;
    end process p_sync_inputs;

    -- Detetct dc updates, store the current and possibly new dc values. Set a flag to the other processes to begin transforming data.
    p_dc_update_controller      : process(clk_50, reset_2r) is
    begin
        if rising_edge(clk_50) then
            new_dc_update <= '0';
            if current_dc_update = '1' and output_result_step /= s_output_idle then
                new_dc_in <= unsigned(current_dc);
                new_dc_update <= '1';
            elsif new_dc_flag = '1' then
                new_dc_update <= '0';
            end if;
        end if;
    end process p_dc_update_controller;

    p_bcd_decode                : process(clk_50, reset_2r) is -- Largely the same logic as used in Lab 6.
    begin
        if rising_edge(clk_50) then
            transmit_flag <= '0';

            case bcd_transform_step is
                when s_bcd_ready =>
                    --current_dc_update <= '0'; -- Reset the update flag.
                    if new_dc_update = '1' then
                        dc_in <= to_integer(unsigned(new_dc_in));
                        bcd_transform_step <= s_bcd_busy;
                    elsif current_dc_update = '1' and new_dc_update = '0' then
                        dc_in <= to_integer(unsigned(current_dc)); -- Take the input DC and cast it to unsigned for use in calcs later.
                        bcd_transform_step <= s_bcd_busy;
                    end if;

                when s_bcd_busy =>
                    case subtraction_step is

                        when s_sub_idle => -- May be unessecary(?)
                            transmit_flag <= '0';
                            subtraction_step <= s_sub_hundreds;
                            dc_hundred      <= 0;
                            dc_tens         <= 0;
                            dc_ones         <= 0;

                        when s_sub_hundreds =>
                            if dc_in = 100 then -- DC is 100%
                                dc_hundred  <= 1;
                                dc_tens     <= 0;
                                dc_ones     <= 0;
                            -- Subtract 100, probably excessive but cant hurt...
                                dc_in       <= dc_in - 100;
                            -- Set the ouputs, since there is only one case where the DC will be 100 no need to do the remaining calculations.
                                hex2        <= c_7seg_number(1);
                                hex1        <= c_7seg_number(0);
                                hex0        <= c_7seg_number(0);
                                subtraction_step <= s_sub_done;
                            else 
                                hex2 <= c_7seg_number(0);
                                subtraction_step <= s_sub_tens;
                                dc_hundred  <= 0;
                            end if;
                        
                        when s_sub_tens =>
                            if dc_in > 9 then
                                dc_tens <= dc_tens + 1;
                                dc_in   <= dc_in - 10;
                            else 
                                hex1 <= c_7seg_number(dc_tens);
                                subtraction_step <= s_sub_ones;
                            end if;
                        
                        when s_sub_ones => 
                            if dc_in > 0 then
                                dc_ones <= dc_ones + 1;
                                dc_in   <= dc_in - 1;
                            else 
                                hex0 <= c_7seg_number(dc_ones);
                                subtraction_step <= s_sub_done;
                            end if;

                        when s_sub_done =>
                            subtraction_step <= s_sub_idle;
                            bcd_transform_step <= s_bcd_valid_out;
                    end case;
                
                when s_bcd_valid_out => -- Transmit the results to serial_ctrl module and reset counters.
                    
                    transmit_flag <= '1';
                    bcd_transform_step <= s_bcd_ready;

                when s_bcd_reset =>
                    transmit_flag <= '0';
                    dc_hundred          <= 0;
                    dc_tens             <= 0;
                    dc_ones             <= 0;

                    hex0        <= c_7seg_number(0);--c_7seg_blank);
                    hex1        <= c_7seg_number(0);--c_7seg_blank);
                    hex2        <= c_7seg_number(0);

                    if reset_2r = '0' then
                        bcd_transform_step <= s_bcd_ready;
                    end if;
            end case;
        end if;

        if reset_2r = '1' then
            bcd_transform_step <= s_bcd_reset;
        end if;
    end process p_bcd_decode;

    p_transmit_results  : process(clk_50, reset_2r) is
    begin
        if rising_edge(clk_50) then
            transmit_valid <= '0';
            transmit_data <= c_ascii_values(0);
            --new_dc_flag <= '0';

            if transmit_ready = '1' then
                case output_result_step is
                    when s_output_idle =>
                        --transmit_data <= c_ascii_values(10); -- Space
                        if transmit_flag = '1' then
                            dc_hundred_cpy  <= dc_hundred;
                            dc_tens_cpy     <= dc_tens;
                            dc_ones_cpy     <= dc_ones;
                            output_result_step <= s_output_hundreds;
                        end if;
                        
                    when s_output_hundreds =>
                        if dc_hundred_cpy = 1 then
                            transmit_data <= x"31";
                        else 
                            transmit_data <= c_ascii_values(10); -- Space
                        end if;
                        if transmit_valid_delay = '1' then
                            transmit_valid      <= '1';
                            output_result_step  <= s_output_tens;
                            transmit_valid_delay <= '0';
                        else
                            transmit_valid_delay <= '1'; 
                        end if;
                        
                    when s_output_tens =>
                        if dc_tens_cpy < 1 and dc_hundred_cpy = 1 then
                            transmit_data <= c_ascii_values(0);
                        elsif dc_tens_cpy < 1 then
                            transmit_data <= c_ascii_values(10); -- Space
                        else
                            transmit_data <= c_ascii_values(dc_tens_cpy);
                        end if;
                        if transmit_valid_delay = '1' then
                            transmit_valid      <= '1';
                            output_result_step  <= s_output_ones;
                            transmit_valid_delay <= '0';
                        else 
                            transmit_valid_delay <= '1';
                        end if;
                        
                    when s_output_ones =>
                        if dc_ones_cpy < 1 and dc_hundred_cpy = 1 then -- If the duty cycle is 100%
                            transmit_data <= c_ascii_values(0);
                        elsif dc_ones_cpy < 1 and dc_tens_cpy /= 0 then -- If the duty cycle is less than 100% but greater than 9
                            transmit_data <= c_ascii_values(0);
                        elsif dc_ones_cpy > 0 then -- If duty cycle is less than 10
                            transmit_data <= c_ascii_values(dc_ones_cpy);
                        --else 
                        --    transmit_data <= x"20"; -- Should not be reached
                        end if;
                        
                        if transmit_valid_delay = '1' then
                            transmit_valid      <= '1';
                            output_result_step  <= s_output_percent;
                            transmit_valid_delay <= '0';
                        else
                            transmit_valid_delay <= '1';
                        end if;
                        
                    when s_output_percent =>
                        transmit_data       <= c_ascii_values(11); -- %
                        if transmit_valid_delay = '1' then
                            transmit_valid      <= '1';
                            output_result_step  <= s_output_carrage;
                            transmit_valid_delay <= '0';
                        else 
                            transmit_valid_delay <= '1';
                        end if;
                        
                    when s_output_carrage =>
                        transmit_data       <= c_ascii_values(12); -- CR
                    -- Check if the values that were output in this run match the current values. If they dont, the dc has changed while
                    -- we were outputting the previous dc. Start a new transmision.
                        if dc_hundred_cpy /= dc_hundred or dc_tens_cpy /= dc_tens or dc_ones_cpy /= dc_ones then
                            dc_hundred_cpy  <= dc_hundred;
                            dc_tens_cpy     <= dc_tens;
                            dc_ones_cpy     <= dc_ones;
                            output_result_step <= s_output_hundreds;
                        elsif transmit_valid_delay = '1' then
                            transmit_valid      <= '1';
                            output_result_step  <= s_output_idle;
                            new_dc_flag <= '1';
                            transmit_valid_delay <= '0';
                        else
                            transmit_valid_delay <= '1';
                        end if; 
                        
                    when s_output_reset => -- Send 5 bytes via uart. space, space, ascii 0, ascii %, ascii carrage return
                        if reset_flag = '1' then
                            if transmit_ready = '1' then
                                case output_reset_valid_cnt is
                                    when 0 => -- Set output to ascii space and pulse transmit_valid
                                        transmit_data <= c_ascii_values(0);
                                        if transmit_valid_delay = '1' then
                                            transmit_valid      <= '1';
                                            --output_result_step  <= s_output_percent;
                                            transmit_valid_delay <= '0';
                                            output_reset_valid_cnt <= output_reset_valid_cnt + 1;
                                        else
                                            transmit_valid_delay <= '1';
                                        end if;
                                    when 1 => -- Keep output at ascii space and pulse transmit_valid again
                                        transmit_data <= c_ascii_values(0);
                                        if transmit_valid_delay = '1' then
                                            transmit_valid      <= '1';
                                            --output_result_step  <= s_output_percent;
                                            transmit_valid_delay <= '0';
                                            output_reset_valid_cnt <= output_reset_valid_cnt + 1;
                                        else
                                            transmit_valid_delay <= '1';
                                        end if;
                                    when 2 => -- Set output to ascii 0, pulse transmit_valid
                                        transmit_data <= c_ascii_values(0);
                                        if transmit_valid_delay = '1' then
                                            transmit_valid      <= '1';
                                            --output_result_step  <= s_output_percent;
                                            transmit_valid_delay <= '0';
                                            output_reset_valid_cnt <= output_reset_valid_cnt + 1;
                                        else
                                            transmit_valid_delay <= '1';
                                        end if;
                                    when 3 => -- Output a ascii %, pulse transmit_valid
                                        transmit_data <= c_ascii_values(11);
                                        if transmit_valid_delay = '1' then
                                            transmit_valid      <= '1';
                                            --output_result_step  <= s_output_percent;
                                            transmit_valid_delay <= '0';
                                            output_reset_valid_cnt <= output_reset_valid_cnt + 1;
                                        else
                                            transmit_valid_delay <= '1';
                                        end if;
                                    when 4 => -- Finally output ascii carrage return and pulse
                                        transmit_data <= c_ascii_values(12);
                                        if transmit_valid_delay = '1' then
                                            transmit_valid      <= '1';
                                            output_result_step  <= s_output_idle;
                                            transmit_valid_delay <= '0';
                                            output_reset_valid_cnt <= output_reset_valid_cnt + 1;
                                        else
                                            transmit_valid_delay <= '1';
                                        end if;
                                    when 5 => 
                                        reset_flag <= '0';
                                        new_dc_flag <= '1';
                                        output_reset_valid_cnt <= 0;
                                    when others => -- Do nothing
                                        null;
                                end case;
                            end if;
                        end if;
                        
                        if reset_2r = '0' then
                            reset_flag <= '1';
                            output_result_step <= s_output_idle;
                        end if;
                        
                    when others =>
                        null;
                end case;
            end if;
        end if;

        if reset_2r = '1' then 
            output_result_step <= s_output_reset;
        end if;
    end process p_transmit_results;
end architecture;