module pc_mux(
input [31:0] alu_out,
input [31:0] pc,
input pcsel,
output reg [31:0] pc_update
);

always @(*)
begin
  case(pcsel)
   1'b0: pc_update = pc + 4;
   1'b1: pc_update = alu_out;
  endcase 
end

endmodule 