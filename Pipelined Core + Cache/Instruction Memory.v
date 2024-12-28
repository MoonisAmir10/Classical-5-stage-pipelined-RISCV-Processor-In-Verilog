module InstrMem(
input [31:0] pc,
output reg [31:0] instr
);

//define the memory size in bytes
`define MEM_SIZE 256

//define the number of rows and columns in the array
`define ROWS (`MEM_SIZE / 4)

reg [31:0] memory [`ROWS - 1:0];
wire [4:0] instr_addr = pc[6:2]; //there are only (MEM_SIZE / 4) locations


//// Convenient for simulation, but not synthesizable
//initial
// begin
//  //assigning instructions
//  $readmemh("instrmem.prog", memory,0,5);
// end
 
// Synthesizable memory initialization using a case statement
// Code is for fibonacci sequence generation. Result is stored in x14.
  always @(*) begin
    case (instr_addr)
      5'd0: instr = 32'h00060613; 
      5'd1: instr = 32'h00168693;
      5'd2: instr = 32'h00C68733;
      5'd3: instr = 32'h00068613;
      5'd4: instr = 32'h00070693;
      5'd5: instr = 32'hFE06DAE3;
      default: instr = 32'h00000013; // Default (NOP)
    endcase
  end

//// ONLY USE IN SIMULATION
//always @(*)
//  instr = memory[instr_addr]; 

endmodule



//module tb_instrmem;
//
//reg [31:0] pc;
//wire [31:0] instr;
//
//InstrMem instrmem_inst(
//.pc(pc),
//.instr(instr)
//); 
//
//initial
//begin
//
//pc = 32'd0;
//#1
//pc = 32'd4;
//#1
//pc = 32'd8;
//$stop;
//
//end
//endmodule
