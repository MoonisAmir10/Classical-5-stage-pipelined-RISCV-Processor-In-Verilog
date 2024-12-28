module RegFile(
input clk,
input reg_write_en,
input [4:0] reg_write_dest_addr,
input [31:0] reg_write_data,
input [4:0] reg_read_addr_rs1,
output reg [31:0] reg_read_data_rs1,
input [4:0] reg_read_addr_rs2,
output reg [31:0] reg_read_data_rs2,
output reg [31:0] x14
);

reg [31:0] reg_array[0:31]; //32 GPRs, each of 32-bit width

integer i;
//initializing all registers to be 0
initial 
begin
  for(i=0;i<31;i=i+1)
   reg_array[i] <= 32'd0;
 end

always @(posedge clk) 
   if(reg_write_en) 
     begin
      reg_array[reg_write_dest_addr] <= reg_write_data;
     end

always @(*)
begin
  reg_read_data_rs1 = reg_array[reg_read_addr_rs1];
  reg_read_data_rs2 = reg_array[reg_read_addr_rs2];
  x14 = reg_array[14];
end

endmodule 

////testbench
//module tb_regfile;
//reg clk;
//reg reg_write_en;
//reg [4:0] reg_write_dest_addr;
//reg [31:0] reg_write_data;
//reg [4:0] reg_read_addr_rs1;
//wire [31:0] reg_read_data_rs1;
//reg [4:0] reg_read_addr_rs2;
//wire [31:0] reg_read_data_rs2;
//
//RegFile regfile_inst(
//.clk(clk),
//.reg_write_en(reg_write_en),
//.reg_write_dest_addr(reg_write_dest_addr),
//.reg_write_data(reg_write_data),
//.reg_read_addr_rs1(reg_read_addr_rs1),
//.reg_read_data_rs1(reg_read_data_rs1),
//.reg_read_addr_rs2(reg_read_addr_rs2),
//.reg_read_data_rs2(reg_read_data_rs2)
//);
//
//// Clock Generation
//initial
//begin
//
//clk = 0;
//forever
//#5 clk= ~clk;
//
//end
//
////Main simulation
//initial
//begin
//
///*reg_write_en = 0;
//reg_read_addr_rs1 = 0;
//reg_read_addr_rs1 = 1;
//repeat(5) @(posedge clk);
//  reset <= #1 0;
//@(posedge clk)
//  reset <= #1 1;
//
//repeat(5) @(posedge clk);
//  reset <= #1 0;
//
//@(posedge clk)
//  reset <= #1 1;
//
//repeat(5) @(posedge clk);
//
//$stop;*/
////end
////endmodule
//
////initialize inputs
//  reg_write_en = 0;
//  reg_write_dest_addr = 0;
//  reg_write_data = 0;
//  reg_read_addr_rs1 = 0;
//  reg_read_addr_rs2 = 0;
//  
//  //wait for some time
//  #10;
//  
//  //write some values to the register file
//  reg_write_en = 1;
//  reg_write_dest_addr = 5; //write to register x5
//  reg_write_data = 32'd124; //write some data
//  #10; //wait for one clock cycle 
//  
//  reg_write_dest_addr = 10; //write to register x10
//  reg_write_data = 32'd214; //write some data
//  #10; //wait for one clock cycle
//  
//  reg_write_en = 0; //stop writing
//  
//  //read some values from the register file
//  reg_read_addr_rs1 = 5; //read from register x5
//  reg_read_addr_rs2 = 10; //read from register x10
//  #10; //wait for one clock cycle
//  
//  //check the outputs
//  $display("reg_read_data_rs1 = %h", reg_read_data_rs1); //should be equal to the data written to x5
//  $display("reg_read_data_rs2 = %h", reg_read_data_rs2); //should be equal to the data written to x10
//  
//end  
//endmodule 