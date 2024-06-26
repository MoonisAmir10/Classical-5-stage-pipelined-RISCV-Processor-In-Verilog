module input1_mux(
input [31:0] read_reg_data1,
input [31:0] pc,
input asel,
output reg [31:0] read_data1
);

always @(*)
begin
  case(asel)
   1'b0: read_data1 = read_reg_data1;
   1'b1: read_data1 = pc;
  endcase 
end

endmodule 
