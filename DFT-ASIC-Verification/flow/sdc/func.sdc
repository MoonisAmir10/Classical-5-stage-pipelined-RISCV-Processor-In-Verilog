# Functional Mode SDC — RV32I + Integrated 2-Way Cache SoC (100 MHz Nominal/Signoff)
create_clock -name sys_clk -period 10.0 [get_ports sys_clk]
create_clock -name tck     -period 100.0 [get_ports tck]
set_propagated_clock [all_clocks]

set_clock_uncertainty -setup 0.25 [get_clocks sys_clk]
set_clock_uncertainty -hold  0.05 [get_clocks sys_clk]
set_clock_uncertainty -setup 0.50 [get_clocks tck]
set_clock_uncertainty -hold  0.10 [get_clocks tck]

# Mode case analysis: disable DFT shift/capture controls in FUNC mode
set_case_analysis 0 [get_ports test_mode]
set_case_analysis 0 [get_ports scan_en]
set_case_analysis 0 [get_pins u_occ_clk_ctrl/test_mode]
set_case_analysis 0 [get_pins u_occ_clk_ctrl/_46_/Q]
set_case_analysis 0 [get_pins u_occ_clk_ctrl/_47_/Q]

set_clock_groups -physically_exclusive -group {sys_clk} -group {tck}

# Asynchronous resets and static DFT test pins are false paths in functional mode
set_false_path -from [get_ports {sys_rst_n trst_n test_mode scan_en scan_in[*] tms tdi}]
set_false_path -to   [get_ports {scan_out[*] tdo tdo_en}]

# Functional I/O boundary timing
set_input_delay  1.5 -clock sys_clk [get_ports {prog_sel cache_mem_rdata[*] cache_ready_mem}]
set_output_delay 1.5 -clock sys_clk [get_ports {x14[*] pc_obs[*] alu_obs[*] cache_mem_wdata[*] cache_addr_mem[*] cache_rd_mem cache_wr_mem cache_stall_cpu cache_hit cache_miss cache_wb bist_done bist_fail}]
