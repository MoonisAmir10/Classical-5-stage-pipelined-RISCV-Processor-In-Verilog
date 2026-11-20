`timescale 1ns/1ps

module rv32i_processor (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        prog_sel,
    // Integrated 32-bit 2-way D-cache CPU master bus
    output wire [15:0] dcache_addr,
    output wire [31:0] dcache_wdata,
    output wire [3:0]  dcache_wstrb,
    output wire        dcache_rd,
    output wire        dcache_wr,
    input  wire [31:0] dcache_rdata,
    input  wire        dcache_stall,
    // Architectural observation outputs (IEEE 1500 wrapped)
    output wire [31:0] x14,
    output wire [31:0] pc_obs,
    output wire [31:0] alu_obs
);
    wire [31:0] instr;
    wire [3:0]  alu_select;
    wire        reg_write_en;
    wire [31:0] count;
    wire [1:0]  imm_sel;
    wire        bsel;
    wire        asel;
    wire        dm_read_en;
    wire        dm_write_en;
    wire [1:0]  wbsel;
    wire        breq_flag;
    wire        brlt_flag;
    wire        bge_flag;
    wire        brun_en;
    wire        pc_sel;
    wire [31:0] alu_EX;
    wire [31:0] alu_MEM;
    wire [31:0] branch_target;
    wire [31:0] pc_update;

    wire [31:0] instr_ID, instr_EX, instr_MEM, instr_WB;
    wire [31:0] count_ID;
    wire        reg_write_en_E, reg_write_en_MEM, reg_write_en_WB;
    wire        dm_read_en_E, dm_read_en_MEM;
    wire        dm_write_en_E, dm_write_en_MEM;
    wire [3:0]  alu_select_E;
    wire        bsel_E, asel_E;
    wire [1:0]  wbsel_E, wbsel_MEM, wbsel_WB;
    wire [1:0]  ForwardAE, ForwardBE;
    wire        en_F, en_D, en_E, en_M, en_W, flushD, flushE;

    assign pc_obs  = count;
    assign alu_obs = alu_MEM;

    assign branch_target = (instr_EX[6:0] == 7'b1100111) ? {alu_EX[31:1], 1'b0} : alu_EX;

    rv32i_pc_mux pc_mux_inst (
        .alu_out(branch_target),
        .pc(count),
        .pcsel(pc_sel),
        .pc_update(pc_update)
    );

    rv32i_pc counter_inst (
        .clk(clk),
        .rst_n(rst_n),
        .pc_update(pc_update),
        .en(en_F),
        .count(count)
    );

    rv32i_reg_pl #(.N(32)) pc_FD (
        .inp(count), .clk(clk), .rst_n(rst_n), .en(en_D), .clear(flushD), .out(count_ID)
    );

    rv32i_instr_mem instrmem_inst (
        .pc(count),
        .prog_sel(prog_sel),
        .instr(instr)
    );

    rv32i_reg_pl #(.N(32)) instr_FD (
        .inp(instr), .clk(clk), .rst_n(rst_n), .en(en_D), .clear(flushD), .out(instr_ID)
    );
    rv32i_reg_pl #(.N(32)) instr_DE (
        .inp(instr_ID), .clk(clk), .rst_n(rst_n), .en(en_E), .clear(flushE), .out(instr_EX)
    );
    rv32i_reg_pl #(.N(32)) instr_E_MEM (
        .inp(instr_EX), .clk(clk), .rst_n(rst_n), .en(en_M), .clear(1'b0), .out(instr_MEM)
    );
    rv32i_reg_pl #(.N(32)) instr_MEM_WB (
        .inp(instr_MEM), .clk(clk), .rst_n(rst_n), .en(en_W), .clear(1'b0), .out(instr_WB)
    );

    rv32i_reg_pl #(.N(1)) reg_write_en_DE (
        .inp(reg_write_en), .clk(clk), .rst_n(rst_n), .en(en_E), .clear(flushE), .out(reg_write_en_E)
    );
    rv32i_reg_pl #(.N(1)) reg_write_en_E_MEM (
        .inp(reg_write_en_E), .clk(clk), .rst_n(rst_n), .en(en_M), .clear(1'b0), .out(reg_write_en_MEM)
    );
    rv32i_reg_pl #(.N(1)) reg_write_en_MEM_WB (
        .inp(reg_write_en_MEM), .clk(clk), .rst_n(rst_n), .en(en_W), .clear(1'b0), .out(reg_write_en_WB)
    );

    rv32i_reg_pl #(.N(1)) dm_read_en_DE (
        .inp(dm_read_en), .clk(clk), .rst_n(rst_n), .en(en_E), .clear(flushE), .out(dm_read_en_E)
    );
    rv32i_reg_pl #(.N(1)) dm_read_en_E_MEM (
        .inp(dm_read_en_E), .clk(clk), .rst_n(rst_n), .en(en_M), .clear(1'b0), .out(dm_read_en_MEM)
    );

    rv32i_reg_pl #(.N(1)) dm_write_en_DE (
        .inp(dm_write_en), .clk(clk), .rst_n(rst_n), .en(en_E), .clear(flushE), .out(dm_write_en_E)
    );
    rv32i_reg_pl #(.N(1)) dm_write_en_E_MEM (
        .inp(dm_write_en_E), .clk(clk), .rst_n(rst_n), .en(en_M), .clear(1'b0), .out(dm_write_en_MEM)
    );

    rv32i_reg_pl #(.N(4)) alu_select_DE (
        .inp(alu_select), .clk(clk), .rst_n(rst_n), .en(en_E), .clear(flushE), .out(alu_select_E)
    );
    rv32i_reg_pl #(.N(1)) bsel_DE (
        .inp(bsel), .clk(clk), .rst_n(rst_n), .en(en_E), .clear(flushE), .out(bsel_E)
    );
    rv32i_reg_pl #(.N(1)) asel_DE (
        .inp(asel), .clk(clk), .rst_n(rst_n), .en(en_E), .clear(flushE), .out(asel_E)
    );

    rv32i_reg_pl #(.N(2)) wbsel_DE (
        .inp(wbsel), .clk(clk), .rst_n(rst_n), .en(en_E), .clear(flushE), .out(wbsel_E)
    );
    rv32i_reg_pl #(.N(2)) wbsel_E_MEM (
        .inp(wbsel_E), .clk(clk), .rst_n(rst_n), .en(en_M), .clear(1'b0), .out(wbsel_MEM)
    );
    rv32i_reg_pl #(.N(2)) wbsel_MEM_WB (
        .inp(wbsel_MEM), .clk(clk), .rst_n(rst_n), .en(en_W), .clear(1'b0), .out(wbsel_WB)
    );

    rv32i_control_unit controlunit_inst (
        .funct7(instr_ID[31:25]),
        .funct3(instr_ID[14:12]),
        .funct3_EX(instr_EX[14:12]),
        .opcode(instr_ID[6:0]),
        .opcode_EX(instr_EX[6:0]),
        .breq_flag(breq_flag),
        .brlt_flag(brlt_flag),
        .bge_flag(bge_flag),
        .alu_select(alu_select),
        .reg_write_en(reg_write_en),
        .imm_sel(imm_sel),
        .bsel(bsel),
        .asel(asel),
        .dm_read_en(dm_read_en),
        .dm_write_en(dm_write_en),
        .wbsel(wbsel),
        .brun_en(brun_en),
        .pc_sel(pc_sel)
    );

    rv32i_hazard_unit hu_inst (
        .RegWriteM(reg_write_en_MEM),
        .RegWriteW(reg_write_en_WB),
        .wbsel_E(wbsel_E),
        .pc_sel(pc_sel),
        .dcache_stall(dcache_stall),
        .RD_E(instr_EX[11:7]),
        .RD_M(instr_MEM[11:7]),
        .RD_W(instr_WB[11:7]),
        .Rs1_D(instr_ID[19:15]),
        .Rs1_E(instr_EX[19:15]),
        .Rs2_D(instr_ID[24:20]),
        .Rs2_E(instr_EX[24:20]),
        .ForwardAE(ForwardAE),
        .ForwardBE(ForwardBE),
        .en_F(en_F),
        .en_D(en_D),
        .en_E(en_E),
        .en_M(en_M),
        .en_W(en_W),
        .flushD(flushD),
        .flushE(flushE)
    );

    rv32i_datapath datapath_inst (
        .read_reg_r1(instr_ID[19:15]),
        .read_reg_r2(instr_ID[24:20]),
        .read_imm_12(instr_ID[31:20]),
        .reg_write_dest(instr_WB[11:7]),
        .reg_write_dest_imm(instr_ID[11:7]),
        .alu_select(alu_select_E),
        .reg_write_en(reg_write_en_WB),
        .clk(clk),
        .rst_n(rst_n),
        .imm_sel(imm_sel),
        .bsel(bsel_E),
        .asel(asel_E),
        .ForwardAE(ForwardAE),
        .ForwardBE(ForwardBE),
        .en_E(en_E),
        .en_M(en_M),
        .en_W(en_W),
        .flushE(flushE),
        .dm_read_en(dm_read_en_MEM),
        .dm_write_en(dm_write_en_MEM),
        .wbsel(wbsel_WB),
        .pc(count_ID),
        .brun_en(brun_en),
        .breq_flag(breq_flag),
        .brlt_flag(brlt_flag),
        .bge_flag(bge_flag),
        .alu_EX(alu_EX),
        .alu_MEM(alu_MEM),
        .dcache_addr(dcache_addr),
        .dcache_wdata(dcache_wdata),
        .dcache_wstrb(dcache_wstrb),
        .dcache_rd(dcache_rd),
        .dcache_wr(dcache_wr),
        .dcache_rdata(dcache_rdata),
        .dcache_stall(dcache_stall),
        .x14(x14)
    );
endmodule
