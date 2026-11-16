EDA_BIN := /home/moonis/auto_job_seeker/.eda_tools/envs/dft/bin
IVERILOG := $(EDA_BIN)/iverilog
VVP := $(EDA_BIN)/vvp
VERILATOR := $(EDA_BIN)/verilator
YOSYS := $(EDA_BIN)/yosys
STA := /home/moonis/auto_job_seeker/.eda_tools/opensta/bin/sta

RTL_CORE := $(wildcard rtl/core/rv32i_*.v)
RTL_CACHE := rtl/mem/sram_sync_sp.v rtl/core/cache_ctrl_logic.v rtl/core/cache_2wsa_dft.v
RTL_DFT := rtl/dft/jtag_tap.sv rtl/dft/ieee1500_wrapper.sv rtl/dft/mbist_ctrl.sv rtl/dft/occ_clk_ctrl.sv rtl/dft/scan_comp_wrap.sv
RTL_SOC := $(RTL_CORE) $(RTL_CACHE) $(RTL_DFT) rtl/top/soc_dft_top.sv
V_FLAGS := --assert -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM --timescale 1ns/1ps -j 2
V_LINT := --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM
BUILD_DIR := build

.PHONY: all lint test-unit test-dft test-dv test-cocotb synth-baseline synth-soc synth-scan test-scan-gls atpg-sweep sta test-sdf-gls test-dbg-studies metrics schematics fpga-metrics clean

all: lint test-unit test-dft test-dv test-cocotb synth-baseline synth-soc synth-scan test-scan-gls atpg-sweep sta test-sdf-gls test-dbg-studies metrics

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

lint:
	PATH=$(EDA_BIN):/usr/bin:/bin $(VERILATOR) $(V_LINT) $(RTL_CORE)
	PATH=$(EDA_BIN):/usr/bin:/bin $(VERILATOR) $(V_LINT) $(RTL_CACHE)
	@for f in $(RTL_DFT); do \
		PATH=$(EDA_BIN):/usr/bin:/bin $(VERILATOR) $(V_LINT) $$f || exit 1; \
	done
	PATH=$(EDA_BIN):/usr/bin:/bin $(VERILATOR) $(V_LINT) --top-module soc_dft_top $(RTL_SOC)

test-unit: $(BUILD_DIR)
	$(IVERILOG) -g2012 -o $(BUILD_DIR)/tb_rv32i.vvp $(RTL_CORE) tb/unit/tb_rv32i_baseline.sv
	$(VVP) $(BUILD_DIR)/tb_rv32i.vvp
	$(IVERILOG) -g2012 -o $(BUILD_DIR)/tb_cache.vvp $(RTL_CACHE) tb/unit/tb_cache_baseline.sv
	$(VVP) $(BUILD_DIR)/tb_cache.vvp
	PATH=$(EDA_BIN):/usr/bin:/bin $(VERILATOR) --binary $(V_FLAGS) --Mdir $(BUILD_DIR)/obj_rv32i $(RTL_CORE) tb/unit/tb_rv32i_baseline.sv -o Vtb_rv32i
	$(BUILD_DIR)/obj_rv32i/Vtb_rv32i
	PATH=$(EDA_BIN):/usr/bin:/bin $(VERILATOR) --binary $(V_FLAGS) --Mdir $(BUILD_DIR)/obj_cache $(RTL_CACHE) tb/unit/tb_cache_baseline.sv -o Vtb_cache
	$(BUILD_DIR)/obj_cache/Vtb_cache

