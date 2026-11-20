`timescale 1ns/1ps

// Pure standard-cell functional SoC logic integrating the 5-stage RV32I core
// directly with the 32-bit 2-way set-associative D-cache controller, with
// exposed SRAM macro ports for ATPG cut, N-chain scan stitching, and MBIST.
module soc_func_logic (
    input  wire        clk,
    input  wire        rst_n,

    // RV32I processor interface (IEEE 1500 wrapped)
    input  wire        prog_sel,
    output wire [31:0] x14,
    output wire [31:0] pc_obs,
    output wire [31:0] alu_obs,

    // External 32-bit Main-Memory master bus & D-cache status
    input  wire [31:0] cache_mem_rdata,
    output wire [31:0] cache_mem_wdata,
    output wire [15:0] cache_addr_mem,
    output wire        cache_rd_mem,
    output wire        cache_wr_mem,
    input  wire        cache_ready_mem,
    output wire        cache_stall_cpu,
    output wire        cache_hit,
    output wire        cache_miss,
    output wire        cache_wb,

    // MBIST bus
    input  wire        bist_en,
    input  wire [1:0]  bist_bank_sel,
    input  wire [2:0]  bist_addr,
    input  wire [31:0] bist_din,
    input  wire        bist_we,
    output wire [31:0] bist_dout,

    // Exposed SRAM interfaces (14b tag + 32b data)
    output wire [2:0]  sram_index,
    output wire [13:0] sram_wtag0,
    output wire [13:0] sram_wtag1,
    output wire        sram_wet0,
    output wire        sram_wet1,
    output wire [31:0] sram_wdata,
    output wire        sram_we0,
    output wire        sram_we1,
    input  wire [13:0] sram_rtag0,
    input  wire [13:0] sram_rtag1,
    input  wire [31:0] sram_rdata0,
    input  wire [31:0] sram_rdata1,

    output wire        sram_bist_en_t0,
    output wire        sram_bist_en_t1,
    output wire        sram_bist_en_d0,
    output wire        sram_bist_en_d1,
    output wire [2:0]  sram_bist_addr,
    output wire [13:0] sram_bist_din_tag,
    output wire [31:0] sram_bist_din_data,
    output wire        sram_bist_we,
    input  wire [13:0] sram_bist_dout_t0,
    input  wire [13:0] sram_bist_dout_t1,
    input  wire [31:0] sram_bist_dout_d0,
    input  wire [31:0] sram_bist_dout_d1
);
    // Internal RV32I MEM-stage <-> 2-Way D-Cache bus
    wire [15:0] cpu_dcache_addr;
    wire [31:0] cpu_dcache_wdata;
    wire [3:0]  cpu_dcache_wstrb;
    wire        cpu_dcache_rd;
    wire        cpu_dcache_wr;
    wire [31:0] cpu_dcache_rdata;
    wire        cpu_dcache_stall;

    assign cache_stall_cpu = cpu_dcache_stall;

    rv32i_processor u_rv32i_core (
        .clk          (clk),
        .rst_n        (rst_n),
        .prog_sel     (prog_sel),
        .dcache_addr  (cpu_dcache_addr),
        .dcache_wdata (cpu_dcache_wdata),
        .dcache_wstrb (cpu_dcache_wstrb),
        .dcache_rd    (cpu_dcache_rd),
        .dcache_wr    (cpu_dcache_wr),
        .dcache_rdata (cpu_dcache_rdata),
        .dcache_stall (cpu_dcache_stall),
        .x14          (x14),
        .pc_obs       (pc_obs),
        .alu_obs      (alu_obs)
    );

    cache_ctrl_logic u_cache_ctrl (
        .clock              (clk),
        .reset_n            (rst_n),
        .addr_cpu           (cpu_dcache_addr),
        .cpu_wdata          (cpu_dcache_wdata),
        .cpu_wstrb          (cpu_dcache_wstrb),
        .rd_cpu             (cpu_dcache_rd),
        .wr_cpu             (cpu_dcache_wr),
        .cpu_rdata          (cpu_dcache_rdata),
        .stall_cpu          (cpu_dcache_stall),
        .addr_mem           (cache_addr_mem),
        .mem_wdata          (cache_mem_wdata),
        .mem_rdata          (cache_mem_rdata),
        .rd_mem             (cache_rd_mem),
        .wr_mem             (cache_wr_mem),
        .ready_mem          (cache_ready_mem),
        .cache_hit          (cache_hit),
        .cache_miss         (cache_miss),
        .cache_wb           (cache_wb),
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

endmodule
