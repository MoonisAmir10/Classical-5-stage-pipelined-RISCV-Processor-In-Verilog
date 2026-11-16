create_clock -name clk -period 10.0 [get_ports clk]
set_input_delay  1.5 -clock clk [get_ports {rst en}]
set_output_delay 1.5 -clock clk [get_ports q*]
