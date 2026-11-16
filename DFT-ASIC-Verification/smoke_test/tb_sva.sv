`timescale 1ns/1ps

module tb_sva;
    logic       clk = 0;
    logic       rst = 1;
    logic       en  = 0;
    logic [3:0] q;

    counter4 dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .q(q)
    );

    always #5 clk = ~clk;

    // Concurrent SVA property check
    property p_reset_clears_q;
        @(posedge clk) rst |=> (q == 4'd0);
    endproperty
    assert property (p_reset_clears_q)
        else $error("SVA failure: reset did not clear q");

    initial begin
        repeat (3) @(posedge clk);
        rst <= 1'b0;
        en  <= 1'b1;
        repeat (6) @(posedge clk);
        #1;
        if (q !== 4'd6) begin
            $display("FAIL: Verilator SVA test q=%0d", q);
            $finish(1);
        end
        $display("PASS: Verilator 5.054 + SVA counter4 q=%0d", q);
        $finish;
    end
endmodule
