`timescale 1ns/1ps

// DFT-ready 2-way set-associative cache subsystem:
// wraps standard-cell cache_ctrl_logic together with 4 sram_sync_sp macros.
module cache_2wsa_dft #(
    parameter integer AWIDTH    = 16,
    parameter integer DWIDTH    = 8,
    parameter integer BLOCKSIZE = 4,
    parameter integer VALIDBIT  = 1,
    parameter integer DIRTYBIT  = 1,
    parameter integer USEDBIT   = 1,
    parameter integer TAGWIDTH  = 11
) (
    input  wire                        clock,
    input  wire                        reset_n,

    // Unidirectional CPU interface
    input  wire [DWIDTH-1:0]           cpu_wdata,
    output wire [DWIDTH-1:0]           cpu_rdata,
    output wire                        cpu_rdata_oe,
    input  wire [AWIDTH-1:0]           addr_cpu,
    input  wire                        rd_cpu,
    input  wire                        wr_cpu,
    output wire                        stall_cpu,

    // Unidirectional Main Memory interface
    input  wire [DWIDTH-1:0]           mem_rdata,
    output wire [DWIDTH-1:0]           mem_wdata,
    output wire                        mem_wdata_oe,
    output wire [AWIDTH-1:0]           addr_mem,
    output wire                        rd_mem,
    output wire                        wr_mem,
    input  wire                        ready_mem,

    // MBIST interface (controls all 4 cache SRAM banks: 0=t0, 1=t1, 2=d0, 3=d1)
    input  wire                        bist_en,
    input  wire [1:0]                  bist_bank_sel,
    input  wire [2:0]                  bist_addr,
    input  wire [31:0]                 bist_din,
    input  wire                        bist_we,
    output wire [31:0]                 bist_dout
`ifndef SYNTHESIS
    ,
    // Simulation-only SRAM fault injection interface
    input  wire                        inj_en,
    input  wire [1:0]                  inj_bank,
    input  wire [2:0]                  inj_addr,
    input  wire [5:0]                  inj_bit,
    input  wire [1:0]                  inj_type
`endif
);
    localparam integer TAG_ENTRY_W = VALIDBIT + USEDBIT + DIRTYBIT + TAGWIDTH; // 14
    localparam integer LINE_W      = DWIDTH * BLOCKSIZE;                      // 32

    wire [2:0]             sram_index;
    wire [TAG_ENTRY_W-1:0] sram_wtag0, sram_wtag1, sram_rtag0, sram_rtag1;
    wire                   sram_wet0, sram_wet1, sram_we0, sram_we1;
    wire [LINE_W-1:0]      sram_wdata, sram_rdata0, sram_rdata1;

    wire                   sram_bist_en_t0, sram_bist_en_t1, sram_bist_en_d0, sram_bist_en_d1;
    wire [2:0]             sram_bist_addr;
    wire [TAG_ENTRY_W-1:0] sram_bist_din_tag, sram_bist_dout_t0, sram_bist_dout_t1;
    wire [31:0]            sram_bist_din_data;
    wire [LINE_W-1:0]      sram_bist_dout_d0, sram_bist_dout_d1;
    wire                   sram_bist_we;

    cache_ctrl_logic #(
        .AWIDTH    (AWIDTH),
        .DWIDTH    (DWIDTH),
        .BLOCKSIZE (BLOCKSIZE),
        .VALIDBIT  (VALIDBIT),
        .DIRTYBIT  (DIRTYBIT),
        .USEDBIT   (USEDBIT),
        .TAGWIDTH  (TAGWIDTH)
    ) u_ctrl (
        .clock              (clock),
        .reset_n            (reset_n),
        .cpu_wdata          (cpu_wdata),
        .cpu_rdata          (cpu_rdata),
        .cpu_rdata_oe       (cpu_rdata_oe),
        .addr_cpu           (addr_cpu),
        .rd_cpu             (rd_cpu),
        .wr_cpu             (wr_cpu),
        .stall_cpu          (stall_cpu),
        .mem_rdata          (mem_rdata),
        .mem_wdata          (mem_wdata),
        .mem_wdata_oe       (mem_wdata_oe),
        .addr_mem           (addr_mem),
        .rd_mem             (rd_mem),
        .wr_mem             (wr_mem),
        .ready_mem          (ready_mem),
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
        .sram_bist_dout_d1  (sram_bist_dout_d1)
    );

    sram_sync_sp #(.AWIDTH(3), .DWIDTH(TAG_ENTRY_W)) u_tag_ram_w0 (
        .clock     (clock),
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
        ,
        .inj_en    (inj_en && (inj_bank == 2'd0)),
        .inj_addr  (inj_addr),
        .inj_bit   (inj_bit),
        .inj_type  (inj_type)
`endif
    );

    sram_sync_sp #(.AWIDTH(3), .DWIDTH(TAG_ENTRY_W)) u_tag_ram_w1 (
        .clock     (clock),
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
        ,
        .inj_en    (inj_en && (inj_bank == 2'd1)),
        .inj_addr  (inj_addr),
        .inj_bit   (inj_bit),
        .inj_type  (inj_type)
`endif
    );

    sram_sync_sp #(.AWIDTH(3), .DWIDTH(LINE_W)) u_data_ram_w0 (
        .clock     (clock),
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
        ,
        .inj_en    (inj_en && (inj_bank == 2'd2)),
        .inj_addr  (inj_addr),
        .inj_bit   (inj_bit),
        .inj_type  (inj_type)
`endif
    );

    sram_sync_sp #(.AWIDTH(3), .DWIDTH(LINE_W)) u_data_ram_w1 (
        .clock     (clock),
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
        ,
        .inj_en    (inj_en && (inj_bank == 2'd3)),
        .inj_addr  (inj_addr),
        .inj_bit   (inj_bit),
        .inj_type  (inj_type)
`endif
    );

endmodule
