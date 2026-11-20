# Scan-Shift Mode SDC — 10 MHz TCK Shifting Through Balanced 8-Chain + Compactor
create_clock -name tck     -period 100.0 [get_ports tck]
create_clock -name sys_clk -period 10.0  [get_ports sys_clk]
set_propagated_clock [all_clocks]

set_clock_uncertainty -setup 0.50 [get_clocks tck]
set_clock_uncertainty -hold  0.15 [get_clocks tck]

# Case analysis: force OCC mux onto TCK shift domain (sys_clk gated off)
set_case_analysis 1 [get_ports test_mode]
set_case_analysis 1 [get_ports scan_en]
set_case_analysis 1 [get_pins u_occ_clk_ctrl/test_mode]
set_case_analysis 0 [get_pins u_occ_clk_ctrl/mbist_active]
set_case_analysis 0 [get_pins u_occ_clk_ctrl/occ_bypass]
set_case_analysis 1 [get_pins u_occ_clk_ctrl/_46_/Q]
set_case_analysis 1 [get_pins u_occ_clk_ctrl/_47_/Q]

set_clock_groups -physically_exclusive -group {tck} -group {sys_clk}

# Static async resets, SRAM standby ports, and functional I/O pins are false during serial scan shift
set_false_path -from [get_cells u_*_ram_*]
set_false_path -to   [get_cells u_*_ram_*]
set_false_path -from [get_ports {sys_rst_n trst_n test_mode scan_en prog_sel cache_mem_rdata[*] cache_ready_mem}]
set_false_path -to   [get_ports {x14[*] pc_obs[*] alu_obs[*] cache_mem_wdata[*] cache_addr_mem[*] cache_rd_mem cache_wr_mem cache_stall_cpu cache_hit cache_miss cache_wb bist_done bist_fail}]

# Scan & JTAG shift I/O constraints
set_input_delay  5.0 -clock tck [get_ports {scan_in[*] tms tdi}]
set_output_delay 5.0 -clock tck [get_ports {scan_out[*] tdo tdo_en}]
