`timescale 1ns/1ps

module tb_mbist_ctrl;
    reg         clk;
    reg         rst_n;
    reg         start_toggle;
    reg         start_sync_pulse;
    reg  [3:0]  bank_mask;
    reg         stop_on_fail;
    reg  [1:0]  pattern_mode;

    wire        bist_en;
    wire [1:0]  bist_bank_sel;
    wire [2:0]  bist_addr;
    wire [31:0] bist_din;
    wire        bist_we;
    wire [31:0] bist_dout;

    wire        bist_done, bist_fail;
    wire [47:0] mbist_stat;

    reg         inj_en;
    reg  [1:0]  inj_bank;
    reg  [2:0]  inj_addr;
    reg  [5:0]  inj_bit;
    reg  [1:0]  inj_type;

    mbist_ctrl u_mbist (
        .clk              (clk),
        .rst_n            (rst_n),
        .start_toggle     (start_toggle),
        .start_sync_pulse (start_sync_pulse),
        .bank_mask        (bank_mask),
        .stop_on_fail     (stop_on_fail),
        .pattern_mode     (pattern_mode),
        .bist_en          (bist_en),
        .bist_bank_sel    (bist_bank_sel),
        .bist_addr        (bist_addr),
        .bist_din         (bist_din),
        .bist_we          (bist_we),
        .bist_dout        (bist_dout),
        .bist_done        (bist_done),
        .bist_fail        (bist_fail),
        .mbist_stat       (mbist_stat)
    );

    wire [31:0] unused_cpu_rdata, unused_mem_wdata;
    wire        unused_stall, unused_rd_mem, unused_wr_mem;
    wire        unused_hit, unused_miss, unused_wb;
    wire [15:0] unused_addr_mem;

    cache_2wsa_dft u_cache (
        .clock         (clk),
        .reset_n       (rst_n),
        .addr_cpu      (16'd0),
        .cpu_wdata     (32'd0),
        .cpu_wstrb     (4'b1111),
        .rd_cpu        (1'b0),
        .wr_cpu        (1'b0),
        .cpu_rdata     (unused_cpu_rdata),
        .stall_cpu     (unused_stall),
        .addr_mem      (unused_addr_mem),
        .mem_wdata     (unused_mem_wdata),
        .mem_rdata     (32'd0),
        .rd_mem        (unused_rd_mem),
        .wr_mem        (unused_wr_mem),
        .ready_mem     (1'b0),
        .cache_hit     (unused_hit),
        .cache_miss    (unused_miss),
        .cache_wb      (unused_wb),
        .bist_en       (bist_en),
        .bist_bank_sel (bist_bank_sel),
        .bist_addr     (bist_addr),
        .bist_din      (bist_din),
        .bist_we       (bist_we),
        .bist_dout     (bist_dout),
        .inj_en        (inj_en),
        .inj_bank      (inj_bank),
        .inj_addr      (inj_addr),
        .inj_bit       (inj_bit),
        .inj_type      (inj_type)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic run_mbist_wait(input logic use_toggle);
        integer cyc;
        begin
            if (use_toggle) begin
                start_toggle = ~start_toggle;
            end else begin
                @(negedge clk);
                start_sync_pulse = 1'b1;
                @(posedge clk); #1;
                @(negedge clk);
                start_sync_pulse = 1'b0;
            end

            // Wait for bist_done to deassert (start recognized) then assert
            cyc = 0;
            while (bist_done && cyc < 20) begin
                @(posedge clk); #1;
                cyc = cyc + 1;
            end
            cyc = 0;
            while (!bist_done && cyc < 3000) begin
                @(posedge clk); #1;
                cyc = cyc + 1;
            end
            if (!bist_done) begin
                $display("FAIL: MBIST timeout waiting for bist_done");
                $fatal(1, "Assertion failed");
            end
        end
    endtask

    initial begin
        rst_n            = 1'b0;
        start_toggle     = 1'b0;
        start_sync_pulse = 1'b0;
        bank_mask        = 4'b1111;
        stop_on_fail     = 1'b0;
        pattern_mode     = 2'b00;
        inj_en           = 1'b0;
        inj_bank         = 2'd0;
        inj_addr         = 3'd0;
        inj_bit          = 6'd0;
        inj_type         = 2'd0;

        repeat (3) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;

        // 1. Clean March-C across all 4 banks via CDC toggle
        run_mbist_wait(1'b1);
        if (bist_fail !== 1'b0 || mbist_stat[0] !== 1'b1 || mbist_stat[1] !== 1'b0) begin
            $display("FAIL [Clean March-C]: fail=%b stat=%h", bist_fail, mbist_stat);
            $fatal(1, "Assertion failed");
        end

        // 2. Clean Checkerboard March across all 4 banks
        pattern_mode = 2'b01;
        run_mbist_wait(1'b0);
        if (bist_fail !== 1'b0) begin
            $display("FAIL [Checkerboard]: fail=%b stat=%h", bist_fail, mbist_stat);
            $fatal(1, "Assertion failed");
        end
        pattern_mode = 2'b00;

        // 3. Inject SA0 on Tag bank 0 (t0), addr 5, bit 11
        inj_en   = 1'b1;
        inj_bank = 2'd0;
        inj_addr = 3'd5;
        inj_bit  = 6'd11;
        inj_type = 2'b01; // SA0
        run_mbist_wait(1'b1);
        if (bist_fail !== 1'b1 || mbist_stat[3:2] !== 2'd0 ||
            mbist_stat[6:4] !== 3'd5 || mbist_stat[39:8] !== 32'h0000_0800) begin
            $display("FAIL [Fault t0 SA0]: bank=%0d addr=%0d mask=%h",
                     mbist_stat[3:2], mbist_stat[6:4], mbist_stat[39:8]);
            $fatal(1, "Assertion failed");
        end

        // 4. Inject SA1 on Data bank 3 (d1), addr 2, bit 29
        inj_bank = 2'd3;
        inj_addr = 3'd2;
        inj_bit  = 6'd29;
        inj_type = 2'b10; // SA1
        run_mbist_wait(1'b1);
        if (bist_fail !== 1'b1 || mbist_stat[3:2] !== 2'd3 ||
            mbist_stat[6:4] !== 3'd2 || mbist_stat[39:8] !== 32'h2000_0000) begin
            $display("FAIL [Fault d1 SA1]: bank=%0d addr=%0d mask=%h",
                     mbist_stat[3:2], mbist_stat[6:4], mbist_stat[39:8]);
            $fatal(1, "Assertion failed");
        end

        // 5. Inject bit-flip on Data bank 2 (d0), addr 7, bit 0 with stop_on_fail=1
        stop_on_fail = 1'b1;
        inj_bank     = 2'd2;
        inj_addr     = 3'd7;
        inj_bit      = 6'd0;
        inj_type     = 2'b11; // flip
        run_mbist_wait(1'b0);
        if (bist_fail !== 1'b1 || mbist_stat[3:2] !== 2'd2 ||
            mbist_stat[6:4] !== 3'd7 || mbist_stat[39:8] !== 32'h0000_0001) begin
            $display("FAIL [Fault d0 flip]: bank=%0d addr=%0d mask=%h",
                     mbist_stat[3:2], mbist_stat[6:4], mbist_stat[39:8]);
            $fatal(1, "Assertion failed");
        end

        $display("PASS [MBIST Ctrl]: Clean March-C, Checkerboard, and SA0/SA1/Flip bank+addr+mask diagnostics verified");
        $finish;
    end
endmodule
