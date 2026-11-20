`timescale 1ns/1ps

module tb_rv32i_baseline;
    reg         clk;
    reg         rst_n;
    reg         prog_sel;
    wire [31:0] x14;
    wire [31:0] pc_obs;
    wire [31:0] alu_obs;

    wire [15:0] dcache_addr;
    wire [31:0] dcache_wdata;
    wire [3:0]  dcache_wstrb;
    wire        dcache_rd;
    wire        dcache_wr;
    wire [31:0] dcache_rdata;
    wire        dcache_stall;

    wire [15:0] addr_mem;
    wire [31:0] mem_wdata;
    reg  [31:0] mem_rdata;
    wire        rd_mem;
    wire        wr_mem;
    reg         ready_mem;
    wire        cache_hit, cache_miss, cache_wb;
    wire [31:0] unused_bist_dout;

    rv32i_processor dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .prog_sel     (prog_sel),
        .dcache_addr  (dcache_addr),
        .dcache_wdata (dcache_wdata),
        .dcache_wstrb (dcache_wstrb),
        .dcache_rd    (dcache_rd),
        .dcache_wr    (dcache_wr),
        .dcache_rdata (dcache_rdata),
        .dcache_stall (dcache_stall),
        .x14          (x14),
        .pc_obs       (pc_obs),
        .alu_obs      (alu_obs)
    );

    cache_2wsa_dft u_dcache (
        .clock         (clk),
        .reset_n       (rst_n),
        .addr_cpu      (dcache_addr),
        .cpu_wdata     (dcache_wdata),
        .cpu_wstrb     (dcache_wstrb),
        .rd_cpu        (dcache_rd),
        .wr_cpu        (dcache_wr),
        .cpu_rdata     (dcache_rdata),
        .stall_cpu     (dcache_stall),
        .addr_mem      (addr_mem),
        .mem_wdata     (mem_wdata),
        .mem_rdata     (mem_rdata),
        .rd_mem        (rd_mem),
        .wr_mem        (wr_mem),
        .ready_mem     (ready_mem),
        .cache_hit     (cache_hit),
        .cache_miss    (cache_miss),
        .cache_wb      (cache_wb),
        .bist_en       (1'b0),
        .bist_bank_sel (2'd0),
        .bist_addr     (3'd0),
        .bist_din      (32'd0),
        .bist_we       (1'b0),
        .bist_dout     (unused_bist_dout),
        .inj_en        (1'b0),
        .inj_bank      (2'd0),
        .inj_addr      (3'd0),
        .inj_bit       (6'd0),
        .inj_type      (2'd0)
    );

    // Synchronous backing memory (4-cycle latency)
    reg [31:0] ext_mem [0:1023];
    reg        mm_busy, mm_is_wr;
    reg [9:0]  mm_addr;
    reg [31:0] mm_wdata;
    reg [2:0]  mm_cnt;
    integer    hits, misses, wbs;

    /* verilator lint_off SYNCASYNCNET */
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready_mem <= 1'b0;
            mem_rdata <= 32'd0;
            mm_busy   <= 1'b0;
            mm_is_wr  <= 1'b0;
            mm_addr   <= 10'd0;
            mm_wdata  <= 32'd0;
            mm_cnt    <= 3'd0;
            hits      <= 0;
            misses    <= 0;
            wbs       <= 0;
        end else begin
            ready_mem <= 1'b0;
            if (cache_hit)  hits   <= hits + 1;
            if (cache_miss) misses <= misses + 1;
            if (cache_wb)   wbs    <= wbs + 1;

            if (!mm_busy) begin
                if (!ready_mem && (rd_mem || wr_mem)) begin
                    mm_busy  <= 1'b1;
                    mm_is_wr <= wr_mem;
                    mm_addr  <= addr_mem[11:2];
                    mm_wdata <= mem_wdata;
                    mm_cnt   <= 3'd3;
                end
            end else if (mm_cnt == 3'd1) begin
                if (mm_is_wr) ext_mem[mm_addr] <= mm_wdata;
                else          mem_rdata <= ext_mem[mm_addr];
                ready_mem <= 1'b1;
                mm_busy   <= 1'b0;
                mm_cnt    <= 3'd0;
            end else begin
                mm_cnt <= mm_cnt - 3'd1;
            end
        end
    end
    /* verilator lint_on SYNCASYNCNET */

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

    integer    expected_fib [0:7];
    integer    fib_idx, k;
    reg [31:0] prev_x14;

    initial begin
        for (k = 0; k < 1024; k = k + 1) ext_mem[k] = 32'd0;
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
        if (fib_idx < 8 || hits != 0 || misses != 0) begin
            $display("FAIL [Program 0]: fib_idx=%0d hits=%0d misses=%0d", fib_idx, hits, misses);
            $finish(1);
        end
        $display("PASS [Program 0]: Fibonacci sequence 1..34 verified on x14 (0 spurious cache accesses)");

        // Test 2: Reset recovery + Program 1 (End-to-End RV32I LW/SW D-Cache suite -> x14=1297)
        @(negedge clk);
        rst_n    = 1'b0;
        prog_sel = 1'b1;
        ext_mem[10'h000] = 32'd10;
        ext_mem[10'h008] = 32'd20;
        ext_mem[10'h010] = 32'd30;
        ext_mem[10'h018] = 32'd40;
        ext_mem[10'h003] = 32'd77;
        ext_mem[10'h005] = 32'd88;
        repeat (3) @(posedge clk);
        #1;
        if (x14 !== 32'd0 || pc_obs !== 32'd0) begin
            $display("FAIL: Reset did not clear x14 (%0d) or pc (%h)", x14, pc_obs);
            $finish(1);
        end
        @(negedge clk);
        rst_n = 1'b1;

        repeat (220) @(posedge clk);
        #1;
        if (x14 !== 32'd1297 || hits !== 7 || misses !== 7 || wbs !== 2 ||
            ext_mem[10'h000] !== 32'd111 || ext_mem[10'h008] !== 32'd220 || ext_mem[10'h003] !== 32'd77) begin
            $display("FAIL [Program 1]: x14=%0d hits=%0d misses=%0d wbs=%0d mm[0]=%0d mm[8]=%0d mm[3]=%0d",
                     x14, hits, misses, wbs, ext_mem[10'h000], ext_mem[10'h008], ext_mem[10'h003]);
            $finish(1);
        end
        $display("PASS [Program 1]: End-to-end RV32I + 2-Way D-Cache verified (x14=%0d, hits=%0d, misses=%0d, wbs=%0d)",
                 x14, hits, misses, wbs);
        $finish;
    end
endmodule
