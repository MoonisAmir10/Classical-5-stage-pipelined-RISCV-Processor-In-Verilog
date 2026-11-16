`timescale 1ns/1ps

module rv32i_pc (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire [31:0] pc_update,
    output reg  [31:0] count
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            count <= 32'd0;
        else if (en)
            count <= pc_update;
    end
endmodule
