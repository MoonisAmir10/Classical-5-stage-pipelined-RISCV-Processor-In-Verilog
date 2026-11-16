`timescale 1ns/1ps

module tb_gls_sdf;
    reg        clk;
    reg        rst;
    reg        en;
    wire [3:0] q;

    counter4 dut (
        .clk (clk),
        .rst (rst),
        .en  (en),
        .q   (q)
    );

    initial begin
        $sdf_annotate(
            "/home/moonis/auto_job_seeker/projects/riscv-soc-dft/smoke_test/build/counter4.sdf",
            dut, , "sdf_annotate.log", "TYPICAL"
        );
    end

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        rst = 1'b1;
        en  = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        en  = 1'b1;

        repeat (6) @(posedge clk);
        #2;
        if (q !== 4'd6) begin
            $display("FAIL: expected q=6, got q=%0d", q);
            $finish(1);
        end
        $display("PASS: SDF GLS counter4 q=%0d", q);
        $finish;
    end
endmodule