test-dft: $(BUILD_DIR)
	$(IVERILOG) -g2012 -o $(BUILD_DIR)/tb_jtag_tap.vvp rtl/dft/jtag_tap.sv tb/unit/tb_jtag_tap.sv
	$(VVP) $(BUILD_DIR)/tb_jtag_tap.vvp
	$(IVERILOG) -g2012 -o $(BUILD_DIR)/tb_ieee1500.vvp $(RTL_CORE) rtl/dft/ieee1500_wrapper.sv tb/unit/tb_ieee1500_wrapper.sv
	$(VVP) $(BUILD_DIR)/tb_ieee1500.vvp
	$(IVERILOG) -g2012 -o $(BUILD_DIR)/tb_mbist.vvp $(RTL_CACHE) rtl/dft/mbist_ctrl.sv tb/unit/tb_mbist_ctrl.sv
	$(VVP) $(BUILD_DIR)/tb_mbist.vvp
	$(IVERILOG) -g2012 -o $(BUILD_DIR)/tb_occ_scan.vvp rtl/dft/occ_clk_ctrl.sv rtl/dft/scan_comp_wrap.sv tb/unit/tb_occ_scan_comp.sv
	$(VVP) $(BUILD_DIR)/tb_occ_scan.vvp
	$(IVERILOG) -g2012 -o $(BUILD_DIR)/tb_soc_top.vvp $(RTL_SOC) tb/unit/tb_soc_dft_top.sv
	$(VVP) $(BUILD_DIR)/tb_soc_top.vvp
	PATH=$(EDA_BIN):/usr/bin:/bin $(VERILATOR) --binary $(V_FLAGS) --Mdir $(BUILD_DIR)/obj_jtag rtl/dft/jtag_tap.sv tb/unit/tb_jtag_tap.sv -o Vtb_jtag
	$(BUILD_DIR)/obj_jtag/Vtb_jtag
	PATH=$(EDA_BIN):/usr/bin:/bin $(VERILATOR) --binary $(V_FLAGS) --Mdir $(BUILD_DIR)/obj_ieee1500 $(RTL_CORE) rtl/dft/ieee1500_wrapper.sv tb/unit/tb_ieee1500_wrapper.sv -o Vtb_ieee1500
	$(BUILD_DIR)/obj_ieee1500/Vtb_ieee1500
	PATH=$(EDA_BIN):/usr/bin:/bin $(VERILATOR) --binary $(V_FLAGS) --Mdir $(BUILD_DIR)/obj_mbist $(RTL_CACHE) rtl/dft/mbist_ctrl.sv tb/unit/tb_mbist_ctrl.sv -o Vtb_mbist
	$(BUILD_DIR)/obj_mbist/Vtb_mbist
	PATH=$(EDA_BIN):/usr/bin:/bin $(VERILATOR) --binary $(V_FLAGS) --Mdir $(BUILD_DIR)/obj_occ_scan rtl/dft/occ_clk_ctrl.sv rtl/dft/scan_comp_wrap.sv tb/unit/tb_occ_scan_comp.sv -o Vtb_occ_scan
	$(BUILD_DIR)/obj_occ_scan/Vtb_occ_scan
	PATH=$(EDA_BIN):/usr/bin:/bin $(VERILATOR) --binary $(V_FLAGS) --Mdir $(BUILD_DIR)/obj_soc_top $(RTL_SOC) tb/unit/tb_soc_dft_top.sv -o Vtb_soc_top
	$(BUILD_DIR)/obj_soc_top/Vtb_soc_top

test-dv: $(BUILD_DIR)
	PATH=$(EDA_BIN):/usr/bin:/bin $(VERILATOR) --binary --coverage-line --coverage-toggle --coverage-user $(V_FLAGS) --Mdir $(BUILD_DIR)/obj_dv $(RTL_SOC) tb/sva/dft_sva_mon.sv tb/dv/tb_dft_dv_rand.sv -o Vtb_dv_rand
	$(BUILD_DIR)/obj_dv/Vtb_dv_rand +verilator+coverage+file+$(BUILD_DIR)/coverage_dv.dat
	PATH=$(EDA_BIN):/usr/bin:/bin python3 scripts/check_dv_coverage.py $(BUILD_DIR)/coverage_dv.dat --report $(BUILD_DIR)/coverage_report.txt --min-line 95 --min-toggle 95 --min-user 100

test-cocotb: $(BUILD_DIR)
	PATH=$(EDA_BIN):/usr/bin:/bin $(MAKE) -C tb/cocotb

synth-baseline: $(BUILD_DIR)
	$(YOSYS) -q -s flow/yosys/synth_rv32i_baseline.ys
	$(YOSYS) -q -s flow/yosys/synth_cache_baseline.ys

synth-soc: $(BUILD_DIR)
	$(YOSYS) -q -s flow/yosys/synth_soc_dft.ys

IHP_LIB_TYP  ?= /home/moonis/auto_job_seeker/.eda_tools/pdk/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib
IHP_BUNDLE_V ?= /home/moonis/auto_job_seeker/.eda_tools/pdk/ihp-sg13g2/libs.ref/sg13g2_stdcell/verilog/sg13g2_bundle.v
OPENSTA_BIN  := /home/moonis/auto_job_seeker/.eda_tools/opensta/bin

