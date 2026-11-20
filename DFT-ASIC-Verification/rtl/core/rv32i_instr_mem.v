`timescale 1ns/1ps

module rv32i_instr_mem (
    input  wire [31:0] pc,
    input  wire        prog_sel,
    output reg  [31:0] instr
);
    wire [6:0] instr_addr = pc[8:2];

    always @(*) begin
        if (!prog_sel) begin
            // Program 0: Fibonacci sequence loop (result observed on x14)
            case (instr_addr)
                7'd0:    instr = 32'h00060613; // addi x12, x12, 0
                7'd1:    instr = 32'h00168693; // addi x13, x13, 1
                7'd2:    instr = 32'h00C68733; // add  x14, x13, x12
                7'd3:    instr = 32'h00068613; // addi x12, x13, 0
                7'd4:    instr = 32'h00070693; // addi x13, x14, 0
                7'd5:    instr = 32'hFE06DAE3; // bge  x13, x0, -12
                default: instr = 32'h00000013; // nop
            endcase
        end else begin
            // Program 1: End-to-End RV32I + 2-Way D-Cache Verification Suite (ends x14=1297)
            case (instr_addr)
                7'd0:    instr = 32'h00002083; // lw   x1, 0(x0)       # MISS#1: Set0 W0=10
                7'd1:    instr = 32'h00108133; // add  x2, x1, x1      # load-use stall -> x2=20
                7'd2:    instr = 32'h00002183; // lw   x3, 0(x0)       # HIT#1: x3=10
                7'd3:    instr = 32'h06F00213; // addi x4, x0, 111     # x4=111
                7'd4:    instr = 32'h00402023; // sw   x4, 0(x0)       # SW fwd + HIT#2: Set0 W0=111 (dirty)
                7'd5:    instr = 32'h00002283; // lw   x5, 0(x0)       # b2b SW->LW HIT#3: x5=111
                7'd6:    instr = 32'h02002303; // lw   x6, 32(x0)      # MISS#2: Set0 W1=20 (Tag1)
                7'd7:    instr = 32'h0C830393; // addi x7, x6, 200     # load-use stall -> x7=220
                7'd8:    instr = 32'h02702023; // sw   x7, 32(x0)      # SW fwd + HIT#4: Set0 W1=220 (dirty)
                7'd9:    instr = 32'h00002403; // lw   x8, 0(x0)       # HIT#5: 2-way Set0 W0=111 (W0->MRU)
                7'd10:   instr = 32'h04002483; // lw   x9, 64(x0)      # MISS#3 + DIRTY WB#1 (0x0020=220->MM)
                7'd11:   instr = 32'h00002503; // lw   x10, 0(x0)      # HIT#6: W0=111 still resident
                7'd12:   instr = 32'h06002583; // lw   x11, 96(x0)     # MISS#4 + ZERO WB (clean W1 evicted)
                7'd13:   instr = 32'h02002603; // lw   x12, 32(x0)     # MISS#5 + DIRTY WB#2 (0x0000=111->MM)
                7'd14:   instr = 32'h22B00793; // addi x15, x0, 555    # x15=555
                7'd15:   instr = 32'h00F02623; // sw   x15, 12(x0)     # MISS#6 (write-alloc): Set3=555
                7'd16:   instr = 32'h01402803; // lw   x16, 20(x0)     # b2b cross-set MISS#7: Set5=88
                7'd17:   instr = 32'h00C02883; // lw   x17, 12(x0)     # HIT#7: Set3=555
                7'd18:   instr = 32'h06300013; // addi x0, x0, 99      # x0 protection check
                7'd19:   instr = 32'hFF800913; // addi x18, x0, -8     # x18=-8
                7'd20:   instr = 32'h40195993; // srai x19, x18, 1     # arithmetic SRAI -> x19=-4
                7'd21:   instr = 32'h00092A33; // slt  x20, x18, x0    # signed SLT (-8 < 0) -> x20=1
                7'd22:   instr = 32'h0139D663; // bge  x19, x19, +12   # equal BGE taken -> skips PC+4 & PC+8
                7'd23:   instr = 32'h00000A13; // addi x20, x0, 0      # wrong-path PC+4 (flushed)
                7'd24:   instr = 32'h00000A13; // addi x20, x0, 0      # wrong-path PC+8 (flushed)
                7'd25:   instr = 32'h000A1463; // bne  x20, x0, +8     # BNE taken (x20==1)
                7'd26:   instr = 32'h00000A13; // addi x20, x0, 0      # wrong-path (flushed)
                7'd27:   instr = 32'h07800A93; // addi x21, x0, 120    # jalr target PC=120
                7'd28:   instr = 32'h000A8B67; // jalr x22, x21, 0     # PC=112 -> jumps to 120, x22=116
                7'd29:   instr = 32'h00000A13; // addi x20, x0, 0      # wrong-path after jalr (flushed)
                7'd30:   instr = 32'hF90B0B93; // addi x23, x22, -112  # x23 = 4
                7'd31:   instr = 32'h00310733; // add  x14, x2, x3     # 30
                7'd32:   instr = 32'h00570733; // add  x14, x14, x5    # 141
                7'd33:   instr = 32'h00870733; // add  x14, x14, x8    # 252
                7'd34:   instr = 32'h00970733; // add  x14, x14, x9    # 282
                7'd35:   instr = 32'h00A70733; // add  x14, x14, x10   # 393
                7'd36:   instr = 32'h00B70733; // add  x14, x14, x11   # 433
                7'd37:   instr = 32'h00C70733; // add  x14, x14, x12   # 653
                7'd38:   instr = 32'h01070733; // add  x14, x14, x16   # 741
                7'd39:   instr = 32'h01170733; // add  x14, x14, x17   # 1296
                7'd40:   instr = 32'h01370733; // add  x14, x14, x19   # 1292
                7'd41:   instr = 32'h01470733; // add  x14, x14, x20   # 1293
                7'd42:   instr = 32'h01770733; // add  x14, x14, x23   # 1297
                7'd43:   instr = 32'h00070733; // add  x14, x14, x0    # 1297
                7'd44:   instr = 32'h00000063; // beq  x0, x0, 0       # halt loop
                default: instr = 32'h00000013; // nop
            endcase
        end
    end
endmodule
