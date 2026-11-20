`timescale 1ns / 1ps

module ControlUnit(
    input  wire [6:0] funct7,
    input  wire [2:0] funct3,
    input  wire [2:0] funct3_EX,
    input  wire [6:0] opcode,
    input  wire [6:0] opcode_EX,
    input  wire       breq_flag,
    input  wire       brlt_flag,
    input  wire       bge_flag,
    output reg  [3:0] alu_select,
    output reg        reg_write_en,
    output reg  [1:0] imm_sel,
    output reg        bsel,
    output reg        asel,
    output reg        dm_read_en,
    output reg        dm_write_en,
    output reg  [1:0] wbsel,
    output reg        brun_en,
    output reg        pc_sel
);

// Main ID-stage decode
always @(*) begin
    reg_write_en = 1'b0;
    imm_sel      = 2'b00;
    bsel         = 1'b0;
    asel         = 1'b0;
    wbsel        = 2'b00;
    dm_read_en   = 1'b0;
    dm_write_en  = 1'b0;
    alu_select   = 4'b0000;

    if (opcode == 7'b0110011) begin
        // R-type instructions
        reg_write_en = 1'b1;
        imm_sel      = 2'b00;
        bsel         = 1'b0;
        asel         = 1'b0;
        wbsel        = 2'b00;
        dm_read_en   = 1'b0;
        dm_write_en  = 1'b0;

        case (funct3)
            3'b000: alu_select = (funct7 == 7'b0100000) ? 4'b0001 : 4'b0000; // SUB / ADD
            3'b001: alu_select = 4'b0100;                                    // SLL
            3'b010: alu_select = 4'b0010;                                    // SLT
            3'b011: alu_select = 4'b1001;                                    // SLTU
            3'b100: alu_select = 4'b1000;                                    // XOR
            3'b101: alu_select = (funct7 == 7'b0100000) ? 4'b0011 : 4'b0101; // SRA / SRL
            3'b110: alu_select = 4'b0110;                                    // OR
            3'b111: alu_select = 4'b0111;                                    // AND
            default: alu_select = 4'b0000;
        endcase

    end else if (opcode == 7'b0010011) begin
        // I-type ALU instructions
        reg_write_en = 1'b1;
        imm_sel      = 2'b01;
        bsel         = 1'b1;
        asel         = 1'b0;
        wbsel        = 2'b00;
        dm_read_en   = 1'b0;
        dm_write_en  = 1'b0;

        case (funct3)
            3'b000: alu_select = 4'b0000;                                    // ADDI
            3'b001: alu_select = 4'b0100;                                    // SLLI
            3'b010: alu_select = 4'b0010;                                    // SLTI
            3'b011: alu_select = 4'b1001;                                    // SLTIU
            3'b100: alu_select = 4'b1000;                                    // XORI
            3'b101: alu_select = (funct7 == 7'b0100000) ? 4'b0011 : 4'b0101; // SRAI / SRLI
            3'b110: alu_select = 4'b0110;                                    // ORI
            3'b111: alu_select = 4'b0111;                                    // ANDI
            default: alu_select = 4'b0000;
        endcase

    end else if (opcode == 7'b0000011) begin
        // Load word (LW)
        reg_write_en = 1'b1;
        imm_sel      = 2'b01;
        bsel         = 1'b1;
        asel         = 1'b0;
        wbsel        = 2'b01;
        dm_read_en   = 1'b1;
        dm_write_en  = 1'b0;
        alu_select   = 4'b0000;

    end else if (opcode == 7'b0100011) begin
        // Store word (SW)
        reg_write_en = 1'b0;
        imm_sel      = 2'b00;
        bsel         = 1'b1;
        asel         = 1'b0;
        wbsel        = 2'b00;
        dm_read_en   = 1'b0;
        dm_write_en  = 1'b1;
        alu_select   = 4'b0000;

    end else if (opcode == 7'b1100011) begin
        // Branch (BEQ, BNE, BLT, BGE, BLTU, BGEU)
        reg_write_en = 1'b0;
        imm_sel      = 2'b10;
        bsel         = 1'b1;
        asel         = 1'b1;
        wbsel        = 2'b00;
        dm_read_en   = 1'b0;
        dm_write_en  = 1'b0;
        alu_select   = 4'b0000;

    end else if (opcode == 7'b1100111) begin
        // JALR
        reg_write_en = 1'b1;
        imm_sel      = 2'b01;
        bsel         = 1'b1;
        asel         = 1'b0;
        wbsel        = 2'b10;
        dm_read_en   = 1'b0;
        dm_write_en  = 1'b0;
        alu_select   = 4'b0000;
    end
end

// EX-stage unsigned-branch mode (independent of comparator flags)
always @(*) begin
    brun_en = (opcode_EX == 7'b1100011) && (funct3_EX[2:1] == 2'b11);
end

// EX-stage Branch & Jump Controller
always @(*) begin
    pc_sel = 1'b0;

    if (opcode_EX == 7'b1100011) begin
        case (funct3_EX)
            3'b000: pc_sel = breq_flag;   // BEQ
            3'b001: pc_sel = ~breq_flag;  // BNE
            3'b100: pc_sel = brlt_flag;   // BLT
            3'b101: pc_sel = bge_flag;    // BGE
            3'b110: pc_sel = brlt_flag;   // BLTU
            3'b111: pc_sel = bge_flag;    // BGEU
            default: pc_sel = 1'b0;
        endcase
    end else if (opcode_EX == 7'b1100111) begin
        pc_sel = 1'b1; // JALR
    end
end

endmodule
