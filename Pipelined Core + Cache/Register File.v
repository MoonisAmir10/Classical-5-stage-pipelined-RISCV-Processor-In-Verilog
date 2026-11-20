`timescale 1ns / 1ps

module RegFile(
    input  wire        clk,
    input  wire        reset,
    input  wire        reg_write_en,
    input  wire [4:0]  reg_write_dest_addr,
    input  wire [31:0] reg_write_data,
    input  wire [4:0]  reg_read_addr_rs1,
    output wire [31:0] reg_read_data_rs1,
    input  wire [4:0]  reg_read_addr_rs2,
    output wire [31:0] reg_read_data_rs2,
    output wire [31:0] x14
);

reg [31:0] reg_array [1:31];
integer i;

always @(posedge clk or negedge reset) begin
    if (!reset) begin
        for (i = 1; i < 32; i = i + 1)
            reg_array[i] <= 32'd0;
    end else if (reg_write_en && (reg_write_dest_addr != 5'd0)) begin
        reg_array[reg_write_dest_addr] <= reg_write_data;
    end
end

// Hardwired x0 == 0 with WB-to-ID internal write-first bypass
assign reg_read_data_rs1 = (reg_read_addr_rs1 == 5'd0) ? 32'd0 :
                           (reg_write_en && (reg_write_dest_addr == reg_read_addr_rs1)) ? reg_write_data :
                           reg_array[reg_read_addr_rs1];

assign reg_read_data_rs2 = (reg_read_addr_rs2 == 5'd0) ? 32'd0 :
                           (reg_write_en && (reg_write_dest_addr == reg_read_addr_rs2)) ? reg_write_data :
                           reg_array[reg_read_addr_rs2];

assign x14 = reg_array[14];

endmodule
