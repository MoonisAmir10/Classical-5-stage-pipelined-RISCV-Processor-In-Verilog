module reg_pl #(parameter N = 32) (inp,clk,reset,en,clear,out);

input [N-1:0] inp;
input clk, reset, en, clear;
output reg [N-1:0] out;

always@(posedge clk, negedge reset)
begin
  if (!reset)
    out <= 0;
  else if (clear)
    out <= 0;
  else if (en)
    out <= inp;
end

endmodule