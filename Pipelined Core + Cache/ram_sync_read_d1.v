`timescale 1ns / 1ps

/*
============================
Parameterized Single Port RAM (Cache Data Way 1)
============================
*/

module ram_sync_read_d1 #(
    parameter AWIDTH = 3,    // Address width (DEPTH = 2^AWIDTH = 8 sets)
    parameter DWIDTH = 32    // Data width (32-bit cache line = 1 word)
)(
    input  wire              clock,
    input  wire [AWIDTH-1:0] addr,
    input  wire [DWIDTH-1:0] din,
    input  wire              we,
    output wire [DWIDTH-1:0] dout
);

localparam DEPTH = 1 << AWIDTH;

reg [DWIDTH-1:0] mem_array [0:DEPTH-1];
reg [AWIDTH-1:0] rd_addr;

`ifndef SYNTHESIS
integer i;
initial begin
    for (i = 0; i < DEPTH; i = i + 1)
        mem_array[i] = {DWIDTH{1'b0}};
    rd_addr = {AWIDTH{1'b0}};
end
`endif

always @(posedge clock) begin
    if (we)
        mem_array[addr] <= din;
    rd_addr <= addr;
end

assign dout = mem_array[rd_addr];

endmodule
