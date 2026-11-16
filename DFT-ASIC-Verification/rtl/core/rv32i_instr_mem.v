`timescale 1ns/1ps

module rv32i_instr_mem (
    input  wire [31:0] pc,
    input  wire        prog_sel,
    output reg  [31:0] instr
);
    wire [4:0] instr_addr = pc[6:2];

    always @(*) begin
        if (!prog_sel) begin
            // Program 0: Fibonacci sequence loop (result observed on x14)
            case (instr_addr)
                5'd0:    instr = 32'h00060613; // addi x12, x12, 0
                5'd1:    instr = 32'h00168693; // addi x13, x13, 1
                5'd2:    instr = 32'h00C68733; // add  x14, x13, x12
                5'd3:    instr = 32'h00068613; // addi x12, x13, 0
                5'd4:    instr = 32'h00070693; // addi x13, x14, 0
                5'd5:    instr = 32'hFE06DAE3; // bge  x13, x0, -12
                default: instr = 32'h00000013; // nop
            endcase
        end else begin
            // Program 1: Load/Store + Load-Use Hazard + ALU self-check (ends x14=12)
            case (instr_addr)
                5'd0:    instr = 32'h00500513; // addi x10, x0, 5
                5'd1:    instr = 32'h00A02023; // sw   x10, 0(x0)
                5'd2:    instr = 32'h00002583; // lw   x11, 0(x0)
                5'd3:    instr = 32'h00B50733; // add  x14, x10, x11  (load-use stall -> x14=10)
                5'd4:    instr = 32'h40A70733; // sub  x14, x14, x10  (x14=5)
                5'd5:    instr = 32'h00B74733; // xor  x14, x14, x11  (x14=0)
                5'd6:    instr = 32'h00750713; // addi x14, x10, 7    (x14=12)
                5'd7:    instr = 32'h00000063; // beq  x0, x0, 0      (halt loop)
                default: instr = 32'h00000013; // nop
            endcase
        end
    end
endmodule
