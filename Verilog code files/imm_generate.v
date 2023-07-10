module imm_generate(
input [11:0]imm_12,
input [4:0]reg_write_dest,
input [1:0]imm_sel,
output reg [31:0]read_imm_data2
);

wire [11:0] s_format_num;
wire [9:0] b_format_bits_1_to_10;
wire [10:0] b_format_bits_10_to_11;
wire [11:0] b_format_num;

assign s_format_num = {imm_12[11:5], reg_write_dest[4:0]};

assign b_format_bits_1_to_10 = {imm_12[10:5], reg_write_dest[4:1]};
assign b_format_bits_10_to_11 = {imm_12[11:11], b_format_bits_1_to_10[9:0]};
assign b_format_num = {reg_write_dest[0:0], b_format_bits_10_to_11[10:0]};

always @(*)
begin
if (imm_sel == 2'b01)
   read_imm_data2 = { { 20{imm_12[11]}}, imm_12};
else if (imm_sel == 2'b00)
   read_imm_data2 = { { 20{s_format_num[11]}}, s_format_num};
else if (imm_sel == 2'b10)
   read_imm_data2 = { { 20{b_format_num[11]}}, b_format_num};
end

endmodule  