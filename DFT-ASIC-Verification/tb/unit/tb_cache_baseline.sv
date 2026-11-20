`timescale 1ns/1ps

module tb_cache_baseline;
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

    reg         bist_en;
    reg  [1:0]  bist_bank_sel;
    reg  [2:0]  bist_addr;
    reg  [31:0] bist_din;
    reg         bist_we;
    wire [31:0] bist_dout;

    reg         inj_en;
    reg  [1:0]  inj_bank;
    reg  [2:0]  inj_addr;
    reg  [5:0]  inj_bit;
    reg  [1:0]  inj_type;

    cache_2wsa_dft dut (
        .clock         (clock),
        .reset_n       (reset_n),
        .addr_cpu      (addr_cpu),
        .cpu_wdata     (cpu_wdata),
        .cpu_wstrb     (cpu_wstrb),
        .rd_cpu        (rd_cpu),
        .wr_cpu        (wr_cpu),
        .cpu_rdata     (cpu_rdata),
        .stall_cpu     (stall_cpu),
        .addr_mem      (addr_mem),
        .mem_wdata     (mem_wdata),
        .mem_rdata     (mem_rdata),
        .rd_mem        (rd_mem),
        .wr_mem        (wr_mem),
        .ready_mem     (ready_mem),
        .cache_hit     (cache_hit),
        .cache_miss    (cache_miss),
        .cache_wb      (cache_wb),
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

    initial clock = 1'b0;
    always #5 clock = ~clock;

    // Strictly synchronous registered backing memory with variable latency
    reg [31:0] ext_mem [0:16383];
    reg        mm_busy;
    reg        mm_is_wr;
    reg [13:0] mm_addr;
    reg [31:0] mm_wdata;
    reg [3:0]  mm_cnt;
    reg [31:0] mm_prng;
    integer    obs_hit_cnt, obs_miss_cnt, obs_wb_cnt, obs_rd_mem_cnt, obs_wr_mem_cnt;

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

    /* verilator lint_off SYNCASYNCNET */
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            ready_mem      <= 1'b0;
            mem_rdata      <= 32'd0;
            mm_busy        <= 1'b0;
            mm_is_wr       <= 1'b0;
            mm_addr        <= 14'd0;
            mm_wdata       <= 32'd0;
            mm_cnt         <= 4'd0;
            obs_hit_cnt    <= 0;
            obs_miss_cnt   <= 0;
            obs_wb_cnt     <= 0;
            obs_rd_mem_cnt <= 0;
            obs_wr_mem_cnt <= 0;
        end else begin
            ready_mem <= 1'b0;
            if (cache_hit)  obs_hit_cnt  <= obs_hit_cnt + 1;
            if (cache_miss) obs_miss_cnt <= obs_miss_cnt + 1;
            if (cache_wb)   obs_wb_cnt   <= obs_wb_cnt + 1;

            if (!mm_busy) begin
                if (!ready_mem && (rd_mem || wr_mem)) begin
                    mm_prng <= xorshift32(mm_prng);
                    if (wr_mem) obs_wr_mem_cnt <= obs_wr_mem_cnt + 1;
                    else        obs_rd_mem_cnt <= obs_rd_mem_cnt + 1;

                    if ((mm_prng[2:0] % 3'd5) == 3'd0) begin
                        if (wr_mem) ext_mem[addr_mem[15:2]] <= mem_wdata;
                        else        mem_rdata <= ext_mem[addr_mem[15:2]];
                        ready_mem <= 1'b1;
                    end else begin
                        mm_busy  <= 1'b1;
                        mm_is_wr <= wr_mem;
                        mm_addr  <= addr_mem[15:2];
                        mm_wdata <= mem_wdata;
                        mm_cnt   <= 4'd1 + {1'b0, (mm_prng[5:3] % 3'd4)};
                    end
                end
            end else begin
                if (mm_cnt == 4'd1) begin
                    if (mm_is_wr) ext_mem[mm_addr] <= mm_wdata;
                    else          mem_rdata <= ext_mem[mm_addr];
                    ready_mem <= 1'b1;
                    mm_busy   <= 1'b0;
                    mm_cnt    <= 4'd0;
                end else begin
                    mm_cnt <= mm_cnt - 4'd1;
                end
            end
        end
    end
    /* verilator lint_on SYNCASYNCNET */

    // Golden 2-way LRU cache + architectural memory scoreboard
    reg [31:0] gold_mem [0:16383];
    reg        g_valid [0:7][0:1];
    reg        g_dirty [0:7][0:1];
    reg [10:0] g_tag   [0:7][0:1];
    reg [31:0] g_data  [0:7][0:1];
    reg        g_mru   [0:7];

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

    task automatic golden_clear;
        integer s, w;
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

    task automatic checked_op(
        input [15:0] addr,
        input        is_wr,
        input [31:0] wdata,
        input [3:0]  wstrb,
        input        idle_after
    );
        integer    guard, pre_hit, pre_miss, pre_wb, pre_wr;
        reg [10:0] tag;
        reg [2:0]  idx;
        reg        h0, h1, exp_hit, vic, exp_wb;
        reg [31:0] got_rdata, line_val;
        begin
            tag = addr[15:5];
            idx = addr[4:2];
            h0  = g_valid[idx][0] && (g_tag[idx][0] == tag);
            h1  = g_valid[idx][1] && (g_tag[idx][1] == tag);
            exp_hit = h0 || h1;

            pre_hit  = obs_hit_cnt;
            pre_miss = obs_miss_cnt;
            pre_wb   = obs_wb_cnt;
            pre_wr   = obs_wr_mem_cnt;

            addr_cpu  = addr;
            cpu_wdata = wdata;
            cpu_wstrb = wstrb;
            rd_cpu    = !is_wr;
            wr_cpu    = is_wr;
            #1;
            guard = 0;
            while (stall_cpu && guard < 80) begin
                @(posedge clock);
                #1;
                guard = guard + 1;
            end
            if (guard >= 80) begin
                $display("FAIL: timeout on addr=0x%04h wr=%b", addr, is_wr);
                $finish(1);
            end
            got_rdata = cpu_rdata;
            @(posedge clock);
            #1;
            if (idle_after) begin
                rd_cpu = 1'b0;
                wr_cpu = 1'b0;
            end

            if (!is_wr && (got_rdata !== gold_mem[addr[15:2]])) begin
                $display("FAIL [READ]: addr=0x%04h got=0x%08h exp=0x%08h",
                         addr, got_rdata, gold_mem[addr[15:2]]);
                $finish(1);
            end

            if (exp_hit) begin
                if ((obs_hit_cnt - pre_hit) != 1 || (obs_miss_cnt - pre_miss) != 0 || (obs_wr_mem_cnt - pre_wr) != 0) begin
                    $display("FAIL [HIT CNT]: addr=0x%04h d_hit=%0d d_miss=%0d d_wr=%0d",
                             addr, obs_hit_cnt - pre_hit, obs_miss_cnt - pre_miss, obs_wr_mem_cnt - pre_wr);
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
                vic = (!g_valid[idx][0]) ? 1'b0 : (!g_valid[idx][1]) ? 1'b1 : g_mru[idx];
                exp_wb = g_valid[idx][vic] && g_dirty[idx][vic];
                if ((obs_miss_cnt - pre_miss) != 1 || (obs_wb_cnt - pre_wb) != (exp_wb ? 1 : 0) ||
                    (obs_wr_mem_cnt - pre_wr) != (exp_wb ? 1 : 0)) begin
                    $display("FAIL [MISS/WB CNT]: addr=0x%04h exp_wb=%b d_miss=%0d d_wb=%0d d_wr=%0d",
                             addr, exp_wb, obs_miss_cnt - pre_miss, obs_wb_cnt - pre_wb, obs_wr_mem_cnt - pre_wr);
                    $finish(1);
                end
                line_val = ext_mem[addr[15:2]];
                if (is_wr && (|wstrb)) line_val = apply_wstrb(line_val, wdata, wstrb);
                g_valid[idx][vic] = 1'b1;
                g_dirty[idx][vic] = is_wr && (|wstrb);
                g_tag[idx][vic]   = tag;
                g_data[idx][vic]  = line_val;
                g_mru[idx]        = !vic;
            end
            if (is_wr && (|wstrb)) begin
                gold_mem[addr[15:2]] = apply_wstrb(gold_mem[addr[15:2]], wdata, wstrb);
            end
        end
    endtask

    integer    k, iter;
    reg [31:0] prng, r32, rval;
    reg [15:0] raddr;
    reg [3:0]  rstrb;

    initial begin
        addr_cpu      = 16'd0;
        cpu_wdata     = 32'd0;
        cpu_wstrb     = 4'b1111;
        rd_cpu        = 1'b0;
        wr_cpu        = 1'b0;
        bist_en       = 1'b0;
        bist_bank_sel = 2'd0;
        bist_addr     = 3'd0;
        bist_din      = 32'd0;
        bist_we       = 1'b0;
        inj_en        = 1'b0;
        inj_bank      = 2'd0;
        inj_addr      = 3'd0;
        inj_bit       = 6'd0;
        inj_type      = 2'd0;
        prng          = 32'hCAFE_2026;
        mm_prng       = 32'h1357_2468;

        for (k = 0; k < 16384; k = k + 1) begin
            ext_mem[k]  = {16'hB000, k[15:0]};
            gold_mem[k] = {16'hB000, k[15:0]};
        end
        golden_clear();

        reset_n = 1'b0;
        repeat (3) @(posedge clock);
        #1;
        reset_n = 1'b1;

        // Directed cross-set, write-back deferral, clean-victim 0-WB, dirty eviction
        checked_op(16'h0000, 1'b0, 32'd0,         4'b1111, 1'b0);
        checked_op(16'h000C, 1'b0, 32'd0,         4'b1111, 1'b0);
        checked_op(16'h0000, 1'b1, 32'hDEAD_BEEF, 4'b1111, 1'b0);
        checked_op(16'h000C, 1'b0, 32'd0,         4'b1111, 1'b0);
        checked_op(16'h0020, 1'b1, 32'h0000_5A00, 4'b0010, 1'b0);
        checked_op(16'h0000, 1'b0, 32'd0,         4'b1111, 1'b0);
        checked_op(16'h0040, 1'b0, 32'd0,         4'b1111, 1'b0); // evicts dirty 0x0020
        checked_op(16'h0000, 1'b0, 32'd0,         4'b1111, 1'b0); // Way 0 MRU dirty, Way 1 LRU clean
        checked_op(16'h0060, 1'b0, 32'd0,         4'b1111, 1'b1); // clean victim -> 0 WB!

        // 1,000-op randomized golden-scoreboard sweep (with mid-stream reset)
        for (iter = 0; iter < 1000; iter = iter + 1) begin
            if (iter == 500) begin
                rd_cpu  = 1'b0;
                wr_cpu  = 1'b0;
                reset_n = 1'b0;
                repeat (2) @(posedge clock);
                for (k = 0; k < 1024; k = k + 1) gold_mem[k] = ext_mem[k];
                golden_clear();
                #1;
                reset_n = 1'b1;
            end
            prng  = xorshift32(prng);
            r32   = prng;
            raddr = {8'd0, r32[2:0] % 3'd5, r32[5:3], 2'b00};
            rstrb = ((r32[11:8] % 4'd10) < 4'd6) ? 4'b1111 : r32[15:12];
            prng  = xorshift32(prng);
            rval  = prng;
            checked_op(raddr, r32[6], rval, rstrb, (r32[18:16] == 3'd0));
        end
        rd_cpu = 1'b0;
        wr_cpu = 1'b0;
        @(posedge clock);

        $display("PASS [Cache Functional]: directed + 1000-op randomized scoreboard verified (hits=%0d misses=%0d wbs=%0d)",
                 obs_hit_cnt, obs_miss_cnt, obs_wb_cnt);

        // MBIST port + fault-injection verification on bank 2 (data RAM way 0)
        @(negedge clock);
        bist_en       = 1'b1;
        bist_bank_sel = 2'd2;
        bist_addr     = 3'd5;
        bist_din      = 32'hDEADBEEF;
        bist_we       = 1'b1;
        @(posedge clock);
        @(negedge clock);
        bist_we = 1'b0;
        @(posedge clock);
        #1;
        if (bist_dout !== 32'hDEADBEEF) begin
            $display("FAIL [MBIST port]: expected 0xDEADBEEF, got 0x%h", bist_dout);
            $finish(1);
        end

        inj_en   = 1'b1;
        inj_bank = 2'd2;
        inj_addr = 3'd5;
        inj_bit  = 6'd0;
        inj_type = 2'd1; // SA0
        #1;
        if (bist_dout !== 32'hDEADBEEE) begin
            $display("FAIL [Fault Inject]: expected 0xDEADBEEE, got 0x%h", bist_dout);
            $finish(1);
        end
        inj_en  = 1'b0;
        bist_en = 1'b0;
        $display("PASS [MBIST Hook & Fault Injection]: SRAM mux and SA0 fault hook verified");
        $finish;
    end
endmodule
