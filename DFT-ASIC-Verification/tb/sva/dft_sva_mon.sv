`timescale 1ns/1ps

// Continuous SVA Protocol Assertions & Functional Cover Properties for soc_dft_top
// Enforces IEEE 1149.1, IEEE 1500, MBIST, OCC, and Scan safety invariants.
module dft_sva_mon (
    // Clocks & resets
    input logic        sys_clk,
    input logic        sys_rst_n,
    input logic        tck,
    input logic        trst_n,

    // JTAG internal status
    input logic [3:0]  tap_state,
    input logic [3:0]  ir_reg,
    input logic        tdo_en,
    input logic [7:0]  tdr_dft_ctrl,
    input logic [15:0] tdr_comp_cfg,

    // IEEE 1500 wrapper status & boundaries
    input logic [3:0]  wir_out,
    input logic        intest_active,
    input logic        extest_active,
    input logic        core_prog_sel,
    input logic [31:0] sys_x14,
    input logic [31:0] sys_pc_obs,
    input logic [31:0] sys_alu_obs,

    // OCC clock & reset gating internals
    input logic        eff_test_mode,
    input logic        scan_en,
    input logic        rst_mask_en,
    input logic        occ_bypass,
    input logic        dft_rst_n,
    input logic        loc_active,
    input logic        scan_en_sys1_q,
    input logic [1:0]  loc_rem_q,
    input logic        allow_sys,
    input logic        en_tck_lat_q,
    input logic        en_sys_off_neg_q,

    // MBIST internals
    input logic        bist_en,
    input logic        bist_we,
    input logic [1:0]  bist_bank_sel,
    input logic        bist_done,
    input logic        bist_fail,
    input logic [2:0]  mbist_elem_q,
    input logic [1:0]  mbist_pattern_mode
);

    /* verilator lint_off SYNCASYNCNET */
    // =========================================================================
    // 1. Concurrent Safety & Protocol Assertions
    // =========================================================================

    // JTAG-03: TDO output enable asserted strictly in Shift-DR / Shift-IR
    property p_tdo_en_only_shift;
        @(posedge tck) disable iff (!trst_n)
            tdo_en |-> (tap_state == 4'h4 || tap_state == 4'hB);
    endproperty
    a_tdo_en_only_shift: assert property (p_tdo_en_only_shift)
        else $error("SVA FAIL [JTAG]: tdo_en asserted in tap_state=%h", tap_state);

    // JTAG-02: Entering Test-Logic-Reset initializes IR=IDCODE & DFT_CTRL=0x08
    property p_tlr_resets_jtag;
        @(posedge tck) disable iff (!trst_n)
            (tap_state == 4'h0) |=> (ir_reg == 4'b0001 && tdr_dft_ctrl == 8'h08);
    endproperty
    a_tlr_resets_jtag: assert property (p_tlr_resets_jtag)
        else $error("SVA FAIL [JTAG]: TLR did not reset IR/DFT_CTRL");

    // W1500-01: INTEST cleanly isolates system pins (0) from core toggling
    property p_w1500_intest_isolates_sys;
        @(posedge sys_clk)
            (intest_active && !extest_active) |->
                (sys_x14 == 32'd0 && sys_pc_obs == 32'd0 && sys_alu_obs == 32'd0);
    endproperty
    a_w1500_intest_isolates_sys: assert property (p_w1500_intest_isolates_sys)
        else $error("SVA FAIL [W1500]: INTEST failed to clamp system outputs");

    // W1500-02: EXTEST clamps core_prog_sel cleanly
    property p_w1500_extest_clamps_core;
        @(posedge sys_clk)
            extest_active |-> (core_prog_sel == 1'b0);
    endproperty
    a_w1500_extest_clamps_core: assert property (p_w1500_extest_clamps_core)
        else $error("SVA FAIL [W1500]: EXTEST did not isolate core_prog_sel");

    // OCC-01 / DBG-01: Async reset masked to 1 during test_mode when rst_mask_en=1
    property p_occ_rst_mask;
        @(posedge sys_clk)
            (eff_test_mode && rst_mask_en) |-> (dft_rst_n == 1'b1);
    endproperty
    a_occ_rst_mask: assert property (p_occ_rst_mask)
        else $error("SVA FAIL [OCC]: dft_rst_n leaked 0 during masked test_mode");

    // OCC-01: LOC disables allow_sys once remaining capture pulse counter reaches 0
    property p_occ_loc_pulse_cap;
        @(posedge sys_clk) disable iff (!dft_rst_n)
            (loc_active && !scan_en_sys1_q && (loc_rem_q == 2'd0)) |-> !allow_sys;
    endproperty
    a_occ_loc_pulse_cap: assert property (p_occ_loc_pulse_cap)
        else $error("SVA FAIL [OCC]: allow_sys stayed high after 2 LOC pulses");

    // MBIST-01: After completion, MBIST releases SRAM mux & write-enable cleanly
    property p_mbist_done_releases_sram;
        @(posedge sys_clk) disable iff (!sys_rst_n)
            bist_done |-> (!bist_en && !bist_we);
    endproperty
    a_mbist_done_releases_sram: assert property (p_mbist_done_releases_sram)
        else $error("SVA FAIL [MBIST]: SRAM bist_en/bist_we active after bist_done");

    // =========================================================================
    // 2. Functional Coverage Points (User Cover Bins)
    // =========================================================================

    // All 16 JTAG TAP states
    genvar s;
    generate
        for (s = 0; s < 16; s = s + 1) begin : g_cov_tap
            c_tap_state: cover property (@(posedge tck) disable iff (!trst_n) tap_state == s[3:0]);
        end
    endgenerate

    // Documented JTAG IR opcodes + illegal fallback
    c_ir_extest:  cover property (@(posedge tck) disable iff (!trst_n) ir_reg == 4'h0);
    c_ir_idcode:  cover property (@(posedge tck) disable iff (!trst_n) ir_reg == 4'h1);
    c_ir_sample:  cover property (@(posedge tck) disable iff (!trst_n) ir_reg == 4'h2);
    c_ir_intest:  cover property (@(posedge tck) disable iff (!trst_n) ir_reg == 4'h3);
    c_ir_dft:     cover property (@(posedge tck) disable iff (!trst_n) ir_reg == 4'h4);
    c_ir_mcmd:    cover property (@(posedge tck) disable iff (!trst_n) ir_reg == 4'h5);
    c_ir_mstat:   cover property (@(posedge tck) disable iff (!trst_n) ir_reg == 4'h6);
    c_ir_comp:    cover property (@(posedge tck) disable iff (!trst_n) ir_reg == 4'h7);
    c_ir_w1500:   cover property (@(posedge tck) disable iff (!trst_n) ir_reg == 4'h8);
    c_ir_bypass:  cover property (@(posedge tck) disable iff (!trst_n) ir_reg == 4'hF);
    c_ir_illegal: cover property (@(posedge tck) disable iff (!trst_n) ir_reg == 4'hA);

    // IEEE 1500 WIR modes
    c_wir_bypass: cover property (@(posedge tck) disable iff (!trst_n) wir_out == 4'b0000);
    c_wir_extest: cover property (@(posedge tck) disable iff (!trst_n) wir_out == 4'b0001);
    c_wir_intest: cover property (@(posedge tck) disable iff (!trst_n) wir_out == 4'b0010);
    c_wir_sample: cover property (@(posedge tck) disable iff (!trst_n) wir_out == 4'b0011);
    c_wir_safe:   cover property (@(posedge tck) disable iff (!trst_n) wir_out == 4'b1111);

    // MBIST algorithms, banks, and outcomes
    genvar m, b;
    generate
        for (m = 0; m < 6; m = m + 1) begin : g_cov_march
            c_march_elem: cover property (@(posedge sys_clk) disable iff (!sys_rst_n)
                                          bist_en && (mbist_elem_q == m[2:0]));
        end
        for (b = 0; b < 4; b = b + 1) begin : g_cov_bank
            c_mbist_bank: cover property (@(posedge sys_clk) disable iff (!sys_rst_n)
                                          bist_en && (bist_bank_sel == b[1:0]));
        end
    endgenerate
    c_mbist_chkb:  cover property (@(posedge sys_clk) disable iff (!sys_rst_n)
                                   bist_en && (mbist_pattern_mode == 2'b01));
    c_mbist_pass:  cover property (@(posedge sys_clk) disable iff (!sys_rst_n)
                                   bist_done && !bist_fail);
    c_mbist_fail:  cover property (@(posedge sys_clk) disable iff (!sys_rst_n)
                                   bist_done && bist_fail);

    // OCC & Scan compression operating modes
    c_occ_shift:   cover property (@(posedge tck) en_tck_lat_q && scan_en);
    c_occ_loc:     cover property (@(posedge sys_clk) loc_active && !en_sys_off_neg_q);
    c_occ_bypass:  cover property (@(posedge tck) eff_test_mode && occ_bypass);
    c_rst_masked:  cover property (@(posedge tck) eff_test_mode && rst_mask_en && !sys_rst_n && dft_rst_n);
    c_scan_bypass: cover property (@(posedge tck) scan_en && !tdr_comp_cfg[0]);
    c_scan_comp:   cover property (@(posedge tck) scan_en && tdr_comp_cfg[0] && tdr_comp_cfg[1]);
    c_scan_xmask:  cover property (@(posedge tck) scan_en && (tdr_comp_cfg[10:3] != 8'h00));
    /* verilator lint_on SYNCASYNCNET */

endmodule
