`timescale 1ns/1ps

module rv32i_alu (
    input  wire [31:0] inp1,
    input  wire [31:0] inp2,
    input  wire [3:0]  alu_select,
    output reg  [31:0] alu_out
);
    always @(*) begin
        case (alu_select)
            4'b0000: alu_out = inp1 + inp2;                                       // ADD
            4'b0001: alu_out = inp1 - inp2;                                       // SUB
            4'b0010: alu_out = ($signed(inp1) < $signed(inp2)) ? 32'd1 : 32'd0;   // SLT
            4'b0011: alu_out = $signed(inp1) >>> inp2[4:0];                       // SRA
            4'b0100: alu_out = inp1 << inp2[4:0];                                 // SLL
            4'b0101: alu_out = inp1 >> inp2[4:0];                                 // SRL
            4'b0110: alu_out = inp1 | inp2;                                       // OR
            4'b0111: alu_out = inp1 & inp2;                                       // AND
            4'b1000: alu_out = inp1 ^ inp2;                                       // XOR
            default: alu_out = inp1 + inp2;
        endcase
    end
endmodule