synth-scan: $(BUILD_DIR)
	PATH=$(EDA_BIN):/usr/bin:/bin IHP_LIB_TYP=$(IHP_LIB_TYP) python3 scripts/run_tradeoff_sweep.py --only-synth

test-scan-gls: synth-scan
	PATH=$(EDA_BIN):/usr/bin:/bin $(IVERILOG) -g2012 -Ttyp -P tb_scan_chain_generic.NUM_CHAINS=1 -o $(BUILD_DIR)/phase4/sim_scan1.vvp $(IHP_BUNDLE_V) rtl/mem/sram_sync_sp.v $(BUILD_DIR)/phase4/soc_func_scan1.v tb/gate/tb_scan_chain_generic.sv
	PATH=$(EDA_BIN):/usr/bin:/bin $(VVP) $(BUILD_DIR)/phase4/sim_scan1.vvp
	PATH=$(EDA_BIN):/usr/bin:/bin $(IVERILOG) -g2012 -Ttyp -P tb_scan_chain_generic.NUM_CHAINS=4 -o $(BUILD_DIR)/phase4/sim_scan4.vvp $(IHP_BUNDLE_V) rtl/mem/sram_sync_sp.v $(BUILD_DIR)/phase4/soc_func_scan4.v tb/gate/tb_scan_chain_generic.sv
	PATH=$(EDA_BIN):/usr/bin:/bin $(VVP) $(BUILD_DIR)/phase4/sim_scan4.vvp
	PATH=$(EDA_BIN):/usr/bin:/bin $(IVERILOG) -g2012 -Ttyp -P tb_scan_chain_generic.NUM_CHAINS=8 -o $(BUILD_DIR)/phase4/sim_scan8.vvp $(IHP_BUNDLE_V) rtl/mem/sram_sync_sp.v $(BUILD_DIR)/phase4/soc_func_scan8.v tb/gate/tb_scan_chain_generic.sv
	PATH=$(EDA_BIN):/usr/bin:/bin $(VVP) $(BUILD_DIR)/phase4/sim_scan8.vvp
	PATH=$(EDA_BIN):/usr/bin:/bin $(IVERILOG) -g2012 -DPOST_SCAN_STITCH -Ttyp -o $(BUILD_DIR)/phase4/sim_soc_scan8.vvp $(IHP_BUNDLE_V) rtl/mem/sram_sync_sp.v $(BUILD_DIR)/phase4/soc_func_scan8.v rtl/dft/jtag_tap.sv rtl/dft/ieee1500_wrapper.sv rtl/dft/mbist_ctrl.sv rtl/dft/occ_clk_ctrl.sv rtl/dft/scan_comp_wrap.sv rtl/top/soc_dft_top.sv tb/gate/tb_soc_scan8_gls.sv
	PATH=$(EDA_BIN):/usr/bin:/bin $(VVP) $(BUILD_DIR)/phase4/sim_soc_scan8.vvp

atpg-sweep: synth-scan
	PATH=$(EDA_BIN):/usr/bin:/bin IHP_LIB_TYP=$(IHP_LIB_TYP) python3 scripts/run_tradeoff_sweep.py --reuse-synth

sta: synth-scan
	PATH=$(OPENSTA_BIN):$(EDA_BIN):/usr/bin:/bin IHP_LIB_TYP=$(IHP_LIB_TYP) python3 scripts/run_phase5_sta.py

