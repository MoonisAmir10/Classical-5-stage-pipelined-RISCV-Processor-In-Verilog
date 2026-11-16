`timescale 1ns/1ps

module rv32i_control_unit (
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
    output reg        dm_write_en,
    output reg  [1:0] wbsel,
    output reg        brun_en,
    output reg        pc_sel
);
    // Decode stage control generation
    always @(*) begin
        reg_write_en = 1'b0;
        imm_sel      = 2'b00;
        bsel         = 1'b0;
        asel         = 1'b0;
        wbsel        = 2'b00;
        dm_write_en  = 1'b0;
        alu_select   = 4'b0000;

        if (opcode == 7'b0110011) begin // R-type
            reg_write_en = 1'b1;
            case (funct3)
                3'b000: alu_select = (funct7 == 7'd32) ? 4'b0001 : 4'b0000;
                3'b110: alu_select = 4'b0110;
                3'b111: alu_select = 4'b0111;
                3'b001: alu_select = 4'b0100;
                3'b101: alu_select = (funct7 == 7'd32) ? 4'b0011 : 4'b0101;
                3'b010: alu_select = 4'b0010;
                3'b100: alu_select = 4'b1000;
                default: alu_select = 4'b0000;
            endcase
        end else if (opcode == 7'b0010011) begin // I-type ALU
            reg_write_en = 1'b1;
            imm_sel      = 2'b01;
            bsel         = 1'b1;
            case (funct3)
                3'b000: alu_select = 4'b0000;
                3'b110: alu_select = 4'b0110;
                3'b111: alu_select = 4'b0111;
                3'b001: alu_select = 4'b0100;
                3'b101: alu_select = (funct7 == 7'd32) ? 4'b0011 : 4'b0101;
                3'b010: alu_select = 4'b0010;
                3'b100: alu_select = 4'b1000;
                default: alu_select = 4'b0000;
            endcase
        end else if (opcode == 7'b0000011) begin // LW
            reg_write_en = 1'b1;
            imm_sel      = 2'b01;
            bsel         = 1'b1;
            wbsel        = 2'b01;
        end else if (opcode == 7'b0100011) begin // SW
            imm_sel      = 2'b00;
            bsel         = 1'b1;
            dm_write_en  = 1'b1;
        end else if (opcode == 7'b1100011) begin // Branch
            imm_sel      = 2'b10;
            bsel         = 1'b1;
            asel         = 1'b1;
        end else if (opcode == 7'b1100111) begin // JALR
            reg_write_en = 1'b1;
            imm_sel      = 2'b01;
            bsel         = 1'b1;
            wbsel        = 2'b10;
        end
    end

    // Execute stage branch & jump controller (single driver for pc_sel and brun_en)
    always @(*) begin
        pc_sel  = 1'b0;
        brun_en = 1'b0;

        if (opcode_EX == 7'b1100011) begin
            case (funct3_EX)
                3'b000: pc_sel = breq_flag;                              // BEQ
                3'b001: pc_sel = ~breq_flag;                             // BNE
                3'b100: pc_sel = brlt_flag;                              // BLT
                3'b101: pc_sel = bge_flag;                               // BGE
                3'b110: begin brun_en = 1'b1; pc_sel = brlt_flag; end    // BLTU
                3'b111: begin brun_en = 1'b1; pc_sel = bge_flag;  end    // BGEU
                default: pc_sel = 1'b0;
            endcase
        end else if (opcode_EX == 7'b1100111) begin
            pc_sel = 1'b1;
        end
    end
endmodule
