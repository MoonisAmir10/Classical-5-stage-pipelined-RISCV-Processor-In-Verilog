`timescale 1ns/1ps

module rv32i_hazard_unit (
    input  wire       RegWriteM,
    input  wire       RegWriteW,
    input  wire [1:0] wbsel_E,
    input  wire       pc_sel,
    input  wire [4:0] RD_E,
    input  wire [4:0] RD_M,
    input  wire [4:0] RD_W,
    input  wire [4:0] Rs1_D,
    input  wire [4:0] Rs1_E,
    input  wire [4:0] Rs2_D,
    input  wire [4:0] Rs2_E,
    output reg  [1:0] ForwardAE,
    output reg  [1:0] ForwardBE,
    output wire       stallF,
    output wire       stallD,
    output wire       flushD,
    output wire       flushE
);
    wire lwstall;

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

    assign lwstall = ((Rs1_D == RD_E) || (Rs2_D == RD_E)) && (RD_E != 5'd0) && wbsel_E[0];
    assign stallF  = !(lwstall || pc_sel);
    assign stallD  = !(lwstall || pc_sel);
    assign flushE  = lwstall || pc_sel;
    assign flushD  = pc_sel;
endmodule
