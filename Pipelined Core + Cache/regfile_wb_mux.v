`timescale 1ns / 1ps

module regfile_wb_mux(
    input  wire [31:0] dm_inp,
    input  wire [31:0] alu_result,
    input  wire [31:0] pc,
    input  wire [1:0]  wbsel,
    output reg  [31:0] write_data
);

// Note: Datapath already computes pc_MEM_plus4 = pc_MEM + 4 -> pc_WB
always @(*) begin
    case (wbsel)
        2'b00:   write_data = alu_result;
        2'b01:   write_data = dm_inp;
        2'b10:   write_data = pc;
        default: write_data = alu_result;
    endcase
end

endmodule
