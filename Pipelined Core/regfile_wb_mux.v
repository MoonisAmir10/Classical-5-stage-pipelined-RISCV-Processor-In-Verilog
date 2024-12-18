module regfile_wb_mux(
input [31:0] dm_inp,
input [31:0] alu_result,
input [31:0] pc,
input [1:0] wbsel,
output reg [31:0] write_data
);

always @(*)
begin
  case(wbsel)
   2'b00: write_data = alu_result;
   2'b01: write_data = dm_inp;
   2'b10: write_data = pc + 4;
   default: write_data = dm_inp;
  endcase 
end 

endmodule 