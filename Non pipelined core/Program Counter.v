module program_counter(
input clk,
input reset,
input [31:0] pc_update,
output reg [31:0] count
);


//PC register
always@(posedge clk, negedge reset)
if (!reset) //active low reset
  count <= 0;
else
  count <= pc_update;

endmodule

//Test bench
module tb_counter;
// Variables Declaration
reg clk;
reg reset;
wire [31:0] count;

// DUT instantiation
program_counter counter_inst(
.clk(clk),
.reset(reset),
.count(count)
);
//---------------------------------------------------

// Clock Generation
initial
begin

clk = 0;
forever
#5 clk= ~clk;

end

//Main simulation
initial
begin

reset = 1;
repeat(5) @(posedge clk);
  reset <= #1 0;
@(posedge clk)
  reset <= #1 1;

repeat(5) @(posedge clk);
  reset <= #1 0;

@(posedge clk)
  reset <= #1 1;

repeat(5) @(posedge clk);

$stop;
end
endmodule



