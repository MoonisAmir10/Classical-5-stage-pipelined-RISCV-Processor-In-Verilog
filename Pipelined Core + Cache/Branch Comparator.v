`timescale 1ns / 1ps

module branch_comparator(
    input  wire [31:0] inpA,
    input  wire [31:0] inpB,
    input  wire        brun_en,
    output reg         breq_flag,
    output reg         brlt_flag,
    output reg         bge_flag
);

always @(*) begin
    breq_flag = (inpA == inpB);
    if (brun_en) begin
        brlt_flag = ($unsigned(inpA) <  $unsigned(inpB));
        bge_flag  = ($unsigned(inpA) >= $unsigned(inpB));
    end else begin
        brlt_flag = ($signed(inpA) <  $signed(inpB));
        bge_flag  = ($signed(inpA) >= $signed(inpB));
    end
end

endmodule
