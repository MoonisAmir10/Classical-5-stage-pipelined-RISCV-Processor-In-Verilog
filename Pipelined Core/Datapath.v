`include "Register File.v"
`include "ALU.v"
`include "input2_mux.v"
`include "imm_generate.v" 
`include "Data Memory.v"
`include "regfile_wb_mux.v"
`include "input1_mux.v"
`include "Branch Comparator.v"

module Datapath(
input [4:0] read_reg_r1,
input [4:0] read_reg_r2,
input [11:0] read_imm_12,
input [4:0] reg_write_dest,
input [3:0] alu_select,
input reg_write_en,
input clk,
input reset,
input [1:0] imm_sel,
input bsel,
input asel,
input [1:0] ForwardAE,
input [1:0] ForwardBE,
input flushE,
input dm_write_en,
input [1:0] wbsel,
input [31:0] pc,
input brun_en,
output breq_flag,
output brlt_flag,
output bge_flag,
output [31:0] alu_MEM,
output [31:0] x14
);

//internal wires
wire [31:0]read_data1;
wire [31:0]read_reg_data1;
wire [31:0]read_reg_data2;
wire [31:0]read_imm_data2;
wire [31:0]read_data2;
wire [31:0]write_data;
wire [31:0]dm_out;
wire [31:0]alu_out;
//wire [31:0] x14;

wire [31:0] inp1_fwd_out, inp2_fwd_out;


///// Pipeline registers /////
wire [31:0] pc_EX, pc_MEM, pc_MEM_plus4, pc_WB;

wire [31:0] rs1_EX, rs2_EX, rs2_MEM;

wire [31:0] imm_EX;

wire [31:0] alu_WB;

wire [31:0] dm_WB;


///// Further pipelining PC /////
reg_pl pc_DE(
.inp(pc),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(flushE),
.out(pc_EX)
);

reg_pl pc_E_MEM(
.inp(pc_EX),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(1'b0),
.out(pc_MEM)
);

assign pc_MEM_plus4 = pc_MEM + 4;

reg_pl pc_MEM_WB(
.inp(pc_MEM_plus4),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(1'b0),
.out(pc_WB)
);


///// Pipelining rs1 and rs2 /////
reg_pl rs1_DE(
.inp(read_reg_data1),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(flushE),
.out(rs1_EX)
);

reg_pl rs2_DE(
.inp(read_reg_data2),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(flushE),
.out(rs2_EX)
);

reg_pl rs2_E_MEM(
.inp(rs2_EX),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(1'b0),
.out(rs2_MEM)
);


///// Pipelining immediate /////
reg_pl imm_DE(
.inp(read_imm_data2),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(flushE),
.out(imm_EX)
);


///// Pipelining alu output /////
reg_pl alu_E_MEM(
.inp(alu_out),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(1'b0),
.out(alu_MEM)
);

reg_pl alu_MEM_WB(
.inp(alu_MEM),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(1'b0),
.out(alu_WB)
);


///// Pipelining data mem output /////
reg_pl dm_MEM_WB(
.inp(dm_out),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(1'b0),
.out(dm_WB)
);



//Instantiating the register file
RegFile regfile_inst(
.clk(clk),
.reg_write_en(reg_write_en),
.reg_write_dest_addr(reg_write_dest),
.reg_write_data(write_data),
.reg_read_addr_rs1(read_reg_r1),
.reg_read_data_rs1(read_reg_data1),
.reg_read_addr_rs2(read_reg_r2),
.reg_read_data_rs2(read_reg_data2),
.x14(x14)
);

//sign extension
imm_generate imm_gen_inst(
.imm_12(read_imm_12),
.reg_write_dest(reg_write_dest),
.imm_sel(imm_sel),
.read_imm_data2(read_imm_data2)
);


// Forward control of input 2 of alu
mux_3_to_1 inp2_fwd(
.a(rs2_EX),
.b(write_data),
.c(alu_MEM),
.sel(ForwardBE),
.out(inp2_fwd_out)
);


//choosing b/w R or I type
input2_mux input2_mux_inst(
.read_reg_data2(inp2_fwd_out),
.read_imm_data2(imm_EX),
.bsel(bsel),
.read_data2(read_data2)
);


// Forward control of input 1 of alu
mux_3_to_1 inp1_fwd(
.a(rs1_EX),
.b(write_data),
.c(alu_MEM),
.sel(ForwardAE),
.out(inp1_fwd_out)
);


//choosing whether B type or not
input1_mux input1_mux_inst(
.read_reg_data1(inp1_fwd_out),
.pc(pc_EX),
.asel(asel),
.read_data1(read_data1)
);

//Instantiating Branch Comp
branch_comparator branc_comp_inst(
.inpA(rs1_EX),
.inpB(rs2_EX),
.brun_en(brun_en),
.breq_flag(breq_flag),
.brlt_flag(brlt_flag),
.bge_flag(bge_flag)
);

//Instantiating ALU
ALU ALU_inst(
.inp1(read_data1),
.inp2(read_data2),
.alu_select(alu_select),
.alu_out(alu_out)
);

DataMem RAM_inst(
.dm_read_addr(alu_MEM),
.dm_write_data_rs2(rs2_MEM),
.dm_write_en(dm_write_en),
.clk(clk),
.dm_read_data(dm_out)
);

regfile_wb_mux wb_mux_inst(
.dm_inp(dm_WB),
.alu_result(alu_WB),
.wbsel(wbsel),
.pc(pc_WB),
.write_data(write_data)
);

endmodule 