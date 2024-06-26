`include "Processor.v"

module processor_tb;

reg clk;
reg reset;
wire [31:0] out;

Processor processor_inst(
.clk(clk),
.reset(reset),
.x14(out)
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
  reset = 0;
  #5 reset = 1;
end 


initial
#4000 $finish;

endmodule 