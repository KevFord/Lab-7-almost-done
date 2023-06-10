-- ////////////////////////////////////////////
-- Key control component for lab 7
-- Author: Kevin Fordal
-- Version 2
--
-- From specifications:
--      "The Key ctrl component shall double synchronize the active low key inputs.
--       The outputs from the compoent shall be set high one clock cycle if the inputs are detected to be low. If
--       the inputs are held low the outputs shall be pulsed high one clock cycle every 10th millisecond.
--       The key_n input vector shall be mapped to the outputs in the following way:
--       key_n(0) shall control key_off output
--       key_n(1) shall control key_on output
--       key_n(2) shall control key_down output
--       key_n(3) shall control key_up output
--       Key_n input bits 3, 2 and 1 shall be ignored if key_n(0) is pushed down.
--       No pulses on key_up or key_down shall be generated if both key_n(2) and key_n(3) is pushed down
--       simultaneously."
--
-- ////////////////////////////////////////////
library ieee;
    use ieee.numeric_std.all;
    use ieee.std_logic_1164.all;

entity key_ctrl is
port (
        clk_50      : in std_logic;
        reset       : in std_logic; -- Active high.
        key_n       : in std_logic_vector(3 downto 0); -- 4 active low buttons.

    -- Outputs
        key_on      : out std_logic;
        key_off     : out std_logic;
        key_up      : out std_logic;
        key_down    : out std_logic
);
end entity key_ctrl;

architecture rtl of key_ctrl is

    type t_output_step is (
        s_delay,
        s_idle
    );
    signal output_step          : t_output_step := s_idle;

    signal key_n_1r : std_logic_vector(3 downto 0) := (others => '1');
    signal key_n_2r : std_logic_vector(3 downto 0) := (others => '1');

    signal reset_1r : std_logic := '0';
    signal reset_2r : std_logic := '0';

    signal cnt_10ms         : unsigned(18 downto 0) := (others => '0'); -- 500 000 clock cycles. 19 bit = 524k
    constant c_cnt_10ms_max : unsigned(18 downto 0) := to_unsigned(500000, cnt_10ms'length); -- 500 000.

    signal cnt_10ms_sim         : unsigned(18 downto 0) := (others => '0'); -- 500 000 clock cycles. 19 bit = 524k
    constant c_cnt_10ms_max_sim : unsigned(18 downto 0) := to_unsigned(50, cnt_10ms'length); -- 50.

begin

-- Sync inputs
    p_sync_inputs       : process(clk_50) is
       begin
           if rising_edge(clk_50) then
               key_n_1r  <= key_n;
               key_n_2r  <= key_n_1r;

               reset_1r    <= reset;
               reset_2r    <= reset_1r;    
           end if;
    end process p_sync_inputs;

-- Check inputs
    p_check_inputs      : process(clk_50, reset_2r) is
    begin
        if rising_edge(clk_50) then
            key_down    <= '0';
            key_up      <= '0';
            key_on      <= '0';
            key_off     <= '0';

            case output_step is 
                when s_idle => 
                    case key_n_2r is

                        when x"d" => -- key_n(1): on
                            key_on <= '1';
                            output_step <= s_delay;

                        when x"b" => -- key_n(2): down
                            if key_n_2r /= x"7" then
                                key_down <= '1';
                                output_step <= s_delay;
                            end if;

                        when x"7" => -- key_n(3): up
                            if key_n_2r /= x"b" then
                                key_up <= '1';
                                output_step <= s_delay;
                            end if;

                        when x"e" => -- key_n(0): off
                            key_off <= '1';
                            output_step <= s_delay;
                        
                        when others =>
                            null;
                    end case;

                when s_delay =>
                    if key_n_2r = x"f" then -- Wait for all keys to be released
                        output_step <= s_idle;
                        cnt_10ms <= (others => '0'); -- Reset counter
                    elsif cnt_10ms = c_cnt_10ms_max then -- Wait untill the 10 ms delay
                        output_step <= s_idle;
                        cnt_10ms <= (others => '0'); -- Reset counter
                    else 
                        cnt_10ms <= cnt_10ms + 1;
                    end if;

                when others => 
                    null;
            end case;
        end if;

        if reset_2r = '1' then
            output_step <= s_idle;
        end if;
    end process p_check_inputs;

-- Counter process
    p_counter       : process(clk_50, reset_2r) is
    begin
        if rising_edge(clk_50) then
            cnt_10ms_sim <= cnt_10ms_sim + 1;
            if cnt_10ms_sim = c_cnt_10ms_max_sim then
                cnt_10ms_sim <= (others => '0');
            end if;
        end if;

        if reset_2r = '1' then
            cnt_10ms_sim <= (others => '0');
        end if;
    end process p_counter;
end architecture rtl;