`timescale 1ns/1ps

// Top-Level DFT-Enabled RISC-V SoC Subsystem
// Integrates:
//   - rv32i_processor (wrapped by IEEE 1500 Core Test Wrapper)
//   - cache_2wsa_dft + 4x sram_sync_sp (with March-C MBIST controller)
//   - IEEE 1149.1 JTAG TAP Controller & Custom TDRs
//   - Glitch-Free OCC Clock & Async Reset Controller
//   - 2:8 Scan Compression & 16-bit X-Masked MISR Wrapper
// Reference: docs/dft_spec.md
module soc_dft_top #(
    parameter logic [31:0] IDCODE_VALUE        = 32'h1BAD_D071,
    parameter integer      USE_EXT_SCAN_CHAINS = 0
) (
    // System clock & reset
    input  logic        sys_clk,
    input  logic        sys_rst_n,

    // IEEE 1149.1 JTAG TAP pins
    input  logic        tck,
    input  logic        tms,
    input  logic        tdi,
    output logic        tdo,
    output logic        tdo_en,
    input  logic        trst_n,

    // Dedicated ATE DFT pins
    input  logic        test_mode,
    input  logic        scan_en,
    input  logic [1:0]  scan_in,
    output logic [1:0]  scan_out,
    output logic        bist_done,
    output logic        bist_fail,

    // Functional RV32I processor interface (IEEE 1500 wrapped)
    input  logic        prog_sel,
    output logic [31:0] x14,
    output logic [31:0] pc_obs,
    output logic [31:0] alu_obs,

    // Functional 2-way cache CPU & Main-Memory unidirectional interfaces
    input  logic [7:0]  cache_cpu_wdata,
    output logic [7:0]  cache_cpu_rdata,
    output logic        cache_cpu_rdata_oe,
    input  logic [15:0] cache_addr_cpu,
    input  logic        cache_rd_cpu,
    input  logic        cache_wr_cpu,
    output logic        cache_stall_cpu,

    input  logic [7:0]  cache_mem_rdata,
    output logic [7:0]  cache_mem_wdata,
    output logic        cache_mem_wdata_oe,
    output logic [15:0] cache_addr_mem,
    output logic        cache_rd_mem,
    output logic        cache_wr_mem,
    input  logic        cache_ready_mem
`ifndef SYNTHESIS
    ,
    // Simulation-only SRAM fault injection interface
    input  logic        inj_en,
    input  logic [1:0]  inj_bank,
    input  logic [2:0]  inj_addr,
    input  logic [5:0]  inj_bit,
    input  logic [1:0]  inj_type
