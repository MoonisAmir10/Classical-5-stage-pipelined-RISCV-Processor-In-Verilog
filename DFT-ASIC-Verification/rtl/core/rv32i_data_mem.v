`timescale 1ns/1ps

module rv32i_data_mem #(
    parameter integer AWIDTH = 4
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] dm_read_addr,
    input  wire [31:0] dm_write_data_rs2,
    input  wire        dm_write_en,
    output wire [31:0] dm_read_data
);
    localparam integer DEPTH = (1 << AWIDTH);
    reg [31:0] memory [0:DEPTH-1];
    wire [AWIDTH-1:0] ram_addr = dm_read_addr[AWIDTH-1:0];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < DEPTH; i = i + 1) begin
                memory[i] <= 32'd0;
            end
        end else if (dm_write_en) begin
            memory[ram_addr] <= dm_write_data_rs2;
        end
    end

    assign dm_read_data = memory[ram_addr];
endmodule
