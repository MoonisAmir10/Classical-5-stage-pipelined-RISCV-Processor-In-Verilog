`timescale 1ns/1ps

module rv32i_pc_mux (
    input  wire [31:0] alu_out,
    input  wire [31:0] pc,
    input  wire        pcsel,
    output wire [31:0] pc_update
);
    assign pc_update = pcsel ? alu_out : (pc + 32'd4);
endmodule

module rv32i_input1_mux (
    input  wire [31:0] read_reg_data1,
    input  wire [31:0] pc,
    input  wire        asel,
    output wire [31:0] read_data1
);
    assign read_data1 = asel ? pc : read_reg_data1;
endmodule

module rv32i_input2_mux (
    input  wire [31:0] read_reg_data2,
    input  wire [31:0] read_imm_data2,
    input  wire        bsel,
    output wire [31:0] read_data2
);
    assign read_data2 = bsel ? read_imm_data2 : read_reg_data2;
endmodule

module rv32i_mux_3_to_1 (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [31:0] c,
    input  wire [1:0]  sel,
    output reg  [31:0] out
);
    always @(*) begin
        case (sel)
            2'b00:   out = a;
            2'b01:   out = b;
            2'b10:   out = c;
            default: out = a;
        endcase
    end
endmodule

module rv32i_wb_mux (
    input  wire [31:0] dm_inp,
    input  wire [31:0] alu_result,
    input  wire [31:0] pc,
    input  wire [1:0]  wbsel,
    output reg  [31:0] write_data
);
    // Note: rv32i_datapath already computes pc_MEM_plus4 = pc_MEM + 4 -> pc_WB
    always @(*) begin
        case (wbsel)
            2'b00:   write_data = alu_result;
            2'b01:   write_data = dm_inp;
            2'b10:   write_data = pc;
            default: write_data = alu_result;
        endcase
    end
endmodule
