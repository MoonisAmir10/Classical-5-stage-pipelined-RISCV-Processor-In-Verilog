read_liberty /home/moonis/auto_job_seeker/.eda_tools/pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_verilog /home/moonis/auto_job_seeker/projects/riscv-soc-dft/smoke_test/build/counter4_synth.v
link_design counter4
read_sdc /home/moonis/auto_job_seeker/projects/riscv-soc-dft/smoke_test/counter4.sdc
report_checks -path_delay min_max -format full_clock_expanded
write_sdf /home/moonis/auto_job_seeker/projects/riscv-soc-dft/smoke_test/build/counter4.sdf
exit