`endif
);

    // JTAG internal status & TDR buses
    logic [3:0]  tap_state;
    logic [3:0]  ir_reg;
    logic [7:0]  tdr_dft_ctrl;
    logic [7:0]  tdr_mbist_cmd;
    logic        mbist_start_toggle;
    logic [47:0] mbist_stat;
    logic [15:0] tdr_comp_cfg;

    // IEEE 1500 bridge wires
    logic        w1500_wrst_n, w1500_tlr_sync;
    logic        w1500_select_wir, w1500_select_wbr;
    logic        w1500_capture, w1500_shift, w1500_update;
    logic        w1500_mode_extest, w1500_mode_sample, w1500_mode_intest;
    logic        w1500_wsi, w1500_wso;
    logic [3:0]  w1500_wir_out;
    logic        w1500_intest_active, w1500_extest_active;

    // Core-side wires inside IEEE 1500 wrapper
    logic        core_prog_sel;
    logic [31:0] core_x14, core_pc_obs, core_alu_obs;

    // OCC clock & reset wires
    logic        occ_clk;
    logic        dft_rst_n;
    wire         eff_test_mode = test_mode || tdr_dft_ctrl[0];
    wire         occ_loc_en    = tdr_dft_ctrl[1];
    wire         occ_bypass    = tdr_dft_ctrl[2];
    wire         rst_mask_en   = tdr_dft_ctrl[3];

    // MBIST wires
    logic        bist_en;
    logic [1:0]  bist_bank_sel;
    logic [2:0]  bist_addr;
    logic [31:0] bist_din;
    logic        bist_we;
    logic [31:0] bist_dout;

    // Scan compression wires
    logic [7:0]  chain_scan_in;
    logic [7:0]  chain_scan_out;
    logic [15:0] misr_sig;

    // JTAG TAP Controller
    jtag_tap #(
        .IDCODE_VALUE (IDCODE_VALUE)
    ) u_jtag_tap (
        .tck                (tck),
        .trst_n             (trst_n),
        .tms                (tms),
        .tdi                (tdi),
        .tdo                (tdo),
        .tdo_en             (tdo_en),
        .tap_state          (tap_state),
        .ir_reg             (ir_reg),
        .w1500_wrst_n       (w1500_wrst_n),
        .w1500_tlr_sync     (w1500_tlr_sync),
        .w1500_select_wir   (w1500_select_wir),
        .w1500_select_wbr   (w1500_select_wbr),
        .w1500_capture      (w1500_capture),
        .w1500_shift        (w1500_shift),
        .w1500_update       (w1500_update),
        .w1500_mode_extest  (w1500_mode_extest),
        .w1500_mode_sample  (w1500_mode_sample),
        .w1500_mode_intest  (w1500_mode_intest),
        .w1500_wsi          (w1500_wsi),
        .w1500_wso          (w1500_wso),
        .tdr_dft_ctrl       (tdr_dft_ctrl),
        .tdr_mbist_cmd      (tdr_mbist_cmd),
        .mbist_start_toggle (mbist_start_toggle),
        .mbist_stat_in      (mbist_stat),
        .tdr_comp_cfg       (tdr_comp_cfg)
    );

    // OCC Clock & Reset Controller
    occ_clk_ctrl u_occ_clk_ctrl (
        .sys_clk      (sys_clk),
        .sys_rst_n    (sys_rst_n),
        .tck          (tck),
        .trst_n       (trst_n),
        .test_mode    (eff_test_mode),
        .scan_en      (scan_en),
        .mbist_active (bist_en),
        .occ_loc_en   (occ_loc_en),
        .occ_bypass   (occ_bypass),
        .rst_mask_en  (rst_mask_en),
        .occ_clk      (occ_clk),
        .dft_rst_n    (dft_rst_n)
    );

    // IEEE 1500 Wrapper around RV32I Processor
    ieee1500_wrapper #(
        .WBR_LEN (97)
    ) u_ieee1500_wrapper (
        .wrck                (tck),
        .wrst_n              (w1500_wrst_n),
        .wrst_sync           (w1500_tlr_sync),
        .select_wir          (w1500_select_wir),
        .capture_wr          (w1500_capture),
        .shift_wr            (w1500_shift),
        .update_wr           (w1500_update),
        .wsi                 (w1500_wsi),
        .wso                 (w1500_wso),
        .jtag_extest         (w1500_mode_extest),
        .jtag_sample_preload (w1500_mode_sample),
        .jtag_intest         (w1500_mode_intest),
        .sys_prog_sel        (prog_sel),
        .sys_x14             (x14),
        .sys_pc_obs          (pc_obs),
        .sys_alu_obs         (alu_obs),
        .core_prog_sel       (core_prog_sel),
        .core_x14            (core_x14),
        .core_pc_obs         (core_pc_obs),
        .core_alu_obs        (core_alu_obs),
        .wir_out             (w1500_wir_out),
        .intest_active       (w1500_intest_active),
        .extest_active       (w1500_extest_active)
    );

`ifdef POST_SCAN_STITCH
    // Stitched gate-level core+cache logic (2,151 FFs across 8 chains) + 4 SRAM banks
    wire [2:0]  sram_index;
    wire [13:0] sram_wtag0, sram_wtag1, sram_rtag0, sram_rtag1;
    wire        sram_wet0, sram_wet1, sram_we0, sram_we1;
    wire [31:0] sram_wdata, sram_rdata0, sram_rdata1;
    wire        sram_bist_en_t0, sram_bist_en_t1, sram_bist_en_d0, sram_bist_en_d1;
    wire [2:0]  sram_bist_addr;
    wire [13:0] sram_bist_din_tag, sram_bist_dout_t0, sram_bist_dout_t1;
    wire [31:0] sram_bist_din_data, sram_bist_dout_d0, sram_bist_dout_d1;
    wire        sram_bist_we;

    soc_func_logic u_func_logic (
        .clk                (occ_clk),
        .rst_n              (dft_rst_n),
        .prog_sel           (core_prog_sel),
        .x14                (core_x14),
        .pc_obs             (core_pc_obs),
        .alu_obs            (core_alu_obs),
        .cache_cpu_wdata    (cache_cpu_wdata),
        .cache_cpu_rdata    (cache_cpu_rdata),
        .cache_cpu_rdata_oe (cache_cpu_rdata_oe),
        .cache_addr_cpu     (cache_addr_cpu),
        .cache_rd_cpu       (cache_rd_cpu),
        .cache_wr_cpu       (cache_wr_cpu),
        .cache_stall_cpu    (cache_stall_cpu),
        .cache_mem_rdata    (cache_mem_rdata),
        .cache_mem_wdata    (cache_mem_wdata),
        .cache_mem_wdata_oe (cache_mem_wdata_oe),
        .cache_addr_mem     (cache_addr_mem),
        .cache_rd_mem       (cache_rd_mem),
        .cache_wr_mem       (cache_wr_mem),
        .cache_ready_mem    (cache_ready_mem),
        .bist_en            (bist_en),
        .bist_bank_sel      (bist_bank_sel),
        .bist_addr          (bist_addr),
        .bist_din           (bist_din),
        .bist_we            (bist_we),
        .bist_dout          (bist_dout),
        .sram_index         (sram_index),
        .sram_wtag0         (sram_wtag0),
        .sram_wtag1         (sram_wtag1),
        .sram_wet0          (sram_wet0),
        .sram_wet1          (sram_wet1),
        .sram_wdata         (sram_wdata),
        .sram_we0           (sram_we0),
        .sram_we1           (sram_we1),
        .sram_rtag0         (sram_rtag0),
        .sram_rtag1         (sram_rtag1),
        .sram_rdata0        (sram_rdata0),
        .sram_rdata1        (sram_rdata1),
        .sram_bist_en_t0    (sram_bist_en_t0),
        .sram_bist_en_t1    (sram_bist_en_t1),
        .sram_bist_en_d0    (sram_bist_en_d0),
        .sram_bist_en_d1    (sram_bist_en_d1),
        .sram_bist_addr     (sram_bist_addr),
        .sram_bist_din_tag  (sram_bist_din_tag),
        .sram_bist_din_data (sram_bist_din_data),
        .sram_bist_we       (sram_bist_we),
        .sram_bist_dout_t0  (sram_bist_dout_t0),
        .sram_bist_dout_t1  (sram_bist_dout_t1),
        .sram_bist_dout_d0  (sram_bist_dout_d0),
        .sram_bist_dout_d1  (sram_bist_dout_d1),
        .scan_en            (scan_en),
        .scan_in            (chain_scan_in),
        .scan_out           (chain_scan_out)
    );

    sram_sync_sp #(.AWIDTH(3), .DWIDTH(14)) u_tag_ram_w0 (
        .clock     (occ_clk),
        .addr      (sram_index),
        .din       (sram_wtag0),
        .we        (sram_wet0),
        .dout      (sram_rtag0),
        .bist_en   (sram_bist_en_t0),
        .bist_addr (sram_bist_addr),
        .bist_din  (sram_bist_din_tag),
        .bist_we   (sram_bist_we),
        .bist_dout (sram_bist_dout_t0)
