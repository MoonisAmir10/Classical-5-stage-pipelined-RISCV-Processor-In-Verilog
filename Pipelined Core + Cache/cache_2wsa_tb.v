`timescale 1ns / 1ps

// Self-checking Directed + 2,500-op Randomized Golden-Scoreboard Testbench for cache_2wsa
module cache_2wsa_tb;

    reg         clock;
    reg         reset_n;

    reg  [15:0] addr_cpu;
    reg  [31:0] cpu_wdata;
    reg  [3:0]  cpu_wstrb;
    reg         rd_cpu;
    reg         wr_cpu;
    wire [31:0] cpu_rdata;
    wire        stall_cpu;

    wire [15:0] addr_mem;
    wire [31:0] mem_wdata;
    reg  [31:0] mem_rdata;
    wire        rd_mem;
    wire        wr_mem;
    reg         ready_mem;

    wire        cache_hit;
    wire        cache_miss;
    wire        cache_wb;

    cache_2wsa dut (
        .clock      (clock),
        .reset_n    (reset_n),
        .addr_cpu   (addr_cpu),
        .cpu_wdata  (cpu_wdata),
        .cpu_wstrb  (cpu_wstrb),
        .rd_cpu     (rd_cpu),
        .wr_cpu     (wr_cpu),
        .cpu_rdata  (cpu_rdata),
        .stall_cpu  (stall_cpu),
        .addr_mem   (addr_mem),
        .mem_wdata  (mem_wdata),
        .mem_rdata  (mem_rdata),
        .rd_mem     (rd_mem),
        .wr_mem     (wr_mem),
        .ready_mem  (ready_mem),
        .cache_hit  (cache_hit),
        .cache_miss (cache_miss),
        .cache_wb   (cache_wb)
    );

    initial clock = 1'b0;
    always #5 clock = ~clock;

    // -------------------------------------------------------------------------
    // Synchronous Backing Memory Model with Configurable / Randomized Latency
    // (Strictly registered ready_mem -- NO combinational ready_mem hack!)
    // -------------------------------------------------------------------------
    reg [31:0] ext_mem [0:16383];
    reg        mm_busy;
    reg        mm_is_wr;
    reg [13:0] mm_addr;
    reg [31:0] mm_wdata;
    reg [3:0]  mm_cnt;
    reg        rand_latency_en;
    reg [31:0] mm_prng;

    function automatic [31:0] xorshift32(input [31:0] s_in);
        reg [31:0] x;
        begin
            x = s_in;
            x = x ^ (x << 13);
            x = x ^ (x >> 17);
            x = x ^ (x << 5);
            xorshift32 = x;
        end
    endfunction

    integer    obs_rd_mem_cnt;
    integer    obs_wr_mem_cnt;
    reg [15:0] obs_last_wb_addr;
    reg [31:0] obs_last_wb_data;
    reg [15:0] obs_last_rd_addr;

    integer    obs_hit_cnt;
    integer    obs_miss_cnt;
    integer    obs_wb_pulse_cnt;

    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            ready_mem        <= 1'b0;
            mem_rdata        <= 32'd0;
            mm_busy          <= 1'b0;
            mm_is_wr         <= 1'b0;
            mm_addr          <= 14'd0;
            mm_wdata         <= 32'd0;
            mm_cnt           <= 4'd0;
            obs_rd_mem_cnt   <= 0;
            obs_wr_mem_cnt   <= 0;
            obs_last_wb_addr <= 16'd0;
            obs_last_wb_data <= 32'd0;
            obs_last_rd_addr <= 16'd0;
            obs_hit_cnt      <= 0;
            obs_miss_cnt     <= 0;
            obs_wb_pulse_cnt <= 0;
        end else begin
            ready_mem <= 1'b0;

            if (cache_hit)  obs_hit_cnt      <= obs_hit_cnt + 1;
            if (cache_miss) obs_miss_cnt     <= obs_miss_cnt + 1;
            if (cache_wb)   obs_wb_pulse_cnt <= obs_wb_pulse_cnt + 1;

            if (!mm_busy) begin
                if (!ready_mem && (rd_mem || wr_mem)) begin
                    if (wr_mem) begin
                        obs_wr_mem_cnt   <= obs_wr_mem_cnt + 1;
                        obs_last_wb_addr <= addr_mem;
                        obs_last_wb_data <= mem_wdata;
                    end else begin
                        obs_rd_mem_cnt   <= obs_rd_mem_cnt + 1;
                        obs_last_rd_addr <= addr_mem;
                    end

                    if (rand_latency_en) begin
                        mm_prng <= xorshift32(mm_prng);
                    end
                    if (rand_latency_en && ((mm_prng[2:0] % 3'd6) == 3'd0)) begin
                        // 1-cycle latency case
                        if (wr_mem)
                            ext_mem[addr_mem[15:2]] <= mem_wdata;
                        else
                            mem_rdata <= ext_mem[addr_mem[15:2]];
                        ready_mem <= 1'b1;
                    end else begin
                        mm_busy  <= 1'b1;
                        mm_is_wr <= wr_mem;
                        mm_addr  <= addr_mem[15:2];
                        mm_wdata <= mem_wdata;
                        mm_cnt   <= rand_latency_en ? (4'd1 + {1'b0, (mm_prng[5:3] % 3'd5)}) : 4'd3;
                    end
                end
            end else begin
                if (mm_cnt == 4'd1) begin
                    if (mm_is_wr)
                        ext_mem[mm_addr] <= mm_wdata;
                    else
                        mem_rdata <= ext_mem[mm_addr];
                    ready_mem <= 1'b1;
                    mm_busy   <= 1'b0;
                    mm_cnt    <= 4'd0;
                end else begin
                    mm_cnt <= mm_cnt - 4'd1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Golden Reference Model (2-Way Set-Associative, Write-Back, Write-Alloc, LRU)
    // -------------------------------------------------------------------------
    reg [31:0] gold_arch_mem [0:16383];
    reg        g_valid [0:7][0:1];
    reg        g_dirty [0:7][0:1];
    reg [10:0] g_tag   [0:7][0:1];
    reg [31:0] g_data  [0:7][0:1];
    reg        g_mru   [0:7]; // 1: Way 0 MRU (Way 1 LRU); 0: Way 1 MRU (Way 0 LRU)

    integer    s, w;
    task automatic golden_reset_cache;
        begin
            for (s = 0; s < 8; s = s + 1) begin
                g_mru[s] = 1'b0;
                for (w = 0; w < 2; w = w + 1) begin
                    g_valid[s][w] = 1'b0;
                    g_dirty[s][w] = 1'b0;
                    g_tag[s][w]   = 11'd0;
                    g_data[s][w]  = 32'd0;
                end
            end
        end
    endtask

    function automatic [31:0] apply_wstrb(input [31:0] old_d, input [31:0] new_d, input [3:0] strb);
        begin
            apply_wstrb = {
                strb[3] ? new_d[31:24] : old_d[31:24],
                strb[2] ? new_d[23:16] : old_d[23:16],
                strb[1] ? new_d[15:8]  : old_d[15:8],
                strb[0] ? new_d[7:0]   : old_d[7:0]
            };
        end
    endfunction

    // Standard req / !stall CPU transaction driver (supports 0-gap back-to-back!)
    task automatic do_cpu_op(
        input  [15:0] addr,
        input         is_wr,
        input  [31:0] wdata,
        input  [3:0]  wstrb,
        input         idle_after,
        output [31:0] rdata_out
    );
        integer guard;
        begin
            addr_cpu  = addr;
            cpu_wdata = wdata;
            cpu_wstrb = wstrb;
            rd_cpu    = !is_wr;
            wr_cpu    = is_wr;
            #1;
            guard = 0;
            while (stall_cpu && guard < 100) begin
                @(posedge clock);
                #1;
                guard = guard + 1;
            end
            if (guard >= 100) begin
                $display("FAIL: timeout waiting for stall_cpu==0 on addr=0x%04h wr=%b", addr, is_wr);
                $finish(1);
            end
            // Data is valid right before the completing posedge!
            rdata_out = cpu_rdata;
            @(posedge clock);
            #1;
            if (idle_after) begin
                rd_cpu = 1'b0;
                wr_cpu = 1'b0;
            end
        end
    endtask

    // Golden-checked single transaction
    integer tot_hits, tot_misses, tot_wbs, tot_clean_evicts;

    task automatic checked_op(
        input [15:0] addr,
        input        is_wr,
        input [31:0] wdata,
        input [3:0]  wstrb,
        input        idle_after
    );
        reg [10:0] tag;
        reg [2:0]  idx;
        reg        h0, h1, exp_hit, vic, exp_wb;
        reg [15:0] exp_wb_addr;
        reg [31:0] exp_wb_data;
        reg [31:0] exp_rdata;
        reg [31:0] got_rdata;
        reg [31:0] line_val;
        integer    pre_hit, pre_miss, pre_wb, pre_rd_mem, pre_wr_mem;
        begin
            tag = addr[15:5];
            idx = addr[4:2];

            h0 = g_valid[idx][0] && (g_tag[idx][0] == tag);
            h1 = g_valid[idx][1] && (g_tag[idx][1] == tag);
            exp_hit = h0 || h1;

            exp_wb      = 1'b0;
            exp_wb_addr = 16'd0;
            exp_wb_data = 32'd0;
            exp_rdata   = gold_arch_mem[addr[15:2]];

            pre_hit    = obs_hit_cnt;
            pre_miss   = obs_miss_cnt;
            pre_wb     = obs_wb_pulse_cnt;
            pre_rd_mem = obs_rd_mem_cnt;
            pre_wr_mem = obs_wr_mem_cnt;

            do_cpu_op(addr, is_wr, wdata, wstrb, idle_after, got_rdata);

            if (!is_wr && (got_rdata !== exp_rdata)) begin
                $display("FAIL [DATA MISMATCH]: addr=0x%04h got=0x%08h exp=0x%08h (exp_hit=%b)",
                         addr, got_rdata, exp_rdata, exp_hit);
                $finish(1);
            end

            // Update golden cache & verify exact hit/miss/wb events
            if (exp_hit) begin
                tot_hits = tot_hits + 1;
                if ((obs_hit_cnt - pre_hit) != 1 || (obs_miss_cnt - pre_miss) != 0 ||
                    (obs_rd_mem_cnt - pre_rd_mem) != 0 || (obs_wr_mem_cnt - pre_wr_mem) != 0) begin
                    $display("FAIL [HIT EVENT]: addr=0x%04h d_hit=%0d d_miss=%0d d_rd=%0d d_wr=%0d",
                             addr, obs_hit_cnt - pre_hit, obs_miss_cnt - pre_miss,
                             obs_rd_mem_cnt - pre_rd_mem, obs_wr_mem_cnt - pre_wr_mem);
                    $finish(1);
                end
                if (h0) begin
                    g_mru[idx] = 1'b1;
                    if (is_wr && (|wstrb)) begin
                        g_data[idx][0]  = apply_wstrb(g_data[idx][0], wdata, wstrb);
                        g_dirty[idx][0] = 1'b1;
                    end
                end else begin
                    g_mru[idx] = 1'b0;
                    if (is_wr && (|wstrb)) begin
                        g_data[idx][1]  = apply_wstrb(g_data[idx][1], wdata, wstrb);
                        g_dirty[idx][1] = 1'b1;
                    end
                end
            end else begin
                tot_misses = tot_misses + 1;
                vic = (!g_valid[idx][0]) ? 1'b0 :
                      (!g_valid[idx][1]) ? 1'b1 :
                      g_mru[idx];
                exp_wb = g_valid[idx][vic] && g_dirty[idx][vic];
                if (exp_wb) begin
                    tot_wbs     = tot_wbs + 1;
                    exp_wb_addr = {g_tag[idx][vic], idx, 2'b00};
                    exp_wb_data = g_data[idx][vic];
                end else if (g_valid[idx][vic]) begin
                    tot_clean_evicts = tot_clean_evicts + 1;
                end

                if ((obs_hit_cnt - pre_hit) != 0 || (obs_miss_cnt - pre_miss) != 1 ||
                    (obs_rd_mem_cnt - pre_rd_mem) != 1 ||
                    (obs_wr_mem_cnt - pre_wr_mem) != (exp_wb ? 1 : 0) ||
                    (obs_wb_pulse_cnt - pre_wb)   != (exp_wb ? 1 : 0)) begin
                    $display("FAIL [MISS EVENT]: addr=0x%04h exp_wb=%b d_hit=%0d d_miss=%0d d_rd=%0d d_wr=%0d d_wbp=%0d",
                             addr, exp_wb, obs_hit_cnt - pre_hit, obs_miss_cnt - pre_miss,
                             obs_rd_mem_cnt - pre_rd_mem, obs_wr_mem_cnt - pre_wr_mem,
                             obs_wb_pulse_cnt - pre_wb);
                    $finish(1);
                end

                if (exp_wb) begin
                    if (obs_last_wb_addr !== exp_wb_addr || obs_last_wb_data !== exp_wb_data) begin
                        $display("FAIL [WB PAYLOAD]: got addr=0x%04h data=0x%08h | exp addr=0x%04h data=0x%08h",
                                 obs_last_wb_addr, obs_last_wb_data, exp_wb_addr, exp_wb_data);
                        $finish(1);
                    end
                    if (ext_mem[exp_wb_addr[15:2]] !== exp_wb_data) begin
                        $display("FAIL [WB EXT_MEM]: ext_mem[0x%04h]=0x%08h exp=0x%08h",
                                 exp_wb_addr, ext_mem[exp_wb_addr[15:2]], exp_wb_data);
                        $finish(1);
                    end
                end

                if (obs_last_rd_addr !== {addr[15:2], 2'b00}) begin
                    $display("FAIL [RD ADDR]: got=0x%04h exp=0x%04h", obs_last_rd_addr, {addr[15:2], 2'b00});
                    $finish(1);
                end

                line_val = ext_mem[addr[15:2]];
                if (is_wr && (|wstrb)) begin
                    line_val = apply_wstrb(line_val, wdata, wstrb);
                end
                g_valid[idx][vic] = 1'b1;
                g_dirty[idx][vic] = is_wr && (|wstrb);
                g_tag[idx][vic]   = tag;
                g_data[idx][vic]  = line_val;
                g_mru[idx]        = !vic;
            end

            if (is_wr && (|wstrb)) begin
                gold_arch_mem[addr[15:2]] = apply_wstrb(gold_arch_mem[addr[15:2]], wdata, wstrb);
            end
        end
    endtask

    integer    k, iter, rand_resets;
    reg [31:0] prng;
    reg [31:0] rval, r32;
    reg [15:0] raddr;
    reg [3:0]  rstrb;
    reg        rwr, ridle;

    initial begin
        prng             = 32'hCACE_2026;
        mm_prng          = 32'h1234_5678;
        rand_latency_en  = 1'b0;
        addr_cpu         = 16'd0;
        cpu_wdata        = 32'd0;
        cpu_wstrb        = 4'b1111;
        rd_cpu           = 1'b0;
        wr_cpu           = 1'b0;
        tot_hits         = 0;
        tot_misses       = 0;
        tot_wbs          = 0;
        tot_clean_evicts = 0;
        rand_resets      = 0;

        for (k = 0; k < 16384; k = k + 1) begin
            ext_mem[k]       = {16'hA000, k[15:0]};
            gold_arch_mem[k] = {16'hA000, k[15:0]};
        end
        golden_reset_cache();

        reset_n = 1'b0;
        repeat (3) @(posedge clock);
        #1;
        reset_n = 1'b1;

        // =====================================================================
        // DIRECTED TESTS (All 5 previously failing bugs + write-back deferral)
        // =====================================================================

        // D1: Cold read miss on Set 0 (0x0000) & Set 3 (0x000C), then ZERO-GAP
        // back-to-back write hit Set 0 -> immediate read Set 3 (index-mux bug test!)
        checked_op(16'h0000, 1'b0, 32'd0,        4'b1111, 1'b0); // miss Set 0
        checked_op(16'h000C, 1'b0, 32'd0,        4'b1111, 1'b0); // miss Set 3 (0-gap!)
        checked_op(16'h0000, 1'b1, 32'hDEAD_BEEF,4'b1111, 1'b0); // write hit Set 0 (0-gap!)
        checked_op(16'h000C, 1'b0, 32'd0,        4'b1111, 1'b0); // read hit Set 3 (0-gap!)
        checked_op(16'h0000, 1'b0, 32'd0,        4'b1111, 1'b1); // read hit Set 0 -> must be DEAD_BEEF!

        // Verify write-back deferral: ext_mem[0x0000] must STILL hold original value!
        if (ext_mem[0] !== 32'hA000_0000) begin
            $display("FAIL [WRITE-BACK DEFERRAL]: ext_mem[0]=0x%08h was modified prematurely!", ext_mem[0]);
            $finish(1);
        end

        // D2: Write miss (write-allocate) with partial strobe -> immediate cross-set op
        checked_op(16'h0020, 1'b1, 32'h0000_7700, 4'b0010, 1'b0); // write miss Set 0 Way 1, byte 1 = 0x77
        checked_op(16'h0014, 1'b0, 32'd0,         4'b1111, 1'b0); // immediate miss Set 5 (0-gap!)
        checked_op(16'h0020, 1'b0, 32'd0,         4'b1111, 1'b1); // read hit Set 0 Way 1 -> merged byte 0x77!

        // D3: Make Set 0 Way 0 (0x0000, dirty) MRU, Way 1 (0x0020, dirty) LRU -> miss Tag 2 (0x0040)
        // Must evict & write back 0x0020 to ext_mem while keeping 0x0000 resident!
        checked_op(16'h0000, 1'b0, 32'd0, 4'b1111, 1'b0); // touch 0x0000 -> Way 0 MRU, Way 1 LRU
        checked_op(16'h0040, 1'b0, 32'd0, 4'b1111, 1'b0); // miss Tag 2 -> evicts dirty Way 1 (0x0020)!
        checked_op(16'h0000, 1'b0, 32'd0, 4'b1111, 1'b1); // 0x0000 MUST STILL HIT!

        // D4: Clean-victim eviction check!
        // Currently Set 0: Way 0 = 0x0000 (DIRTY & MRU), Way 1 = 0x0040 (CLEAN & LRU).
        // Accessing Tag 3 (0x0060) MUST evict CLEAN Way 1 with ZERO wr_mem!
        checked_op(16'h0060, 1'b0, 32'd0, 4'b1111, 1'b1);

        // D5: Mid-run reset_n tag invalidation check!
        // 0x0000 is dirty in cache (0xDEAD_BEEF), while ext_mem[0] is still 0xA000_0000.
        // Update ext_mem[0] to 0x1234_5678, pulse reset_n, and verify cache MISSES & reads 0x1234_5678!
        reset_n = 1'b0;
        rd_cpu  = 1'b0;
        wr_cpu  = 1'b0;
        repeat (3) @(posedge clock);
        ext_mem[0]       = 32'h1234_5678;
        for (k = 0; k < 16384; k = k + 1) gold_arch_mem[k] = ext_mem[k];
        golden_reset_cache();
        #1;
        reset_n = 1'b1;
        // Issue read IMMEDIATELY on cycle 0 after reset release (tests S_INIT stall too!)
        checked_op(16'h0000, 1'b0, 32'd0, 4'b1111, 1'b1);

        $display("PASS [Directed Cache Audit]: D1(b2b cross-set), D2(write-alloc+partial), D3(LRU dirty WB), D4(clean victim 0-WB), D5(reset invalidation)");

        // =====================================================================
        // 2,500-OP RANDOMIZED GOLDEN-SCOREBOARD STRESS TEST
        // =====================================================================
        rand_latency_en = 1'b1;

        for (iter = 0; iter < 2500; iter = iter + 1) begin
            // Periodic mid-run reset every 600 ops to stress S_INIT tag invalidation
            if (iter > 0 && (iter % 600) == 0) begin
                rd_cpu  = 1'b0;
                wr_cpu  = 1'b0;
                reset_n = 1'b0;
                repeat (2) @(posedge clock);
                for (k = 0; k < 16384; k = k + 1) gold_arch_mem[k] = ext_mem[k];
                golden_reset_cache();
                #1;
                reset_n = 1'b1;
                rand_resets = rand_resets + 1;
            end

            prng  = xorshift32(prng);
            r32   = prng;
            // Focus on 5 conflicting tags per set across all 8 sets so hits, misses,
            // clean evictions, and dirty writebacks all occur heavily!
            raddr = {8'd0, r32[2:0] % 3'd5, r32[5:3], 2'b00};
            rwr   = r32[6];
            // Mix full-word writes (60%) with random partial byte strobes (40%)
            if ((r32[11:8] % 4'd10) < 4'd6)
                rstrb = 4'b1111;
            else
                rstrb = r32[15:12];
            ridle = (r32[18:16] == 3'd0); // ~87.5% zero-gap back-to-back!
            prng  = xorshift32(prng);
            rval  = prng;

            checked_op(raddr, rwr, rval, rstrb, ridle);
            if (ridle) begin
                @(posedge clock);
                #1;
            end
        end

        // Final check: force eviction of all 8 sets x 2 ways using fresh tags 6 & 7,
        // then verify EVERY word of ext_mem matches gold_arch_mem!
        for (s = 0; s < 8; s = s + 1) begin
            checked_op({8'd0, 3'd6, s[2:0], 2'b00}, 1'b0, 32'd0, 4'b1111, 1'b0);
            checked_op({8'd0, 3'd7, s[2:0], 2'b00}, 1'b0, 32'd0, 4'b1111, 1'b0);
        end
        rd_cpu = 1'b0;
        wr_cpu = 1'b0;
        @(posedge clock);

        for (k = 0; k < 1024; k = k + 1) begin
            if (ext_mem[k] !== gold_arch_mem[k]) begin
                $display("FAIL [FINAL FLUSH COHERENCE]: word %0d ext_mem=0x%08h gold=0x%08h",
                         k, ext_mem[k], gold_arch_mem[k]);
                $finish(1);
            end
        end

        $display("PASS [Randomized Golden Scoreboard]: 2500 random ops + flush verified! hits=%0d misses=%0d dirty_wbs=%0d clean_evicts=%0d resets=%0d",
                 tot_hits, tot_misses, tot_wbs, tot_clean_evicts, rand_resets);
        $finish;
    end

endmodule
