`timescale 1ns/1ps

// Glitch-free On-Chip Clock & Reset Controller (OCC) for DFT Modes.
// Reference: docs/dft_spec.md Section 2 and Section 6
// Features:
//   - Synchronized negative-edge clock enable handshake between sys_clk (100 MHz) & tck (10 MHz)
//   - Launch-on-Capture (occ_loc_en=1) 2-pulse sys_clk burst upon scan_en 1->0
//   - Bypass mode (occ_bypass=1 && test_mode=1) routing TCK directly when sys_clk is stopped
//   - Active-low async reset gating: dft_rst_n = (test_mode && rst_mask_en) ? 1'b1 : sys_rst_n
module occ_clk_ctrl (
    input  logic sys_clk,
    input  logic sys_rst_n,
    input  logic tck,
    input  logic trst_n,
    input  logic test_mode,
    input  logic scan_en,
    input  logic mbist_active,
    input  logic occ_loc_en,
    input  logic occ_bypass,
    input  logic rst_mask_en,
    output logic occ_clk,
    output logic dft_rst_n
);

    // Async reset mask protecting scan shift chains from sys_rst_n glitches
    assign dft_rst_n = (test_mode && rst_mask_en) ? 1'b1 : sys_rst_n;

    // Desired clock source selection (tck during scan shift when not running MBIST)
    wire bypass_tck = test_mode && occ_bypass && !mbist_active;
    wire sel_tck    = test_mode && scan_en && !mbist_active && !bypass_tck;

    // Handshake registers
    logic       tck_s0_q, tck_s1_q, en_tck_lat_q;
    logic       sys_s0_q, sys_s1_q, en_sys_off_neg_q;
    logic       scan_en_sys0_q, scan_en_sys1_q;
    logic [1:0] loc_rem_q;

    // Branch 1: TCK clock-gating domain (reset cleanly to 0 on !trst_n)
    // Synchronize sys_clk-stopped handshake (en_sys_off_neg_q) on turn-on,
    // and gate immediately via low-level ICG latch on !tck so no extra TCK
    // pulses leak after scan_en drops 1->0.
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            tck_s0_q <= 1'b0;
            tck_s1_q <= 1'b0;
        end else begin
            tck_s0_q <= sel_tck && en_sys_off_neg_q;
            tck_s1_q <= sel_tck && tck_s0_q;
        end
    end

    /* verilator lint_off SYNCASYNCNET */
    always_latch begin
        if (!trst_n) begin
            en_tck_lat_q = 1'b0;
        end else if (!tck) begin
            en_tck_lat_q = sel_tck && tck_s1_q;
        end
    end
    /* verilator lint_on SYNCASYNCNET */

    // Branch 2: sys_clk clock-gating & LOC burst domain
    // en_sys_off_neg_q resets to 0 so FUNC mode (!test_mode) passes sys_clk immediately.
    wire want_sys_base = (!sel_tck) && (!bypass_tck) && (!en_tck_lat_q);
    wire loc_active    = test_mode && occ_loc_en && !mbist_active && !bypass_tck;

    always_ff @(posedge sys_clk or negedge dft_rst_n) begin
        if (!dft_rst_n) begin
            sys_s0_q       <= 1'b0;
            sys_s1_q       <= 1'b0;
            scan_en_sys0_q <= 1'b0;
            scan_en_sys1_q <= 1'b0;
            loc_rem_q      <= 2'd2;
        end else begin
            scan_en_sys0_q <= scan_en;
            scan_en_sys1_q <= scan_en_sys0_q;
            sys_s0_q       <= want_sys_base;
            sys_s1_q       <= sys_s0_q;

            if (scan_en_sys1_q || !loc_active) begin
                loc_rem_q <= 2'd2;
            end else if (!en_sys_off_neg_q && (loc_rem_q != 2'd0)) begin
                loc_rem_q <= loc_rem_q - 2'd1;
            end
        end
    end

    wire allow_sys = !test_mode ? 1'b1 :
                     (sys_s1_q && (!loc_active || (!scan_en_sys1_q && (loc_rem_q != 2'd0))));

    always_ff @(negedge sys_clk or negedge dft_rst_n) begin
        if (!dft_rst_n) begin
            en_sys_off_neg_q <= 1'b0;
        end else begin
            en_sys_off_neg_q <= !allow_sys;
        end
    end

    wire g_tck = tck     & en_tck_lat_q;
    wire g_sys = sys_clk & (~en_sys_off_neg_q);

    assign occ_clk = bypass_tck ? tck : (g_tck | g_sys);

endmodule
