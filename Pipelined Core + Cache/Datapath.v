`timescale 1ns / 1ps

module Datapath(
    input  wire [4:0]  read_reg_r1,
    input  wire [4:0]  read_reg_r2,
    input  wire [11:0] read_imm_12,
    input  wire [4:0]  reg_write_dest,
    input  wire [4:0]  reg_write_dest_imm,
    input  wire [3:0]  alu_select,
    input  wire        reg_write_en,
    input  wire        clk,
    input  wire        reset,
    input  wire [1:0]  imm_sel,
    input  wire        bsel,
    input  wire        asel,
    input  wire [1:0]  ForwardAE,
    input  wire [1:0]  ForwardBE,
    input  wire        en_E,
    input  wire        en_M,
    input  wire        en_W,
    input  wire        flushE,
    input  wire        dm_read_en,
    input  wire        dm_write_en,
    input  wire [1:0]  wbsel,
    input  wire [31:0] pc,
    input  wire        brun_en,
    output wire        breq_flag,
    output wire        brlt_flag,
    output wire        bge_flag,
    output wire [31:0] alu_EX,
    output wire [31:0] alu_MEM,
    output wire        dcache_stall,
    output wire        dcache_hit,
    output wire        dcache_miss,
    output wire        dcache_wb,
    // Main memory master interface from integrated 2-way D-cache
    output wire [15:0] addr_mem,
    output wire [31:0] mem_wdata,
    input  wire [31:0] mem_rdata,
    output wire        rd_mem,
    output wire        wr_mem,
    input  wire        ready_mem,
    output wire [31:0] x14
);

wire [31:0] read_data1;
wire [31:0] read_reg_data1;
wire [31:0] read_reg_data2;
wire [31:0] read_imm_data2;
wire [31:0] read_data2;
wire [31:0] write_data;
wire [31:0] dm_out;
wire [31:0] alu_out;
wire [31:0] inp1_fwd_out, inp2_fwd_out;

// Pipeline registers
wire [31:0] pc_EX, pc_MEM, pc_MEM_plus4, pc_WB;
wire [31:0] rs1_EX, rs2_EX, rs2_MEM;
wire [31:0] imm_EX;
wire [31:0] alu_WB;
wire [31:0] dm_WB;

assign alu_EX = alu_out;

// PC pipeline
reg_pl pc_DE(
    .inp(pc),
    .clk(clk),
    .reset(reset),
    .en(en_E),
    .clear(flushE),
    .out(pc_EX)
);

reg_pl pc_E_MEM(
    .inp(pc_EX),
    .clk(clk),
    .reset(reset),
    .en(en_M),
    .clear(1'b0),
    .out(pc_MEM)
);

assign pc_MEM_plus4 = pc_MEM + 32'd4;

reg_pl pc_MEM_WB(
    .inp(pc_MEM_plus4),
    .clk(clk),
    .reset(reset),
    .en(en_W),
    .clear(1'b0),
    .out(pc_WB)
);

// RS1 and RS2 pipeline (rs2_E_MEM captures FORWARDED inp2_fwd_out for SW!)
reg_pl rs1_DE(
    .inp(read_reg_data1),
    .clk(clk),
    .reset(reset),
    .en(en_E),
    .clear(flushE),
    .out(rs1_EX)
);

reg_pl rs2_DE(
    .inp(read_reg_data2),
    .clk(clk),
    .reset(reset),
    .en(en_E),
    .clear(flushE),
    .out(rs2_EX)
);

reg_pl rs2_E_MEM(
    .inp(inp2_fwd_out),
    .clk(clk),
    .reset(reset),
    .en(en_M),
    .clear(1'b0),
    .out(rs2_MEM)
);

// Immediate pipeline
reg_pl imm_DE(
    .inp(read_imm_data2),
    .clk(clk),
    .reset(reset),
    .en(en_E),
    .clear(flushE),
    .out(imm_EX)
);

// ALU output pipeline
reg_pl alu_E_MEM(
    .inp(alu_out),
    .clk(clk),
    .reset(reset),
    .en(en_M),
    .clear(1'b0),
    .out(alu_MEM)
);

reg_pl alu_MEM_WB(
    .inp(alu_MEM),
    .clk(clk),
    .reset(reset),
    .en(en_W),
    .clear(1'b0),
    .out(alu_WB)
);

// Data cache output pipeline
reg_pl dm_MEM_WB(
    .inp(dm_out),
    .clk(clk),
    .reset(reset),
    .en(en_W),
    .clear(1'b0),
    .out(dm_WB)
);

// Register File (write gated by !dcache_stall so WB commits once on pipeline advance)
RegFile regfile_inst(
    .clk(clk),
    .reset(reset),
    .reg_write_en(reg_write_en && !dcache_stall),
    .reg_write_dest_addr(reg_write_dest),
    .reg_write_data(write_data),
    .reg_read_addr_rs1(read_reg_r1),
    .reg_read_data_rs1(read_reg_data1),
    .reg_read_addr_rs2(read_reg_r2),
    .reg_read_data_rs2(read_reg_data2),
    .x14(x14)
);

// Immediate Generator
imm_generate imm_gen_inst(
    .imm_12(read_imm_12),
    .reg_write_dest(reg_write_dest_imm),
    .imm_sel(imm_sel),
    .read_imm_data2(read_imm_data2)
);

// Operand B Forwarding + R/I Mux
mux_3_to_1 inp2_fwd(
    .a(rs2_EX),
    .b(write_data),
    .c(alu_MEM),
    .sel(ForwardBE),
    .out(inp2_fwd_out)
);

input2_mux input2_mux_inst(
    .read_reg_data2(inp2_fwd_out),
    .read_imm_data2(imm_EX),
    .bsel(bsel),
    .read_data2(read_data2)
);

// Operand A Forwarding + PC/Reg Mux
mux_3_to_1 inp1_fwd(
    .a(rs1_EX),
    .b(write_data),
    .c(alu_MEM),
    .sel(ForwardAE),
    .out(inp1_fwd_out)
);

input1_mux input1_mux_inst(
    .read_reg_data1(inp1_fwd_out),
    .pc(pc_EX),
    .asel(asel),
    .read_data1(read_data1)
);

// Branch Comparator
branch_comparator branc_comp_inst(
    .inpA(inp1_fwd_out),
    .inpB(inp2_fwd_out),
    .brun_en(brun_en),
    .breq_flag(breq_flag),
    .brlt_flag(brlt_flag),
    .bge_flag(bge_flag)
);

// ALU
ALU ALU_inst(
    .inp1(read_data1),
    .inp2(read_data2),
    .alu_select(alu_select),
    .alu_out(alu_out)
);

// Integrated 32-bit 2-Way Set-Associative Write-Back / Write-Allocate Data Cache
cache_2wsa dcache_inst(
    .clock(clk),
    .reset_n(reset),
    .addr_cpu(alu_MEM[15:0]),
    .cpu_wdata(rs2_MEM),
    .cpu_wstrb(4'b1111),
    .rd_cpu(dm_read_en),
    .wr_cpu(dm_write_en),
    .cpu_rdata(dm_out),
    .stall_cpu(dcache_stall),
    .addr_mem(addr_mem),
    .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata),
    .rd_mem(rd_mem),
    .wr_mem(wr_mem),
    .ready_mem(ready_mem),
    .cache_hit(dcache_hit),
    .cache_miss(dcache_miss),
    .cache_wb(dcache_wb)
);

// Writeback Mux
regfile_wb_mux wb_mux_inst(
    .dm_inp(dm_WB),
    .alu_result(alu_WB),
    .wbsel(wbsel),
    .pc(pc_WB),
    .write_data(write_data)
);

endmodule
