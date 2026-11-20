`timescale 1ns / 1ps

// End-to-End Self-Checking Testbench for 5-Stage Pipelined RV32I + Integrated 2-Way D-Cache
module processor_tb #(
    parameter MEM_LATENCY = 4
);

    reg         clk;
    reg         reset_fib;
    reg         reset_cache;
    wire [31:0] x14_fib;
    wire [31:0] x14_cache;

    // Instance 0: Original Fibonacci benchmark (PROG_SEL = 0)
    Processor #(
        .PROG_SEL    (0),
        .MEM_LATENCY (4)
    ) proc_fib (
        .clk   (clk),
        .reset (reset_fib),
        .x14   (x14_fib)
    );

    // Instance 1: End-to-end LW/SW D-cache hit/miss/eviction/WB/hazard suite (PROG_SEL = 1)
    Processor #(
        .PROG_SEL    (1),
        .MEM_LATENCY (MEM_LATENCY)
    ) proc_cache (
        .clk   (clk),
        .reset (reset_cache),
        .x14   (x14_cache)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Count cache events on both cores
    integer fib_hits, fib_misses;
    integer dc_hits, dc_misses, dc_wbs, dc_stall_cycles;

    always @(posedge clk or negedge reset_fib) begin
        if (!reset_fib) begin
            fib_hits   <= 0;
            fib_misses <= 0;
        end else begin
            if (proc_fib.dcache_hit)  fib_hits   <= fib_hits + 1;
            if (proc_fib.dcache_miss) fib_misses <= fib_misses + 1;
        end
    end

    always @(posedge clk or negedge reset_cache) begin
        if (!reset_cache) begin
            dc_hits         <= 0;
            dc_misses       <= 0;
            dc_wbs          <= 0;
            dc_stall_cycles <= 0;
        end else begin
            if (proc_cache.dcache_hit)   dc_hits         <= dc_hits + 1;
            if (proc_cache.dcache_miss)  dc_misses       <= dc_misses + 1;
            if (proc_cache.dcache_wb)    dc_wbs          <= dc_wbs + 1;
            if (proc_cache.dcache_stall) dc_stall_cycles <= dc_stall_cycles + 1;
        end
    end

    integer    expected_fib [0:8];
    integer    fib_idx, cyc;
    reg [31:0] prev_fib;

    initial begin
        expected_fib[0] = 1;
        expected_fib[1] = 2;
        expected_fib[2] = 3;
        expected_fib[3] = 5;
        expected_fib[4] = 8;
        expected_fib[5] = 13;
        expected_fib[6] = 21;
        expected_fib[7] = 34;
        expected_fib[8] = 55;

        // Preload backing main_memory for proc_cache (PROG_SEL = 1)
        proc_cache.main_mem_inst.memory[10'h000] = 32'd10; // addr 0x0000 (Set 0, Tag 0)
        proc_cache.main_mem_inst.memory[10'h008] = 32'd20; // addr 0x0020 (Set 0, Tag 1)
        proc_cache.main_mem_inst.memory[10'h010] = 32'd30; // addr 0x0040 (Set 0, Tag 2)
        proc_cache.main_mem_inst.memory[10'h018] = 32'd40; // addr 0x0060 (Set 0, Tag 3)
        proc_cache.main_mem_inst.memory[10'h003] = 32'd77; // addr 0x000C (Set 3, Tag 0)
        proc_cache.main_mem_inst.memory[10'h005] = 32'd88; // addr 0x0014 (Set 5, Tag 0)

        reset_fib   = 1'b0;
        reset_cache = 1'b0;
        repeat (4) @(posedge clk);
        #1;
        reset_fib   = 1'b1;
        reset_cache = 1'b1;

        // =====================================================================
        // TEST 1: Fibonacci Benchmark (PROG_SEL = 0)
        // =====================================================================
        fib_idx  = 0;
        prev_fib = 32'd0;
        for (cyc = 0; cyc < 100; cyc = cyc + 1) begin
            @(posedge clk);
            #1;
            if (x14_fib !== prev_fib) begin
                if (fib_idx < 9) begin
                    if (x14_fib !== expected_fib[fib_idx]) begin
                        $display("FAIL [Fib term %0d]: got %0d exp %0d",
                                 fib_idx, x14_fib, expected_fib[fib_idx]);
                        $finish(1);
                    end
                    fib_idx = fib_idx + 1;
                end
                prev_fib = x14_fib;
            end
        end
        if (fib_idx < 9) begin
            $display("FAIL [Fib]: only saw %0d terms", fib_idx);
            $finish(1);
        end
        if (fib_hits != 0 || fib_misses != 0) begin
            $display("FAIL [Fib]: ALU-only program triggered spurious cache activity (hits=%0d misses=%0d)",
                     fib_hits, fib_misses);
            $finish(1);
        end
        $display("PASS [PROG 0 - Fibonacci]: 1..55 verified on x14 with 0 spurious cache accesses");

        // =====================================================================
        // TEST 2: End-to-End RV32I LW/SW D-Cache + Hazard + ISA Suite (PROG_SEL = 1)
        // =====================================================================
        // Allow ample cycles for all 7 misses (including 2 dirty writebacks) + hits + ALU/branches
        repeat (160) @(posedge clk);
        #1;

        if (x14_cache !== 32'd1297) begin
            $display("FAIL [PROG 1 - Checksum]: x14=%0d (0x%08h), expected 1297", x14_cache, x14_cache);
            $display("  x1=%0d x2=%0d x3=%0d x4=%0d x5=%0d x6=%0d x7=%0d x8=%0d",
                     proc_cache.datapath_inst.regfile_inst.reg_array[1],
                     proc_cache.datapath_inst.regfile_inst.reg_array[2],
                     proc_cache.datapath_inst.regfile_inst.reg_array[3],
                     proc_cache.datapath_inst.regfile_inst.reg_array[4],
                     proc_cache.datapath_inst.regfile_inst.reg_array[5],
                     proc_cache.datapath_inst.regfile_inst.reg_array[6],
                     proc_cache.datapath_inst.regfile_inst.reg_array[7],
                     proc_cache.datapath_inst.regfile_inst.reg_array[8]);
            $display("  x9=%0d x10=%0d x11=%0d x12=%0d x15=%0d x16=%0d x17=%0d",
                     proc_cache.datapath_inst.regfile_inst.reg_array[9],
                     proc_cache.datapath_inst.regfile_inst.reg_array[10],
                     proc_cache.datapath_inst.regfile_inst.reg_array[11],
                     proc_cache.datapath_inst.regfile_inst.reg_array[12],
                     proc_cache.datapath_inst.regfile_inst.reg_array[15],
                     proc_cache.datapath_inst.regfile_inst.reg_array[16],
                     proc_cache.datapath_inst.regfile_inst.reg_array[17]);
            $display("  x18=%0d x19=%0d x20=%0d x21=%0d x22=%0d x23=%0d",
                     $signed(proc_cache.datapath_inst.regfile_inst.reg_array[18]),
                     $signed(proc_cache.datapath_inst.regfile_inst.reg_array[19]),
                     proc_cache.datapath_inst.regfile_inst.reg_array[20],
                     proc_cache.datapath_inst.regfile_inst.reg_array[21],
                     proc_cache.datapath_inst.regfile_inst.reg_array[22],
                     proc_cache.datapath_inst.regfile_inst.reg_array[23]);
            $finish(1);
        end

        // Verify exact architectural registers
        if (proc_cache.datapath_inst.regfile_inst.reg_array[2]  !== 32'd20  ||
            proc_cache.datapath_inst.regfile_inst.reg_array[5]  !== 32'd111 ||
            proc_cache.datapath_inst.regfile_inst.reg_array[8]  !== 32'd111 ||
            proc_cache.datapath_inst.regfile_inst.reg_array[9]  !== 32'd30  ||
            proc_cache.datapath_inst.regfile_inst.reg_array[10] !== 32'd111 ||
            proc_cache.datapath_inst.regfile_inst.reg_array[11] !== 32'd40  ||
            proc_cache.datapath_inst.regfile_inst.reg_array[12] !== 32'd220 ||
            proc_cache.datapath_inst.regfile_inst.reg_array[16] !== 32'd88  ||
            proc_cache.datapath_inst.regfile_inst.reg_array[17] !== 32'd555 ||
            proc_cache.datapath_inst.regfile_inst.reg_array[19] !== 32'hFFFF_FFFC ||
            proc_cache.datapath_inst.regfile_inst.reg_array[20] !== 32'd1   ||
            proc_cache.datapath_inst.regfile_inst.reg_array[23] !== 32'd4) begin
            $display("FAIL [PROG 1 - Register State]: mismatch in individual register verification");
            $finish(1);
        end

        // Verify exact cache hit / miss / dirty-writeback counts!
        if (dc_hits !== 7 || dc_misses !== 7 || dc_wbs !== 2) begin
            $display("FAIL [PROG 1 - Cache Counters]: got hits=%0d misses=%0d wbs=%0d (exp 7, 7, 2)",
                     dc_hits, dc_misses, dc_wbs);
            $finish(1);
        end

        // Verify backing main_memory reflects exact write-back policy:
        // - 0x0000 was evicted dirty -> main_memory[0] MUST be 111
        // - 0x0020 was evicted dirty -> main_memory[8] MUST be 220
        // - 0x000C was written dirty (555) and NOT yet evicted -> main_memory[3] MUST still be 77!
        if (proc_cache.main_mem_inst.memory[10'h000] !== 32'd111 ||
            proc_cache.main_mem_inst.memory[10'h008] !== 32'd220 ||
            proc_cache.main_mem_inst.memory[10'h003] !== 32'd77) begin
            $display("FAIL [PROG 1 - Backing Memory]: mm[0]=%0d(exp 111) mm[8]=%0d(exp 220) mm[3]=%0d(exp 77)",
                     proc_cache.main_mem_inst.memory[10'h000],
                     proc_cache.main_mem_inst.memory[10'h008],
                     proc_cache.main_mem_inst.memory[10'h003]);
            $finish(1);
        end

        $display("PASS [PROG 1 - End-to-End RV32I + 2-Way D-Cache]: x14=%0d, hits=%0d, misses=%0d, dirty_wbs=%0d, stall_cycles=%0d",
                 x14_cache, dc_hits, dc_misses, dc_wbs, dc_stall_cycles);

        // =====================================================================
        // TEST 3: Mid-Run Reset Recovery + Cache Tag Invalidation End-to-End!
        // =====================================================================
        // After reset, modify backing memory[0x000C] to 999 (was 77 in MM, 555 dirty in cache)
        // and re-preload 0x0000=10, 0x0020=20, 0x000C=77 -> re-run PROG 1 cleanly!
        reset_cache = 1'b0;
        repeat (4) @(posedge clk);
        proc_cache.main_mem_inst.memory[10'h000] = 32'd10;
        proc_cache.main_mem_inst.memory[10'h008] = 32'd20;
        proc_cache.main_mem_inst.memory[10'h010] = 32'd30;
        proc_cache.main_mem_inst.memory[10'h018] = 32'd40;
        proc_cache.main_mem_inst.memory[10'h003] = 32'd77;
        proc_cache.main_mem_inst.memory[10'h005] = 32'd88;
        #1;
        reset_cache = 1'b1;

        repeat (220) @(posedge clk);
        #1;
        if (x14_cache !== 32'd1297 || dc_hits !== 7 || dc_misses !== 7 || dc_wbs !== 2) begin
            $display("FAIL [PROG 1 - Post-Reset Re-run]: x14=%0d hits=%0d misses=%0d wbs=%0d",
                     x14_cache, dc_hits, dc_misses, dc_wbs);
            $finish(1);
        end
        $display("PASS [PROG 1 - Post-Reset Recovery]: tag invalidation + full re-execution verified (hits=%0d misses=%0d wbs=%0d)",
                 dc_hits, dc_misses, dc_wbs);

        $finish;
    end

endmodule
