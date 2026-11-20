`timescale 1ns/1ps

// Phase 5 Debug Case Study 2 (DBG-02):
// Fast-corner SDF gate-level simulation across the Chain 0 -> Chain 1 inter-clock
// skewed boundary (`16x sg13g2_buf_4` clock delay onto Chain 1 head `_15178_`).
//   - Without lockup latch (`+EXPECT_HOLD_FAIL`): shoot-through bit slip corrupts stream.
//   - With negative-edge `sg13g2_dllrq_1` lockup latch: 0 mismatches across 538 FFs.
module tb_dbg02_skew_hold #(
    parameter integer CHAIN_PAIR_LEN = 400
);

    reg clk;
    reg rst_n;
    reg scan_en;
    reg scan_in_ch0;
    wire scan_out_ch1;

    dbg02_dut dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .scan_en     (scan_en),
        .scan_in_ch0 (scan_in_ch0),
        .scan_out_ch1(scan_out_ch1)
    );

    initial clk = 1'b0;
    always #50 clk = ~clk; // 10 MHz scan shift clock

    function automatic logic stream_bit(input integer k);
        begin
            stream_bit = ((k >> 1) & 1); // 00110011...
        end
    endfunction

    integer cyc;
    integer mismatch_cnt;
    integer expect_fail;
    string  sdf_file;

    initial begin
        expect_fail = $test$plusargs("EXPECT_HOLD_FAIL");
        if (!$value$plusargs("SDF=%s", sdf_file)) begin
            $display("ERROR: pass +SDF=<path_to_fast_sdf>");
            $fatal(1);
        end
        $sdf_annotate(sdf_file, dut, , , "MINIMUM");

        mismatch_cnt = 0;
        rst_n        = 1'b0;
        scan_en      = 1'b0;
        scan_in_ch0  = 1'b0;

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n   = 1'b1;
        scan_en = 1'b1;

        for (cyc = 0; cyc < CHAIN_PAIR_LEN + 64; cyc = cyc + 1) begin
            scan_in_ch0 = stream_bit(cyc);
            @(posedge clk);
            @(negedge clk);
            if (cyc >= CHAIN_PAIR_LEN - 1) begin
                if (scan_out_ch1 !== stream_bit(cyc - (CHAIN_PAIR_LEN - 1))) begin
                    if (mismatch_cnt < 5) begin
                        $display("HOLD_SLIP cyc=%0d exp=%b got=%b",
                            cyc, stream_bit(cyc - (CHAIN_PAIR_LEN - 1)), scan_out_ch1);
                    end
                    mismatch_cnt = mismatch_cnt + 1;
                end
            end
        end

        if (expect_fail) begin
            if (mismatch_cnt == 0) begin
                $display("FAIL [DBG-02 Buggy]: expected hold shoot-through slip, got 0 mismatches!");
                $fatal(1);
            end
            $display("PASS [DBG-02 Buggy Reproduced]: %0d shift mismatches caused by inter-clock skew hold violation!", mismatch_cnt);
        end else begin
            if (mismatch_cnt != 0) begin
                $display("FAIL [DBG-02 Lockup Fixed]: %0d shift mismatches remain!", mismatch_cnt);
                $fatal(1);
            end
            $display("PASS [DBG-02 Lockup Fixed]: 0 mismatches across %0d skewed scan FFs with sg13g2_dllrq_1 lockup latch!", CHAIN_PAIR_LEN);
        end
        $finish;
    end

endmodule
