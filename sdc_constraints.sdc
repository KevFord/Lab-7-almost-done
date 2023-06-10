create_clock -name tc_clock_50 -period 20 [get_ports clock_50]
derive_pll_clocks
set_output_delay -clock clock_50 -max 8 [get_ports *]
set_input_delay -clock clock_50 -min 8 [get_ports *]

