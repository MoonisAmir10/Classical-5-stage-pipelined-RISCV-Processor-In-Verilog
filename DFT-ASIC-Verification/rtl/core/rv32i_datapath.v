`timescale 1ns/1ps

module rv32i_datapath (
    input  wire [4:0]  read_reg_r1,
    input  wire [4:0]  read_reg_r2,
    input  wire [11:0] read_imm_12,
    input  wire [4:0]  reg_write_dest,
    input  wire [4:0]  reg_write_dest_imm,
    input  wire [3:0]  alu_select,
    input  wire        reg_write_en,
    input  wire        clk,
    input  wire        rst_n,
    input  wire [1:0]  imm_sel,
    input  wire        bsel,
    input  wire        asel,
    input  wire [1:0]  ForwardAE,
    input  wire [1:0]  ForwardBE,
    input  wire        flushE,
    input  wire        dm_write_en,
    input  wire [1:0]  wbsel,
    input  wire [31:0] pc,
    input  wire        brun_en,
    output wire        breq_flag,
    output wire        brlt_flag,
    output wire        bge_flag,
    output wire [31:0] alu_MEM,
    output wire [31:0] x14
);
    wire [31:0] read_data1;
    wire [31:0] read_reg_data1;
    wire [31:0] read_reg_data2;
    wire [31:0] read_imm_data2;
    wire [31:0] read_data2;
    wire [31:0] write_data;
    wire [31:0] dm_out;
    wire [31:0] alu_out;
    wire [31:0] inp1_fwd_out;
    wire [31:0] inp2_fwd_out;

    wire [31:0] pc_EX, pc_MEM, pc_MEM_plus4, pc_WB;
    wire [31:0] rs1_EX, rs2_EX, rs2_MEM;
    wire [31:0] imm_EX;
    wire [31:0] alu_WB;
    wire [31:0] dm_WB;

    rv32i_reg_pl #(.N(32)) pc_DE (
        .inp(pc), .clk(clk), .rst_n(rst_n), .en(1'b1), .clear(flushE), .out(pc_EX)
    );
    rv32i_reg_pl #(.N(32)) pc_E_MEM (
        .inp(pc_EX), .clk(clk), .rst_n(rst_n), .en(1'b1), .clear(1'b0), .out(pc_MEM)
    );
    assign pc_MEM_plus4 = pc_MEM + 32'd4;
    rv32i_reg_pl #(.N(32)) pc_MEM_WB (
        .inp(pc_MEM_plus4), .clk(clk), .rst_n(rst_n), .en(1'b1), .clear(1'b0), .out(pc_WB)
    );

    rv32i_reg_pl #(.N(32)) rs1_DE (
        .inp(read_reg_data1), .clk(clk), .rst_n(rst_n), .en(1'b1), .clear(flushE), .out(rs1_EX)
    );
    rv32i_reg_pl #(.N(32)) rs2_DE (
        .inp(read_reg_data2), .clk(clk), .rst_n(rst_n), .en(1'b1), .clear(flushE), .out(rs2_EX)
    );
    rv32i_reg_pl #(.N(32)) rs2_E_MEM (
        .inp(rs2_EX), .clk(clk), .rst_n(rst_n), .en(1'b1), .clear(1'b0), .out(rs2_MEM)
    );

    rv32i_reg_pl #(.N(32)) imm_DE (
        .inp(read_imm_data2), .clk(clk), .rst_n(rst_n), .en(1'b1), .clear(flushE), .out(imm_EX)
    );

    rv32i_reg_pl #(.N(32)) alu_E_MEM (
        .inp(alu_out), .clk(clk), .rst_n(rst_n), .en(1'b1), .clear(1'b0), .out(alu_MEM)
    );
    rv32i_reg_pl #(.N(32)) alu_MEM_WB (
        .inp(alu_MEM), .clk(clk), .rst_n(rst_n), .en(1'b1), .clear(1'b0), .out(alu_WB)
    );

    rv32i_reg_pl #(.N(32)) dm_MEM_WB (
        .inp(dm_out), .clk(clk), .rst_n(rst_n), .en(1'b1), .clear(1'b0), .out(dm_WB)
    );

    rv32i_regfile regfile_inst (
        .clk(clk),
        .rst_n(rst_n),
        .reg_write_en(reg_write_en),
        .reg_write_dest_addr(reg_write_dest),
        .reg_write_data(write_data),
        .reg_read_addr_rs1(read_reg_r1),
        .reg_read_data_rs1(read_reg_data1),
        .reg_read_addr_rs2(read_reg_r2),
        .reg_read_data_rs2(read_reg_data2),
        .x14(x14)
    );

    rv32i_imm_gen imm_gen_inst (
        .imm_12(read_imm_12),
        .reg_write_dest(reg_write_dest_imm),
        .imm_sel(imm_sel),
        .read_imm_data2(read_imm_data2)
    );

    rv32i_mux_3_to_1 inp2_fwd (
        .a(rs2_EX), .b(write_data), .c(alu_MEM), .sel(ForwardBE), .out(inp2_fwd_out)
    );
    rv32i_input2_mux input2_mux_inst (
        .read_reg_data2(inp2_fwd_out), .read_imm_data2(imm_EX), .bsel(bsel), .read_data2(read_data2)
    );

    rv32i_mux_3_to_1 inp1_fwd (
        .a(rs1_EX), .b(write_data), .c(alu_MEM), .sel(ForwardAE), .out(inp1_fwd_out)
    );
    rv32i_input1_mux input1_mux_inst (
        .read_reg_data1(inp1_fwd_out), .pc(pc_EX), .asel(asel), .read_data1(read_data1)
    );

    rv32i_branch_comp branc_comp_inst (
        .inpA(inp1_fwd_out),
        .inpB(inp2_fwd_out),
        .brun_en(brun_en),
        .breq_flag(breq_flag),
        .brlt_flag(brlt_flag),
        .bge_flag(bge_flag)
    );

    rv32i_alu ALU_inst (
        .inp1(read_data1),
        .inp2(read_data2),
        .alu_select(alu_select),
        .alu_out(alu_out)
    );

    rv32i_data_mem #(.AWIDTH(4)) RAM_inst (
        .clk(clk),
        .rst_n(rst_n),
        .dm_read_addr(alu_MEM),
        .dm_write_data_rs2(rs2_MEM),
        .dm_write_en(dm_write_en),
        .dm_read_data(dm_out)
    );

    rv32i_wb_mux wb_mux_inst (
        .dm_inp(dm_WB),
        .alu_result(alu_WB),
        .wbsel(wbsel),
        .pc(pc_WB),
        .write_data(write_data)
    );
endmodule
