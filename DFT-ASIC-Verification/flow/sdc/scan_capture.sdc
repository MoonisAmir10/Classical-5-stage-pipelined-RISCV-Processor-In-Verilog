# Scan-Capture Mode SDC — At-Speed 100 MHz Launch-on-Capture Window
create_clock -name sys_clk -period 10.0 [get_ports sys_clk]
create_clock -name tck     -period 100.0 [get_ports tck]
set_propagated_clock [all_clocks]

set_clock_uncertainty -setup 0.25 [get_clocks sys_clk]
set_clock_uncertainty -hold  0.05 [get_clocks sys_clk]
set_clock_uncertainty -setup 0.50 [get_clocks tck]
set_clock_uncertainty -hold  0.10 [get_clocks tck]

# Case analysis: test_mode=1, scan_en=0, OCC mux open for sys_clk 2-pulse LOC burst
set_case_analysis 1 [get_ports test_mode]
set_case_analysis 0 [get_ports scan_en]
set_case_analysis 1 [get_pins u_occ_clk_ctrl/test_mode]
set_case_analysis 0 [get_pins u_occ_clk_ctrl/mbist_active]
set_case_analysis 0 [get_pins u_occ_clk_ctrl/occ_bypass]
set_case_analysis 0 [get_pins u_occ_clk_ctrl/_46_/Q]
set_case_analysis 0 [get_pins u_occ_clk_ctrl/_47_/Q]

set_clock_groups -physically_exclusive -group {sys_clk} -group {tck}

# Slow static JTAG TDR outputs driving capture configuration receive multicycle relaxation
set_multicycle_path -setup 4 -from [get_clocks tck]
set_multicycle_path -hold  3 -from [get_clocks tck]

set_false_path -from [get_ports {sys_rst_n trst_n test_mode scan_en scan_in[*]}]
set_false_path -to   [get_ports {scan_out[*] tdo tdo_en}]

set_input_delay  1.5 -clock sys_clk [get_ports {prog_sel cache_cpu_wdata[*] cache_addr_cpu[*] cache_rd_cpu cache_wr_cpu cache_mem_rdata[*] cache_ready_mem}]
set_output_delay 1.5 -clock sys_clk [get_ports {x14[*] pc_obs[*] alu_obs[*] cache_cpu_rdata[*] cache_cpu_rdata_oe cache_stall_cpu cache_mem_wdata[*] cache_mem_wdata_oe cache_addr_mem[*] cache_rd_mem cache_wr_mem bist_done bist_fail}]
