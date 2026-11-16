`timescale 1ns/1ps

// IEEE 1500 Core Test Wrapper around rv32i_processor.
// Boundary ports wrapped (WBR_LEN = 97 bits):
//   [0]      prog_sel (input cell)
//   [32:1]   x14      (32 output cells)
//   [64:33]  pc_obs   (32 output cells)
//   [96:65]  alu_obs  (32 output cells)
// Supports standalone IEEE 1500 WSP control as well as JTAG bridge overrides.
module ieee1500_wrapper #(
    parameter integer WBR_LEN = 97
) (
    // Wrapper Serial Port (WSP)
    input  logic        wrck,
    input  logic        wrst_n,
    input  logic        wrst_sync,
    input  logic        select_wir,
    input  logic        capture_wr,
    input  logic        shift_wr,
    input  logic        update_wr,
    input  logic        wsi,
    output logic        wso,

    // Optional JTAG-bridge mode overrides
    input  logic        jtag_extest,
    input  logic        jtag_sample_preload,
    input  logic        jtag_intest,

    // External / SoC system-side boundary pins
    input  logic        sys_prog_sel,
    output logic [31:0] sys_x14,
    output logic [31:0] sys_pc_obs,
    output logic [31:0] sys_alu_obs,

    // Core-side boundary pins (connected to rv32i_processor)
    output logic        core_prog_sel,
    input  logic [31:0] core_x14,
    input  logic [31:0] core_pc_obs,
    input  logic [31:0] core_alu_obs,

    // Observable status flags for verification / SVA
    output logic [3:0]  wir_out,
    output logic        intest_active,
    output logic        extest_active
);

    // IEEE 1500 Wrapper Instruction Register (WIR) opcodes
    localparam logic [3:0]
        WS_BYPASS         = 4'b0000,
        WS_EXTEST         = 4'b0001,
        WS_INTEST_RING    = 4'b0010,
        WS_SAMPLE_PRELOAD = 4'b0011,
        WS_SAFE           = 4'b1111;

    logic [3:0]         wir_shift_q;
    logic [3:0]         wir_q;
    logic               wby_q;
    logic [WBR_LEN-1:0] wbr_shift_q;
    logic               wbr_upd_prog_sel_q;
    logic [95:0]        wbr_upd_out_q;

    assign wir_out = wir_q;

    // Effective mode resolution (JTAG bridge overrides WIR when active; otherwise WIR governs)
    wire jtag_wbr_override = jtag_extest || jtag_intest || jtag_sample_preload;
    wire eff_extest        = jtag_extest || (!jtag_wbr_override && (wir_q == WS_EXTEST));
    wire eff_intest        = jtag_intest || (!jtag_wbr_override && (wir_q == WS_INTEST_RING));
    wire eff_sample        = jtag_sample_preload || (!jtag_wbr_override && (wir_q == WS_SAMPLE_PRELOAD));
    wire eff_safe          = !jtag_wbr_override && (wir_q == WS_SAFE);

    assign intest_active = eff_intest;
    assign extest_active = eff_extest;

    // Select WBR when executing WBR-based instructions; otherwise select 1-bit WBY
    wire wbr_selected = eff_extest || eff_intest || eff_sample;

    // Core input boundary mux (controls core_prog_sel during INTEST; clamps during EXTEST/SAFE)
    always_comb begin
        if (eff_intest) begin
            core_prog_sel = wbr_upd_prog_sel_q;
        end else if (eff_extest || eff_safe) begin
            core_prog_sel = 1'b0;
        end else begin
            core_prog_sel = sys_prog_sel;
        end
    end

    // System output boundary mux (drives updated WBR in EXTEST, clamps in INTEST/SAFE, passes in FUNC/SAMPLE)
    always @(*) begin
        if (eff_extest) begin
            sys_x14     = wbr_upd_out_q[31:0];
            sys_pc_obs  = wbr_upd_out_q[63:32];
            sys_alu_obs = wbr_upd_out_q[95:64];
        end else if (eff_intest || eff_safe) begin
            sys_x14     = 32'd0;
            sys_pc_obs  = 32'd0;
            sys_alu_obs = 32'd0;
        end else begin
            sys_x14     = core_x14;
            sys_pc_obs  = core_pc_obs;
            sys_alu_obs = core_alu_obs;
        end
    end

    // Boundary capture sources:
    //   Input cell [0]: captures sys_prog_sel in EXTEST/SAMPLE/FUNC; retains wbr_upd_prog_sel_q in INTEST
    //   Output cells [96:1]: capture core outputs in INTEST/SAMPLE/FUNC; retain wbr_upd_out_q in EXTEST
    wire        cap_in_bit   = eff_intest ? wbr_upd_prog_sel_q : sys_prog_sel;
    wire [95:0] cap_out_bits = eff_extest ? wbr_upd_out_q : {core_alu_obs, core_pc_obs, core_x14};

    // Serial Capture & Shift on rising edge of WRCK
    always_ff @(posedge wrck or negedge wrst_n) begin
        if (!wrst_n) begin
            wir_shift_q <= WS_BYPASS;
            wby_q       <= 1'b0;
            wbr_shift_q <= {WBR_LEN{1'b0}};
        end else if (wrst_sync) begin
            wir_shift_q <= WS_BYPASS;
            wby_q       <= 1'b0;
            wbr_shift_q <= {WBR_LEN{1'b0}};
        end else begin
            if (select_wir) begin
                if (capture_wr) begin
                    wir_shift_q <= wir_q;
                end else if (shift_wr) begin
                    wir_shift_q <= {wsi, wir_shift_q[3:1]};
                end
            end else if (wbr_selected) begin
                if (capture_wr) begin
                    wbr_shift_q <= {cap_out_bits, cap_in_bit};
                end else if (shift_wr) begin
                    wbr_shift_q <= {wsi, wbr_shift_q[WBR_LEN-1:1]};
                end
            end else begin
                if (capture_wr) begin
                    wby_q <= 1'b0;
                end else if (shift_wr) begin
                    wby_q <= wsi;
                end
            end
        end
    end

    // Parallel Update shadow latches on falling edge of WRCK (IEEE 1500 compliant)
    always_ff @(negedge wrck or negedge wrst_n) begin
        if (!wrst_n) begin
            wir_q              <= WS_BYPASS;
            wbr_upd_prog_sel_q <= 1'b0;
            wbr_upd_out_q      <= 96'd0;
        end else if (wrst_sync) begin
            wir_q              <= WS_BYPASS;
            wbr_upd_prog_sel_q <= 1'b0;
            wbr_upd_out_q      <= 96'd0;
        end else if (update_wr) begin
            if (select_wir) begin
                wir_q <= wir_shift_q;
            end else if (wbr_selected) begin
                wbr_upd_prog_sel_q <= wbr_shift_q[0];
                wbr_upd_out_q      <= wbr_shift_q[WBR_LEN-1:1];
            end
        end
    end

    // Serial Output WSO
    assign wso = select_wir   ? wir_shift_q[0] :
                 wbr_selected ? wbr_shift_q[0] : wby_q;

endmodule
