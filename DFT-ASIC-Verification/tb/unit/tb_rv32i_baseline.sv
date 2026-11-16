`timescale 1ns/1ps

module tb_rv32i_baseline;
    reg         clk;
    reg         rst_n;
    reg         prog_sel;
    wire [31:0] x14;
    wire [31:0] pc_obs;
    wire [31:0] alu_obs;

    rv32i_processor dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .prog_sel (prog_sel),
        .x14      (x14),
        .pc_obs   (pc_obs),
        .alu_obs  (alu_obs)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

`ifdef VERILATOR
    /* verilator lint_off SYNCASYNCNET */
    property p_rst_clears;
        @(posedge clk) (!rst_n) |-> (x14 == 32'd0 && pc_obs == 32'd0);
    endproperty
    assert property (p_rst_clears)
        else $error("SVA failure: reset did not clear x14/pc_obs");
    /* verilator lint_on SYNCASYNCNET */
`endif

    integer expected_fib [0:7];
    integer fib_idx;
    reg [31:0] prev_x14;

    initial begin
        expected_fib[0] = 1;
        expected_fib[1] = 2;
        expected_fib[2] = 3;
        expected_fib[3] = 5;
        expected_fib[4] = 8;
        expected_fib[5] = 13;
        expected_fib[6] = 21;
        expected_fib[7] = 34;

        // Test 1: Fibonacci loop (prog_sel = 0)
        prog_sel = 1'b0;
        rst_n    = 1'b1;
        #2;
        rst_n    = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n    = 1'b1;

        fib_idx  = 0;
        prev_x14 = 32'd0;
        repeat (80) begin
            @(posedge clk);
            #1;
            if (x14 != prev_x14) begin
                if (fib_idx < 8) begin
                    if (x14 !== expected_fib[fib_idx]) begin
                        $display("FAIL [Fib %0d]: expected %0d, got %0d",
                                 fib_idx, expected_fib[fib_idx], x14);
                        $finish(1);
                    end
                    fib_idx = fib_idx + 1;
                end
                prev_x14 = x14;
            end
        end
        if (fib_idx < 8) begin
            $display("FAIL: Only observed %0d Fibonacci terms", fib_idx);
            $finish(1);
        end
        $display("PASS [Program 0]: Fibonacci sequence 1..34 verified on x14");

        // Test 2: Reset recovery & Program 1 (LW/SW + load-use stall + ALU -> x14=12)
        @(negedge clk);
        rst_n    = 1'b0;
        prog_sel = 1'b1;
        repeat (3) @(posedge clk);
        #1;
        if (x14 !== 32'd0 || pc_obs !== 32'd0) begin
            $display("FAIL: Reset did not clear x14 (%0d) or pc (%h)", x14, pc_obs);
            $finish(1);
        end
        @(negedge clk);
        rst_n = 1'b1;

        repeat (30) @(posedge clk);
        #1;
        if (x14 !== 32'd12) begin
            $display("FAIL [Program 1]: expected x14=12, got %0d", x14);
            $finish(1);
        end
        $display("PASS [Program 1]: SW/LW + load-use hazard + ALU verified (x14=%0d)", x14);
        $finish;
    end
endmodule
