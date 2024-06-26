`include "Control Unit.v"
`include "Datapath.v"
`include "Program Counter.v"
`include "Instruction Memory.v"
`include "pc_mux.v"

module Processor( 
input clk, 
input reset,
output [31:0] x14 // Register to observe results of fibonacci sequence
);

wire [31:0] instr;
wire [3:0] alu_select;
wire reg_write_en;
wire [31:0] count;
wire [1:0] imm_sel;
wire bsel;
wire asel;
wire dm_write_en;
wire [1:0] wbsel;
wire breq_flag;
wire brlt_flag;
wire bge_flag;
wire brun_en;
wire pc_sel;
wire [31:0] alu_out;
wire [31:0] pc_update;


///// Pipeline registers /////
wire [31:0] instr_ID, instr_EX, instr_MEM, instr_WB;

wire [31:0] count_ID;

wire reg_write_en_E, reg_write_en_MEM, reg_write_en_WB;

wire dm_write_en_E, dm_write_en_MEM;

wire [3:0] alu_select_E;

wire busy;

wire bsel_E, asel_E;

wire [1:0] wbsel_E, wbsel_MEM, wbsel_WB;

wire brun_en_E;

wire pc_sel_E;
wire pc_sel_MEM;

wire [1:0] ForwardAE, ForwardBE;

wire stallF, stallD, stallE, flushD, flushE;



//assign stallF = 1'b1;
//assign stallD = 1'b1;
//assign flushD = 1'b0;
//assign flushE = 1'b0;
//assign ForwardAE = 2'b00;
//assign ForwardBE = 2'b00;



pc_mux pc_mux_inst(
.alu_out(alu_out),
.pc(count),
.pcsel(pc_sel_MEM),
.pc_update(pc_update)
);


///// PC and its registers /////
program_counter counter_inst(
.clk(clk),
.reset(reset),
.pc_update(pc_update),
.en(stallF),
.count(count)
);

reg_pl pc_FD(
.inp(count),
.clk(clk),
.reset(reset),
.en(stallD),
.clear(flushD),
.out(count_ID)
);


///// Instruction memory and its registers /////
InstrMem instrmem_inst(
.pc(count),
.instr(instr)
); 

reg_pl instr_FD(
.inp(instr),
.clk(clk),
.reset(reset),
.en(stallD),
.clear(flushD),
.out(instr_ID)
);

reg_pl instr_DE(
.inp(instr_ID),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(flushE),
.out(instr_EX)
);

reg_pl instr_E_MEM(
.inp(instr_EX),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(1'b0),
.out(instr_MEM)
);

reg_pl instr_MEM_WB(
.inp(instr_MEM),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(1'b0),
.out(instr_WB)
);


///// Pipelining control unit parameters /////

// RegWE
reg_pl #(.N(1)) reg_write_DE(
.inp(reg_write_en),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(flushE),
.out(reg_write_en_E)
);

reg_pl #(.N(1)) reg_write_E_MEM(
.inp(reg_write_en_E),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(1'b0),
.out(reg_write_en_MEM)
);

reg_pl #(.N(1)) reg_write_MEM_WB(
.inp(reg_write_en_MEM),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(1'b0),
.out(reg_write_en_WB)
);

// DM
reg_pl #(.N(1)) dm_write_DE(
.inp(dm_write_en),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(flushE),
.out(dm_write_en_E)
);

reg_pl #(.N(1)) dm_write_E_MEM(
.inp(dm_write_en_E),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(1'b0),
.out(dm_write_en_MEM)
);

// alu 
reg_pl #(.N(4)) alu_sel_E(
.inp(alu_select),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(flushE),
.out(alu_select_E)
);

reg_pl #(.N(1)) bsel_DE(
.inp(bsel),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(flushE),
.out(bsel_E)
);

reg_pl #(.N(1)) asel_DE(
.inp(asel),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(flushE),
.out(asel_E)
);

// Write back
reg_pl #(.N(2)) wbsel_DE(
.inp(wbsel),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(flushE),
.out(wbsel_E)
);

reg_pl #(.N(2)) wbsel_E_MEM(
.inp(wbsel_E),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(1'b0),
.out(wbsel_MEM)
);

reg_pl #(.N(2)) wbsel_MEM_WB(
.inp(wbsel_MEM),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(1'b0),
.out(wbsel_WB)
);

// branch unsigned sel
reg_pl #(.N(1)) brun_en_DE(
.inp(brun_en),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(flushE),
.out(brun_en_E)
);

// pc_sel
reg_pl #(.N(1)) pc_sel_DE(
.inp(pc_sel),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(flushE),
.out(pc_sel_E)
);

reg_pl #(.N(1)) pc_sel_E_MEM(
.inp(pc_sel_E),
.clk(clk),
.reset(reset),
.en(1'b1),
.clear(1'b0),
.out(pc_sel_MEM)
);


ControlUnit controlunit_inst(
.funct7(instr_ID[31:25]),
.funct3(instr_ID[14:12]),
.opcode(instr_ID[6:0]),
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

hazard_unit hu_inst(
.RegWriteM(reg_write_en_MEM),
.RegWriteW(reg_write_en_WB),
.wbsel_E(wbsel_E),
.pc_sel(pc_sel_E),
.RD_E(instr_EX[11:7]),
.RD_M(instr_MEM[11:7]),
.RD_W(instr_WB[11:7]),
.Rs1_D(instr_ID[19:15]),
.Rs1_E(instr_EX[19:15]),
.Rs2_D(instr_ID[24:20]),
.Rs2_E(instr_EX[24:20]),
.ForwardAE(ForwardAE),
.ForwardBE(ForwardBE),
.stallF(stallF),
.stallD(stallD),
.flushD(flushD),
.flushE(flushE)
);


Datapath datapath_inst(
.read_reg_r1(instr_ID[19:15]),
.read_reg_r2(instr_ID[24:20]),
.read_imm_12(instr_ID[31:20]),
.reg_write_dest(instr_WB[11:7]),
.alu_select(alu_select_E),
.reg_write_en(reg_write_en_WB),
.clk(clk),
.reset(reset),
.imm_sel(imm_sel),
.bsel(bsel_E),
.asel(asel_E),
.ForwardAE(ForwardAE),
.ForwardBE(ForwardBE),
.flushE(flushE),
.dm_write_en(dm_write_en_MEM),
.wbsel(wbsel_WB),
.pc(count_ID),
.brun_en(brun_en_E),
.breq_flag(breq_flag),
.brlt_flag(brlt_flag),
.bge_flag(bge_flag),
.alu_MEM(alu_out),
.x14(x14)
);

endmodule 