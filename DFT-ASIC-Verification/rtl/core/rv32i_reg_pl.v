`timescale 1ns/1ps

module rv32i_reg_pl #(
    parameter integer N = 32
) (
    input  wire [N-1:0] inp,
    input  wire         clk,
    input  wire         rst_n,
    input  wire         en,
    input  wire         clear,
    output reg  [N-1:0] out
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            out <= {N{1'b0}};
        else if (clear)
            out <= {N{1'b0}};
        else if (en)
            out <= inp;
    end
endmodule