`ifndef SYNTHESIS
        , .inj_en(inj_en && (inj_bank == 2'd0)), .inj_addr(inj_addr), .inj_bit(inj_bit), .inj_type(inj_type)
`endif
    );

    sram_sync_sp #(.AWIDTH(3), .DWIDTH(14)) u_tag_ram_w1 (
        .clock     (occ_clk),
        .addr      (sram_index),
        .din       (sram_wtag1),
        .we        (sram_wet1),
        .dout      (sram_rtag1),
        .bist_en   (sram_bist_en_t1),
        .bist_addr (sram_bist_addr),
        .bist_din  (sram_bist_din_tag),
        .bist_we   (sram_bist_we),
        .bist_dout (sram_bist_dout_t1)
`ifndef SYNTHESIS
        , .inj_en(inj_en && (inj_bank == 2'd1)), .inj_addr(inj_addr), .inj_bit(inj_bit), .inj_type(inj_type)
`endif
    );

    sram_sync_sp #(.AWIDTH(3), .DWIDTH(32)) u_data_ram_w0 (
        .clock     (occ_clk),
        .addr      (sram_index),
        .din       (sram_wdata),
        .we        (sram_we0),
        .dout      (sram_rdata0),
        .bist_en   (sram_bist_en_d0),
        .bist_addr (sram_bist_addr),
        .bist_din  (sram_bist_din_data),
        .bist_we   (sram_bist_we),
        .bist_dout (sram_bist_dout_d0)
`ifndef SYNTHESIS
        , .inj_en(inj_en && (inj_bank == 2'd2)), .inj_addr(inj_addr), .inj_bit(inj_bit), .inj_type(inj_type)
`endif
    );

    sram_sync_sp #(.AWIDTH(3), .DWIDTH(32)) u_data_ram_w1 (
        .clock     (occ_clk),
        .addr      (sram_index),
        .din       (sram_wdata),
        .we        (sram_we1),
        .dout      (sram_rdata1),
        .bist_en   (sram_bist_en_d1),
        .bist_addr (sram_bist_addr),
        .bist_din  (sram_bist_din_data),
        .bist_we   (sram_bist_we),
        .bist_dout (sram_bist_dout_d1)
`ifndef SYNTHESIS
        , .inj_en(inj_en && (inj_bank == 2'd3)), .inj_addr(inj_addr), .inj_bit(inj_bit), .inj_type(inj_type)
`endif
    );
