module regfile_wb_mux(
input [31:0] dm_inp,
input [31:0] alu_result,
input wbsel,
output reg [31:0] write_data
);

always @(*)
begin
  case(wbsel)
   1'b0: write_data = dm_inp;
   1'b1: write_data = alu_result;
  endcase 
end 

endmodule 