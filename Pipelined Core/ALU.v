module ALU(
input [31:0] inp1, //can be Reg[rs1]
input [31:0] inp2, //can be Reg[rs2] or imm
input [3:0] alu_select, //selecting operation type
output reg [31:0] alu_out
);

always @(*)
begin
  case(alu_select)
  4'b0000: alu_out = inp1 + inp2; //add
  4'b0001: alu_out = inp1 - inp2; //sub
  4'b0010:  begin 
             if(inp1 < inp2) //slt
              alu_out = 1;
             else
              alu_out = 0;
            end
  4'b0011: alu_out = inp1 >>> inp2; //SRA
  4'b0100: alu_out = inp1 << inp2; //SLL
  4'b0101: alu_out = inp1 >> inp2; //SRL
  4'b0110: alu_out = inp1 | inp2; //or
  4'b0111: alu_out = inp1 & inp2; //and
  4'b1000: alu_out = inp1 ^ inp2; //xor
  default: alu_out = inp1 + inp2; 
  endcase
end

endmodule


//module tb_alu;
//
//reg [31:0] inp1;
//reg [31:0] inp2;
//reg [3:0] alu_select;
//wire [31:0] alu_out;
//
//ALU ALU_inst(
//.inp1(inp1),
//.inp2(inp2),
//.alu_select(alu_select),
//.alu_out(alu_out)
//);
//
//initial
//begin
//
//inp1 = 12;
//inp2 = 15;
//alu_select = 0;
//
//#1
//alu_select = 4'b0001;
//#1
//alu_select = 4'b0110;
//#1
//alu_select = 4'b0111;
//#1
//alu_select = 4'b0010;
//#1
//alu_select = 4'b0100;
//
//$stop;
//
//end
//endmodule
     
