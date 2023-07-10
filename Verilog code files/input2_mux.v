module input2_mux(
input [31:0] read_reg_data2,
input [31:0] read_imm_data2,
input bsel,
output reg [31:0] read_data2
);

always @(*)
begin
  case(bsel)
   1'b0: read_data2 = read_reg_data2;
   1'b1: read_data2 = read_imm_data2;
  endcase 
end

endmodule 