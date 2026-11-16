read_liberty /home/moonis/auto_job_seeker/.eda_tools/pdk/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib
read_verilog /home/moonis/auto_job_seeker/projects/riscv-soc-dft/smoke_test/build/counter4_ihp_synth.v
link_design counter4
read_sdc /home/moonis/auto_job_seeker/projects/riscv-soc-dft/smoke_test/counter4.sdc
report_checks -path_delay min_max
write_sdf -include_typ /home/moonis/auto_job_seeker/projects/riscv-soc-dft/smoke_test/build/counter4_ihp.sdf
exit