test-sdf-gls: sta
	PATH=$(EDA_BIN):/usr/bin:/bin bash -o pipefail -c '$(IVERILOG) -g2012 -gspecify -Tmax -o $(BUILD_DIR)/phase5/sim_soc_sdf_slow.vvp $(IHP_BUNDLE_V) rtl/mem/sram_sync_sp.v $(BUILD_DIR)/phase5/soc_dft_top_cts.v tb/gate/tb_soc_sdf_gls.sv 2>&1 | { grep -v "Timing checks" || test $$? -eq 1; }'
	PATH=$(EDA_BIN):/usr/bin:/bin bash -o pipefail -c '$(VVP) $(BUILD_DIR)/phase5/sim_soc_sdf_slow.vvp +SDF=$(BUILD_DIR)/phase5/soc_dft_top_slow.sdf +FAIL_LOG=reports/ate_sim_fail.log 2>&1 | { grep -v "Timing checks" || test $$? -eq 1; }'
	PATH=$(EDA_BIN):/usr/bin:/bin bash -o pipefail -c '$(IVERILOG) -g2012 -gspecify -Ttyp -o $(BUILD_DIR)/phase5/sim_soc_sdf_typ.vvp $(IHP_BUNDLE_V) rtl/mem/sram_sync_sp.v $(BUILD_DIR)/phase5/soc_dft_top_cts.v tb/gate/tb_soc_sdf_gls.sv 2>&1 | { grep -v "Timing checks" || test $$? -eq 1; }'
	PATH=$(EDA_BIN):/usr/bin:/bin bash -o pipefail -c '$(VVP) $(BUILD_DIR)/phase5/sim_soc_sdf_typ.vvp +SDF=$(BUILD_DIR)/phase5/soc_dft_top_typ.sdf +QUICK_CORNER 2>&1 | { grep -v "Timing checks" || test $$? -eq 1; }'
	PATH=$(EDA_BIN):/usr/bin:/bin bash -o pipefail -c '$(IVERILOG) -g2012 -gspecify -Tmin -o $(BUILD_DIR)/phase5/sim_soc_sdf_fast.vvp $(IHP_BUNDLE_V) rtl/mem/sram_sync_sp.v $(BUILD_DIR)/phase5/soc_dft_top_cts.v tb/gate/tb_soc_sdf_gls.sv 2>&1 | { grep -v "Timing checks" || test $$? -eq 1; }'
	PATH=$(EDA_BIN):/usr/bin:/bin bash -o pipefail -c '$(VVP) $(BUILD_DIR)/phase5/sim_soc_sdf_fast.vvp +SDF=$(BUILD_DIR)/phase5/soc_dft_top_fast.sdf +QUICK_CORNER 2>&1 | { grep -v "Timing checks" || test $$? -eq 1; }'

test-dbg-studies: test-sdf-gls
	PATH=$(EDA_BIN):/usr/bin:/bin bash -o pipefail -c '$(IVERILOG) -g2012 -gspecify -Tmin -o $(BUILD_DIR)/phase5/sim_dbg02_buggy.vvp $(IHP_BUNDLE_V) $(BUILD_DIR)/phase5/dbg02_buggy.v tb/gate/tb_dbg02_skew_hold.sv 2>&1 | { grep -v "Timing checks" || test $$? -eq 1; }'
	PATH=$(EDA_BIN):/usr/bin:/bin bash -o pipefail -c '$(VVP) $(BUILD_DIR)/phase5/sim_dbg02_buggy.vvp +SDF=$(BUILD_DIR)/phase5/dbg02_buggy_fast.sdf +EXPECT_HOLD_FAIL 2>&1 | { grep -v "Timing checks" || test $$? -eq 1; }'
	PATH=$(EDA_BIN):/usr/bin:/bin bash -o pipefail -c '$(IVERILOG) -g2012 -gspecify -Tmin -o $(BUILD_DIR)/phase5/sim_dbg02_fixed.vvp $(IHP_BUNDLE_V) $(BUILD_DIR)/phase5/dbg02_fixed.v tb/gate/tb_dbg02_skew_hold.sv 2>&1 | { grep -v "Timing checks" || test $$? -eq 1; }'
	PATH=$(EDA_BIN):/usr/bin:/bin bash -o pipefail -c '$(VVP) $(BUILD_DIR)/phase5/sim_dbg02_fixed.vvp +SDF=$(BUILD_DIR)/phase5/dbg02_fixed_fast.sdf 2>&1 | { grep -v "Timing checks" || test $$? -eq 1; }'
	PATH=$(EDA_BIN):/usr/bin:/bin python3 scripts/ate_fail_diag.py reports/ate_sim_fail.log --meta $(BUILD_DIR)/phase4/scan8.json --report reports/ate_diag_report.md

schematics: sta
	PATH=$(OPENSTA_BIN):$(EDA_BIN):/usr/bin:/bin IHP_LIB_TYP=$(IHP_LIB_TYP) python3 scripts/extract_asic_metrics.py --skip-metrics

metrics: synth-baseline sta
	PATH=$(OPENSTA_BIN):$(EDA_BIN):/usr/bin:/bin IHP_LIB_TYP=$(IHP_LIB_TYP) python3 scripts/extract_asic_metrics.py

fpga-metrics: synth-baseline sta
	PATH=$(OPENSTA_BIN):$(EDA_BIN):/usr/bin:/bin IHP_LIB_TYP=$(IHP_LIB_TYP) python3 scripts/extract_asic_metrics.py --run-xilinx

clean:
	rm -rf $(BUILD_DIR)
