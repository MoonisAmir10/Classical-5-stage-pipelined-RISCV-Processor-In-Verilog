`timescale 1ns / 1ps

module Processor #(
    parameter PROG_SEL    = 0,
    parameter MEM_LATENCY = 4
)(
    input  wire        clk,
    input  wire        reset,
    output wire [31:0] x14
);

wire [31:0] instr;
wire [3:0]  alu_select;
wire        reg_write_en;
wire [31:0] count;
wire [1:0]  imm_sel;
wire        bsel;
wire        asel;
wire        dm_read_en;
wire        dm_write_en;
wire [1:0]  wbsel;
wire        breq_flag;
wire        brlt_flag;
wire        bge_flag;
wire        brun_en;
wire        pc_sel;
wire [31:0] alu_EX;
wire [31:0] alu_MEM;
wire [31:0] branch_target;
wire [31:0] pc_update;

// Pipeline registers
wire [31:0] instr_ID, instr_EX, instr_MEM, instr_WB;
wire [31:0] count_ID;

wire        reg_write_en_E, reg_write_en_MEM, reg_write_en_WB;
wire        dm_read_en_E, dm_read_en_MEM;
wire        dm_write_en_E, dm_write_en_MEM;
wire [3:0]  alu_select_E;
wire        bsel_E, asel_E;
wire [1:0]  wbsel_E, wbsel_MEM, wbsel_WB;

wire [1:0]  ForwardAE, ForwardBE;
wire        en_F, en_D, en_E, en_M, en_W, flushD, flushE;

// Integrated D-cache <-> Main Memory wires
wire        dcache_stall;
wire        dcache_hit;
wire        dcache_miss;
wire        dcache_wb;
wire [15:0] addr_mem;
wire [31:0] mem_wdata;
wire [31:0] mem_rdata;
wire        rd_mem;
wire        wr_mem;
wire        ready_mem;

// Clear LSB on JALR per RV32I spec; branch targets already have LSB == 0
assign branch_target = (instr_EX[6:0] == 7'b1100111) ? {alu_EX[31:1], 1'b0} : alu_EX;

pc_mux pc_mux_inst(
    .alu_out(branch_target),
    .pc(count),
    .pcsel(pc_sel),
    .pc_update(pc_update)
);

// PC and IF/ID PC register
program_counter counter_inst(
    .clk(clk),
    .reset(reset),
    .pc_update(pc_update),
    .en(en_F),
    .count(count)
);

reg_pl pc_FD(
    .inp(count),
    .clk(clk),
    .reset(reset),
    .en(en_D),
    .clear(flushD),
    .out(count_ID)
);

// Instruction memory and pipeline registers
InstrMem #(.PROG_SEL(PROG_SEL)) instrmem_inst(
    .pc(count),
    .instr(instr)
);

reg_pl instr_FD(
    .inp(instr),
    .clk(clk),
    .reset(reset),
    .en(en_D),
    .clear(flushD),
    .out(instr_ID)
);

reg_pl instr_DE(
    .inp(instr_ID),
    .clk(clk),
    .reset(reset),
    .en(en_E),
    .clear(flushE),
    .out(instr_EX)
);

reg_pl instr_E_MEM(
    .inp(instr_EX),
    .clk(clk),
    .reset(reset),
    .en(en_M),
    .clear(1'b0),
    .out(instr_MEM)
);

reg_pl instr_MEM_WB(
    .inp(instr_MEM),
    .clk(clk),
    .reset(reset),
    .en(en_W),
    .clear(1'b0),
    .out(instr_WB)
);

// Pipelining control signals
reg_pl #(.N(1)) reg_write_DE(
    .inp(reg_write_en),
    .clk(clk),
    .reset(reset),
    .en(en_E),
    .clear(flushE),
    .out(reg_write_en_E)
);

reg_pl #(.N(1)) reg_write_E_MEM(
    .inp(reg_write_en_E),
    .clk(clk),
    .reset(reset),
    .en(en_M),
    .clear(1'b0),
    .out(reg_write_en_MEM)
);

reg_pl #(.N(1)) reg_write_MEM_WB(
    .inp(reg_write_en_MEM),
    .clk(clk),
    .reset(reset),
    .en(en_W),
    .clear(1'b0),
    .out(reg_write_en_WB)
);

// Data Memory / Cache Read & Write Enables
reg_pl #(.N(1)) dm_read_DE(
    .inp(dm_read_en),
    .clk(clk),
    .reset(reset),
    .en(en_E),
    .clear(flushE),
    .out(dm_read_en_E)
);

reg_pl #(.N(1)) dm_read_E_MEM(
    .inp(dm_read_en_E),
    .clk(clk),
    .reset(reset),
    .en(en_M),
    .clear(1'b0),
    .out(dm_read_en_MEM)
);

reg_pl #(.N(1)) dm_write_DE(
    .inp(dm_write_en),
    .clk(clk),
    .reset(reset),
    .en(en_E),
    .clear(flushE),
    .out(dm_write_en_E)
);

reg_pl #(.N(1)) dm_write_E_MEM(
    .inp(dm_write_en_E),
    .clk(clk),
    .reset(reset),
    .en(en_M),
    .clear(1'b0),
    .out(dm_write_en_MEM)
);

// ALU control
reg_pl #(.N(4)) alu_sel_E(
    .inp(alu_select),
    .clk(clk),
    .reset(reset),
    .en(en_E),
    .clear(flushE),
    .out(alu_select_E)
);

reg_pl #(.N(1)) bsel_DE(
    .inp(bsel),
    .clk(clk),
    .reset(reset),
    .en(en_E),
    .clear(flushE),
    .out(bsel_E)
);

reg_pl #(.N(1)) asel_DE(
    .inp(asel),
    .clk(clk),
    .reset(reset),
    .en(en_E),
    .clear(flushE),
    .out(asel_E)
);

// Writeback select
reg_pl #(.N(2)) wbsel_DE(
    .inp(wbsel),
    .clk(clk),
    .reset(reset),
    .en(en_E),
    .clear(flushE),
    .out(wbsel_E)
);

reg_pl #(.N(2)) wbsel_E_MEM(
    .inp(wbsel_E),
    .clk(clk),
    .reset(reset),
    .en(en_M),
    .clear(1'b0),
    .out(wbsel_MEM)
);

reg_pl #(.N(2)) wbsel_MEM_WB(
    .inp(wbsel_MEM),
    .clk(clk),
    .reset(reset),
    .en(en_W),
    .clear(1'b0),
    .out(wbsel_WB)
);

ControlUnit controlunit_inst(
    .funct7(instr_ID[31:25]),
    .funct3(instr_ID[14:12]),
    .funct3_EX(instr_EX[14:12]),
    .opcode(instr_ID[6:0]),
    .opcode_EX(instr_EX[6:0]),
    .breq_flag(breq_flag),
    .brlt_flag(brlt_flag),
    .bge_flag(bge_flag),
    .alu_select(alu_select),
    .reg_write_en(reg_write_en),
    .imm_sel(imm_sel),
    .bsel(bsel),
    .asel(asel),
    .dm_read_en(dm_read_en),
    .dm_write_en(dm_write_en),
    .wbsel(wbsel),
    .brun_en(brun_en),
    .pc_sel(pc_sel)
);

hazard_unit hu_inst(
    .RegWriteM(reg_write_en_MEM),
    .RegWriteW(reg_write_en_WB),
    .wbsel_E(wbsel_E),
    .pc_sel(pc_sel),
    .dcache_stall(dcache_stall),
    .RD_E(instr_EX[11:7]),
    .RD_M(instr_MEM[11:7]),
    .RD_W(instr_WB[11:7]),
    .Rs1_D(instr_ID[19:15]),
    .Rs1_E(instr_EX[19:15]),
    .Rs2_D(instr_ID[24:20]),
    .Rs2_E(instr_EX[24:20]),
    .ForwardAE(ForwardAE),
    .ForwardBE(ForwardBE),
    .en_F(en_F),
    .en_D(en_D),
    .en_E(en_E),
    .en_M(en_M),
    .en_W(en_W),
    .flushD(flushD),
    .flushE(flushE)
);

Datapath datapath_inst(
    .read_reg_r1(instr_ID[19:15]),
    .read_reg_r2(instr_ID[24:20]),
    .read_imm_12(instr_ID[31:20]),
    .reg_write_dest(instr_WB[11:7]),
    .reg_write_dest_imm(instr_ID[11:7]),
    .alu_select(alu_select_E),
    .reg_write_en(reg_write_en_WB),
    .clk(clk),
    .reset(reset),
    .imm_sel(imm_sel),
    .bsel(bsel_E),
    .asel(asel_E),
    .ForwardAE(ForwardAE),
    .ForwardBE(ForwardBE),
    .en_E(en_E),
    .en_M(en_M),
    .en_W(en_W),
    .flushE(flushE),
    .dm_read_en(dm_read_en_MEM),
    .dm_write_en(dm_write_en_MEM),
    .wbsel(wbsel_WB),
    .pc(count_ID),
    .brun_en(brun_en),
    .breq_flag(breq_flag),
    .brlt_flag(brlt_flag),
    .bge_flag(bge_flag),
    .alu_EX(alu_EX),
    .alu_MEM(alu_MEM),
    .dcache_stall(dcache_stall),
    .dcache_hit(dcache_hit),
    .dcache_miss(dcache_miss),
    .dcache_wb(dcache_wb),
    .addr_mem(addr_mem),
    .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata),
    .rd_mem(rd_mem),
    .wr_mem(wr_mem),
    .ready_mem(ready_mem),
    .x14(x14)
);

main_memory #(
    .WORD_BITS(10),
    .LATENCY(MEM_LATENCY)
) main_mem_inst (
    .clk(clk),
    .rst_n(reset),
    .read_mem(rd_mem),
    .write_mem(wr_mem),
    .addr_mem(addr_mem),
    .wdata_mem(mem_wdata),
    .rdata_mem(mem_rdata),
    .ready_mem(ready_mem)
);

endmodule
