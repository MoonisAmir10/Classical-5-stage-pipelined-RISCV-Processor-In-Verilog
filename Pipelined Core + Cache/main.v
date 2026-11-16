//`include "Processor.v"

module processor_tb;

reg clk;
reg reset;
wire [31:0] x14;

Processor processor_inst(
.clk(clk),
.reset(reset),
.x14(x14)
);

initial begin
        $dumpfile("output_wave.vcd");
        $dumpvars(0,processor_tb);
    end

// Clock Generation
 initial 
begin
    clk = 0;
    forever #20 clk = ~clk;
end

initial 
begin
  reset = 1;
  #5 reset = 0;
  #15 reset = 1;
end 


initial
#12000 $finish;

endmodule 