`timescale 1ns / 1ps

// Synchronous 32-bit word-addressed backing memory with configurable latency
// Handshake: holds ready_mem=0 while idle/busy, pulses ready_mem=1 for 1 clock
// cycle upon read/write completion.
module main_memory #(
    parameter AWIDTH    = 16,
    parameter DWIDTH    = 32,
    parameter WORD_BITS = 10, // 2^10 = 1024 words (4 KB default; override up to 14 = 64 KB)
    parameter LATENCY   = 4   // >= 1 clock cycles
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              read_mem,
    input  wire              write_mem,
    input  wire [AWIDTH-1:0] addr_mem,
    input  wire [DWIDTH-1:0] wdata_mem,
    output reg  [DWIDTH-1:0] rdata_mem,
    output reg               ready_mem
);

localparam DEPTH = 1 << WORD_BITS;

reg [DWIDTH-1:0]    memory [0:DEPTH-1];
reg                 busy;
reg                 is_write;
reg [WORD_BITS-1:0] lat_addr;
reg [DWIDTH-1:0]    lat_wdata;
reg [7:0]           cycle_cnt;

wire [WORD_BITS-1:0] word_addr = addr_mem[WORD_BITS+1:2];

`ifndef SYNTHESIS
integer i;
initial begin
    for (i = 0; i < DEPTH; i = i + 1)
        memory[i] = 32'd0;
end
`endif

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ready_mem <= 1'b0;
        rdata_mem <= {DWIDTH{1'b0}};
        busy      <= 1'b0;
        is_write  <= 1'b0;
        lat_addr  <= {WORD_BITS{1'b0}};
        lat_wdata <= {DWIDTH{1'b0}};
        cycle_cnt <= 8'd0;
    end else begin
        ready_mem <= 1'b0;

        if (!busy) begin
            if (!ready_mem && (read_mem || write_mem)) begin
                if (LATENCY <= 1) begin
                    if (write_mem)
                        memory[word_addr] <= wdata_mem;
                    else
                        rdata_mem <= memory[word_addr];
                    ready_mem <= 1'b1;
                end else begin
                    busy      <= 1'b1;
                    is_write  <= write_mem;
                    lat_addr  <= word_addr;
                    lat_wdata <= wdata_mem;
                    cycle_cnt <= LATENCY[7:0] - 8'd1;
                end
            end
        end else begin
            if (cycle_cnt == 8'd1) begin
                if (is_write)
                    memory[lat_addr] <= lat_wdata;
                else
                    rdata_mem <= memory[lat_addr];
                ready_mem <= 1'b1;
                busy      <= 1'b0;
                cycle_cnt <= 8'd0;
            end else begin
                cycle_cnt <= cycle_cnt - 8'd1;
            end
        end
    end
end

endmodule
