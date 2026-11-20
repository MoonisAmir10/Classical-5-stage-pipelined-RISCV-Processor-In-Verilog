`timescale 1ns / 1ps

module hazard_unit(
    input  wire       RegWriteM,
    input  wire       RegWriteW,
    input  wire [1:0] wbsel_E,
    input  wire       pc_sel,
    input  wire       dcache_stall,
    input  wire [4:0] RD_E,
    input  wire [4:0] RD_M,
    input  wire [4:0] RD_W,
    input  wire [4:0] Rs1_D,
    input  wire [4:0] Rs1_E,
    input  wire [4:0] Rs2_D,
    input  wire [4:0] Rs2_E,
    output reg  [1:0] ForwardAE,
    output reg  [1:0] ForwardBE,
    output wire       en_F,
    output wire       en_D,
    output wire       en_E,
    output wire       en_M,
    output wire       en_W,
    output wire       flushD,
    output wire       flushE
);

wire lwstall;

// EX-stage RAW Forwarding
always @(*) begin
    if (((Rs1_E == RD_M) && RegWriteM) && (Rs1_E != 5'd0))
        ForwardAE = 2'b10;
    else if (((Rs1_E == RD_W) && RegWriteW) && (Rs1_E != 5'd0))
        ForwardAE = 2'b01;
    else
        ForwardAE = 2'b00;
end

always @(*) begin
    if (((Rs2_E == RD_M) && RegWriteM) && (Rs2_E != 5'd0))
        ForwardBE = 2'b10;
    else if (((Rs2_E == RD_W) && RegWriteW) && (Rs2_E != 5'd0))
        ForwardBE = 2'b01;
    else
        ForwardBE = 2'b00;
end

// Load-use hazard detection (LW in EX with matching non-zero destination)
assign lwstall = (wbsel_E == 2'b01) && (RD_E != 5'd0) &&
                 ((Rs1_D == RD_E) || (Rs2_D == RD_E));

// Pipeline stage enables & flushes:
// - When dcache_stall == 1, freeze all 5 stages and suppress flushes so in-flight
//   branch/load-use state is preserved intact until the cache completes.
// - On taken branch/jump in EX (pc_sel == 1) with !dcache_stall, PC immediately
//   loads alu_EX (en_F = 1) while IF/ID and ID/EX flush (2-cycle branch penalty).
assign en_F   = !dcache_stall && !lwstall;
assign en_D   = !dcache_stall && !lwstall;
assign en_E   = !dcache_stall;
assign en_M   = !dcache_stall;
assign en_W   = !dcache_stall;

assign flushD = !dcache_stall && pc_sel;
assign flushE = !dcache_stall && (lwstall || pc_sel);

endmodule
