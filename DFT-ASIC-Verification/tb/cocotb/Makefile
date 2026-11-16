TOPLEVEL_LANG = verilog
SIM ?= icarus
COMPILE_ARGS += -g2012

PROJ_DIR := $(abspath ../..)
VERILOG_SOURCES = \
	$(wildcard $(PROJ_DIR)/rtl/core/rv32i_*.v) \
	$(PROJ_DIR)/rtl/mem/sram_sync_sp.v \
	$(PROJ_DIR)/rtl/core/cache_ctrl_logic.v \
	$(PROJ_DIR)/rtl/core/cache_2wsa_dft.v \
	$(PROJ_DIR)/rtl/dft/jtag_tap.sv \
	$(PROJ_DIR)/rtl/dft/ieee1500_wrapper.sv \
	$(PROJ_DIR)/rtl/dft/mbist_ctrl.sv \
	$(PROJ_DIR)/rtl/dft/occ_clk_ctrl.sv \
	$(PROJ_DIR)/rtl/dft/scan_comp_wrap.sv \
	$(PROJ_DIR)/rtl/top/soc_dft_top.sv

TOPLEVEL = soc_dft_top
COCOTB_TEST_MODULES = test_soc_dft_dv
SIM_BUILD = $(PROJ_DIR)/build/cocotb_dv
COCOTB_RESULTS_FILE = $(PROJ_DIR)/build/cocotb_results.xml

include $(shell cocotb-config --makefiles)/Makefile.sim