`else
    // 5-Stage Pipelined RV32I Core
    rv32i_processor u_rv32i_core (
        .clk      (occ_clk),
        .rst_n    (dft_rst_n),
        .prog_sel (core_prog_sel),
        .x14      (core_x14),
        .pc_obs   (core_pc_obs),
        .alu_obs  (core_alu_obs)
    );

    // 2-Way Set-Associative Cache + 4 SRAM Banks
    cache_2wsa_dft u_cache (
        .clock         (occ_clk),
        .reset_n       (dft_rst_n),
        .cpu_wdata     (cache_cpu_wdata),
        .cpu_rdata     (cache_cpu_rdata),
        .cpu_rdata_oe  (cache_cpu_rdata_oe),
        .addr_cpu      (cache_addr_cpu),
        .rd_cpu        (cache_rd_cpu),
        .wr_cpu        (cache_wr_cpu),
        .stall_cpu     (cache_stall_cpu),
        .mem_rdata     (cache_mem_rdata),
        .mem_wdata     (cache_mem_wdata),
        .mem_wdata_oe  (cache_mem_wdata_oe),
        .addr_mem      (cache_addr_mem),
        .rd_mem        (cache_rd_mem),
        .wr_mem        (cache_wr_mem),
        .ready_mem     (cache_ready_mem),
        .bist_en       (bist_en),
        .bist_bank_sel (bist_bank_sel),
        .bist_addr     (bist_addr),
        .bist_din      (bist_din),
        .bist_we       (bist_we),
        .bist_dout     (bist_dout)
`ifndef SYNTHESIS
        ,
        .inj_en        (inj_en),
        .inj_bank      (inj_bank),
        .inj_addr      (inj_addr),
        .inj_bit       (inj_bit),
        .inj_type      (inj_type)
`endif
    );
`endif

    // March-C MBIST Controller (runs on sys_clk)
    mbist_ctrl u_mbist_ctrl (
        .clk              (sys_clk),
        .rst_n            (sys_rst_n),
        .start_toggle     (mbist_start_toggle),
        .start_sync_pulse (1'b0),
        .bank_mask        (tdr_mbist_cmd[4:1]),
        .stop_on_fail     (tdr_mbist_cmd[5]),
        .pattern_mode     (tdr_mbist_cmd[7:6]),
        .bist_en          (bist_en),
        .bist_bank_sel    (bist_bank_sel),
        .bist_addr        (bist_addr),
        .bist_din         (bist_din),
        .bist_we          (bist_we),
        .bist_dout        (bist_dout),
        .bist_done        (bist_done),
        .bist_fail        (bist_fail),
        .mbist_stat       (mbist_stat)
    );

    // Scan Compression, Bypass & 16-bit MISR Wrapper
    scan_comp_wrap #(
        .N_EXT    (2),
        .N_CHAINS (8)
    ) u_scan_comp_wrap (
        .clk            (occ_clk),
        .rst_n          (dft_rst_n),
        .scan_en        (scan_en),
        .comp_en        (tdr_comp_cfg[0]),
        .misr_en        (tdr_comp_cfg[1]),
        .misr_clr       (tdr_comp_cfg[2]),
        .chain_x_mask   (tdr_comp_cfg[10:3]),
        .ext_scan_in    (scan_in),
        .ext_scan_out   (scan_out),
        .chain_scan_in  (chain_scan_in),
        .chain_scan_out (chain_scan_out),
        .misr_sig       (misr_sig)
    );

`ifndef POST_SCAN_STITCH
    // Pre-stitch RTL observation/surrogate scan chains (USE_EXT_SCAN_CHAINS=0):
    // 8 x 8-bit shift/capture segments observing live core & cache state.
    // Under POST_SCAN_STITCH, real gate-level scan chains drive chain_scan_out directly.
    generate
        if (USE_EXT_SCAN_CHAINS == 0) begin : g_rtl_scan_chains
            logic [7:0] sc_seg_q [0:7];
            wire  [63:0] obs_bus = {
                core_x14[15:0],
                core_pc_obs[15:0],
                core_alu_obs[15:0],
                cache_addr_mem[7:0],
                bist_done, bist_fail, cache_stall_cpu, cache_rd_mem,
                cache_wr_mem, w1500_intest_active, w1500_extest_active, core_prog_sel
            };

            genvar c;
            for (c = 0; c < 8; c = c + 1) begin : g_chain
                assign chain_scan_out[c] = sc_seg_q[c][0];
                always_ff @(posedge occ_clk or negedge dft_rst_n) begin
                    if (!dft_rst_n) begin
                        sc_seg_q[c] <= 8'd0;
                    end else if (eff_test_mode) begin
                        if (scan_en) begin
                            sc_seg_q[c] <= {chain_scan_in[c], sc_seg_q[c][7:1]};
                        end else begin
                            sc_seg_q[c] <= obs_bus[c*8 +: 8];
                        end
                    end
                end
            end
        end else begin : g_ext_chains
            assign chain_scan_out = 8'd0;
        end
    endgenerate
`endif

endmodule
