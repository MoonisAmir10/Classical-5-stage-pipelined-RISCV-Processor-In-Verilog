# ATE Silicon Fail Diagnosis Report (`scripts/ate_fail_diag.py`)

- **Fail Log:** `reports/ate_sim_fail.log`
- **Scan Map:** `build/phase4/scan8.json`
- **Total Fail Events Diagnosed:** `3`

| Pat | Mode | Pin | Shift Cyc | Exp -> Got | Resolution | Suspect Chain / Bit | Synth FF Instance | RTL Signal (`q_net`) | Note |
| :---: | :---: | :---: | :---: | :---: | :--- | :---: | :--- | :--- | :--- |
| 0 | `BYPASS` | 0 | 0 | `1` -> `0` | EXACT_1TO1 | ch7[267] | `_17059_` | `\u_rv32i_core.alu_select_DE.out [8]` | `DBG01_RESET_LEAK` |
| 1 | `BYPASS` | 0 | 1301 | `1` -> `0` | EXACT_1TO1 | ch3[42] | `_15758_` | `\u_rv32i_core.datapath_inst.regfile_inst.reg_array[2] [6]` | `SA0_CH3_BIT42` |
| 2 | `COMP82` | 1 | 226 | `0` -> `x` | ISOLATED_BY_XMASK | ch3[42] | `_15758_` | `\u_rv32i_core.datapath_inst.regfile_inst.reg_array[2] [6]` | `DBG03_X_INJECT` |
