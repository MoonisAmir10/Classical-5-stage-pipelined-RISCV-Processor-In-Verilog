module DataMem(
input [31:0] dm_read_addr,
input [31:0] dm_write_data_rs2,
input dm_write_en,
input clk,
output reg [31:0] dm_read_data
);

//define the memory size in bytes
`define MEM_SIZE 256

//define the number of rows and columns in the array
`define ROWS (`MEM_SIZE / 4)

reg [31:0] memory [`ROWS - 1:0];
wire [5:0] ram_addr = dm_read_addr[5:0];
integer i;

//initializing all locations to be 8, for testing purposes
initial 
begin
  for(i=0;i<63;i=i+1)
   memory[i] <= 32'd8;
end



always @(posedge clk) begin 
  if (dm_write_en)
   memory[ram_addr] <= dm_write_data_rs2;
 end 

always@(*)
dm_read_data = memory[ram_addr];

endmodule 