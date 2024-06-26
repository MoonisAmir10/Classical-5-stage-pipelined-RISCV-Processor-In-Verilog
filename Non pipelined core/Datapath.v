`include "Register File.v"
`include "ALU.v"
`include "input2_mux.v"
`include "imm_generate.v" 
`include "Data Memory.v"
`include "regfile_wb_mux.v"
`include "input1_mux.v"
`include "Branch Comparator.v"

module Datapath(
input [4:0]read_reg_r1,
input [4:0]read_reg_r2,
input [11:0]read_imm_12,
input [4:0]reg_write_dest,
input [3:0]alu_select,
input reg_write_en,
input clk,
input [1:0]imm_sel,
input bsel,
input asel,
input dm_write_en,
input wbsel,
input [31:0]pc,
input brun_en,
output breq_flag,
output brlt_flag,
output bge_flag,
output [31:0] alu_out
);

//internal wires
wire [31:0]read_data1;
wire [31:0]read_reg_data1;
wire [31:0]read_reg_data2;
wire [31:0]read_imm_data2;
wire [31:0]read_data2;
wire [31:0]write_data;
wire [31:0]dm_out;

//Instantiating the register file
RegFile regfile_inst(
.clk(clk),
.reg_write_en(reg_write_en),
.reg_write_dest_addr(reg_write_dest),
.reg_write_data(write_data),
.reg_read_addr_rs1(read_reg_r1),
.reg_read_data_rs1(read_reg_data1),
.reg_read_addr_rs2(read_reg_r2),
.reg_read_data_rs2(read_reg_data2)
);

//sign extension
imm_generate imm_gen_inst(
.imm_12(read_imm_12),
.reg_write_dest(reg_write_dest),
.imm_sel(imm_sel),
.read_imm_data2(read_imm_data2)
);

//choosing b/w R or I type
input2_mux input2_mux_inst(
.read_reg_data2(read_reg_data2),
.read_imm_data2(read_imm_data2),
.bsel(bsel),
.read_data2(read_data2)
);

//choosing whether B type or not
input1_mux input1_mux_inst(
.read_reg_data1(read_reg_data1),
.pc(pc),
.asel(asel),
.read_data1(read_data1)
);

//Instantiating Branch Comp
branch_comparator branc_comp_inst(
.inpA(read_reg_data1),
.inpB(read_reg_data2),
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
.dm_read_addr(alu_out),
.dm_write_data_rs2(read_reg_data2),
.dm_write_en(dm_write_en),
.clk(clk),
.dm_read_data(dm_out)
);

regfile_wb_mux wb_mux_inst(
.dm_inp(dm_out),
.alu_result(alu_out),
.wbsel(wbsel),
.write_data(write_data)
);

endmodule 