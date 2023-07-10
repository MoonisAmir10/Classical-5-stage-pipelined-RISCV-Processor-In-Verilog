`include "Control Unit.v"
`include "Datapath.v"
`include "Program Counter.v"
`include "Instruction Memory.v"
`include "pc_mux.v"

module Processor( 
input clk, 
input reset
);

wire [31:0] instr;
wire [3:0] alu_select;
wire reg_write_en;
wire [31:0] count;
wire [1:0] imm_sel;
wire bsel;
wire asel;
wire dm_write_en;
wire wbsel;
wire breq_flag;
wire brlt_flag;
wire bge_flag;
wire brun_en;
wire pc_sel;
wire [31:0] alu_out;
wire [31:0] pc_update;

pc_mux pc_mux_inst(
.alu_out(alu_out),
.pc(count),
.pcsel(pc_sel),
.pc_update(pc_update)
);

program_counter counter_inst(
.clk(clk),
.reset(reset),
.pc_update(pc_update),
.count(count)
);

InstrMem instrmem_inst(
.pc(count),
.instr(instr)
); 

ControlUnit controlunit_inst(
.funct7(instr[31:25]),
.funct3(instr[14:12]),
.opcode(instr[6:0]),
.breq_flag(breq_flag),
.brlt_flag(brlt_flag),
.bge_flag(bge_flag),
.alu_select(alu_select),
.reg_write_en(reg_write_en),
.imm_sel(imm_sel),
.bsel(bsel),
.asel(asel),
.dm_write_en(dm_write_en),
.wbsel(wbsel),
.brun_en(brun_en),
.pc_sel(pc_sel)
);

Datapath datapath_inst(
.read_reg_r1(instr[19:15]),
.read_reg_r2(instr[24:20]),
.read_imm_12(instr[31:20]),
.reg_write_dest(instr[11:7]),
.alu_select(alu_select),
.reg_write_en(reg_write_en),
.clk(clk),
.imm_sel(imm_sel),
.bsel(bsel),
.asel(asel),
.dm_write_en(dm_write_en),
.wbsel(wbsel),
.pc(count),
.brun_en(brun_en),
.breq_flag(breq_flag),
.brlt_flag(brlt_flag),
.bge_flag(bge_flag),
.alu_out(alu_out)
);

endmodule 