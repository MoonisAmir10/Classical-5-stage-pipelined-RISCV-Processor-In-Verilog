#!/usr/bin/env bash
# Source this file to activate the local open-source DFT toolchain:
#   source env_eda.sh

_EDA_ROOT="/home/moonis/auto_job_seeker/.eda_tools"
export EDA_ENV_PREFIX="${_EDA_ROOT}/envs/dft"
export PYTHONHOME="${EDA_ENV_PREFIX}"
export PATH="${EDA_ENV_PREFIX}/bin:${_EDA_ROOT}/opensta/bin:${PATH}"

export PDK_ROOT="${_EDA_ROOT}/pdk"

# Primary PDK (IHP SG13G2 130nm — full specify blocks for SDF GLS + Fault + OpenSTA)
export IHP_PDK_DIR="${PDK_ROOT}/ihp-sg13g2/libs.ref/sg13g2_stdcell"
export IHP_LIB_TYP="${IHP_PDK_DIR}/lib/sg13g2_stdcell_typ_1p20V_25C.lib"
export IHP_LIB_SLOW="${IHP_PDK_DIR}/lib/sg13g2_stdcell_slow_1p08V_125C.lib"
export IHP_LIB_FAST="${IHP_PDK_DIR}/lib/sg13g2_stdcell_fast_1p32V_m40C.lib"
export IHP_UDP_V="${IHP_PDK_DIR}/verilog/sg13g2_udp.v"
export IHP_STDCELL_V="${IHP_PDK_DIR}/verilog/sg13g2_stdcell.v"
export IHP_BUNDLE_V="${IHP_PDK_DIR}/verilog/sg13g2_bundle.v"

# Secondary PDK (Sky130 HD + SRAM macros)
export SKY130_HD_DIR="${PDK_ROOT}/sky130A/libs.ref/sky130_fd_sc_hd"
export SKY130_HD_LIB_TT="${SKY130_HD_DIR}/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
export SKY130_HD_LIB_SS="${SKY130_HD_DIR}/lib/sky130_fd_sc_hd__ss_100C_1v60.lib"
export SKY130_HD_LIB_FF="${SKY130_HD_DIR}/lib/sky130_fd_sc_hd__ff_n40C_1v95.lib"
export SKY130_HD_PRIMS_V="${SKY130_HD_DIR}/verilog/primitives.v"
export SKY130_HD_CELLS_V="${SKY130_HD_DIR}/verilog/sky130_fd_sc_hd_sim.v"
export SKY130_HD_BUNDLE_V="${SKY130_HD_DIR}/verilog/sky130_fd_sc_hd_bundle.v"
export SKY130_SRAM_DIR="${PDK_ROOT}/sky130A/libs.ref/sky130_sram_macros"
