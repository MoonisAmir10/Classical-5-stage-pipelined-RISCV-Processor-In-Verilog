`timescale 1ns/1ps

module tb_scan_chain_generic #(
    parameter integer NUM_CHAINS = 8,
    parameter integer TOTAL_FFS  = 2151
) ();

    localparam integer REM     = TOTAL_FFS % NUM_CHAINS;
    localparam integer BASE_L  = TOTAL_FFS / NUM_CHAINS;
    localparam integer MAX_LEN = BASE_L + ((REM > 0) ? 1 : 0);

    reg clk;
    reg rst_n;
    reg prog_sel;
    reg scan_en;
    reg [NUM_CHAINS-1:0] scan_in;
    wire [NUM_CHAINS-1:0] scan_out;

    wire [31:0] x14;
    wire [31:0] pc_obs;
    wire [31:0] alu_obs;

    // External CPU/Mem stub tied idle so only RV32I processor runs
    reg  [7:0]  cache_cpu_wdata;
    wire [7:0]  cache_cpu_rdata;
    wire        cache_cpu_rdata_oe;
    reg  [15:0] cache_addr_cpu;
    reg         cache_rd_cpu;
    reg         cache_wr_cpu;
    wire        cache_stall_cpu;
    reg  [7:0]  cache_mem_rdata;
    wire [7:0]  cache_mem_wdata;
    wire        cache_mem_wdata_oe;
    wire [15:0] cache_addr_mem;
    wire        cache_rd_mem;
    wire        cache_wr_mem;
    reg         cache_ready_mem;

    // MBIST stub tied idle
    reg         bist_en;
    reg  [1:0]  bist_bank_sel;
    reg  [2:0]  bist_addr;
    reg  [31:0] bist_din;
    reg         bist_we;
    wire [31:0] bist_dout;

    // SRAM macro boundary signals
    wire [2:0]  sram_index;
    wire [13:0] sram_wtag0, sram_wtag1;
    wire        sram_wet0, sram_wet1;
    wire [31:0] sram_wdata;
    wire        sram_we0, sram_we1;
    wire [13:0] sram_rtag0, sram_rtag1;
    wire [31:0] sram_rdata0, sram_rdata1;
    wire        sram_bist_en_t0, sram_bist_en_t1, sram_bist_en_d0, sram_bist_en_d1;
    wire [2:0]  sram_bist_addr;
    wire [13:0] sram_bist_din_tag;
    wire [31:0] sram_bist_din_data;
    wire        sram_bist_we;
    wire [13:0] sram_bist_dout_t0, sram_bist_dout_t1;
    wire [31:0] sram_bist_dout_d0, sram_bist_dout_d1;

    soc_func_logic dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .prog_sel          (prog_sel),
        .x14               (x14),
        .pc_obs            (pc_obs),
        .alu_obs           (alu_obs),
        .cache_cpu_wdata   (cache_cpu_wdata),
        .cache_cpu_rdata   (cache_cpu_rdata),
        .cache_cpu_rdata_oe(cache_cpu_rdata_oe),
        .cache_addr_cpu    (cache_addr_cpu),
        .cache_rd_cpu      (cache_rd_cpu),
        .cache_wr_cpu      (cache_wr_cpu),
        .cache_stall_cpu   (cache_stall_cpu),
        .cache_mem_rdata   (cache_mem_rdata),
        .cache_mem_wdata   (cache_mem_wdata),
        .cache_mem_wdata_oe(cache_mem_wdata_oe),
        .cache_addr_mem    (cache_addr_mem),
        .cache_rd_mem      (cache_rd_mem),
        .cache_wr_mem      (cache_wr_mem),
        .cache_ready_mem   (cache_ready_mem),
        .bist_en           (bist_en),
        .bist_bank_sel     (bist_bank_sel),
        .bist_addr         (bist_addr),
        .bist_din          (bist_din),
        .bist_we           (bist_we),
        .bist_dout         (bist_dout),
        .sram_index        (sram_index),
        .sram_wtag0        (sram_wtag0),
        .sram_wtag1        (sram_wtag1),
        .sram_wet0         (sram_wet0),
        .sram_wet1         (sram_wet1),
        .sram_wdata        (sram_wdata),
        .sram_we0          (sram_we0),
        .sram_we1          (sram_we1),
        .sram_rtag0        (sram_rtag0),
        .sram_rtag1        (sram_rtag1),
        .sram_rdata0       (sram_rdata0),
        .sram_rdata1       (sram_rdata1),
        .sram_bist_en_t0   (sram_bist_en_t0),
        .sram_bist_en_t1   (sram_bist_en_t1),
        .sram_bist_en_d0   (sram_bist_en_d0),
        .sram_bist_en_d1   (sram_bist_en_d1),
        .sram_bist_addr     (sram_bist_addr),
        .sram_bist_din_tag  (sram_bist_din_tag),
        .sram_bist_din_data (sram_bist_din_data),
        .sram_bist_we       (sram_bist_we),
        .sram_bist_dout_t0  (sram_bist_dout_t0),
        .sram_bist_dout_t1  (sram_bist_dout_t1),
        .sram_bist_dout_d0  (sram_bist_dout_d0),
        .sram_bist_dout_d1  (sram_bist_dout_d1),
        .scan_en           (scan_en),
        .scan_in           (scan_in),
        .scan_out          (scan_out)
    );

    sram_sync_sp #(.AWIDTH(3), .DWIDTH(14)) u_sram_tag_way0 (
        .clock(clk), .addr(sram_index), .din(sram_wtag0), .we(sram_wet0), .dout(sram_rtag0),
        .bist_en(sram_bist_en_t0), .bist_addr(sram_bist_addr), .bist_din(sram_bist_din_tag),
        .bist_we(sram_bist_we), .bist_dout(sram_bist_dout_t0),
        .inj_en(1'b0), .inj_addr(3'd0), .inj_bit(6'd0), .inj_type(2'b00)
    );
    sram_sync_sp #(.AWIDTH(3), .DWIDTH(14)) u_sram_tag_way1 (
        .clock(clk), .addr(sram_index), .din(sram_wtag1), .we(sram_wet1), .dout(sram_rtag1),
        .bist_en(sram_bist_en_t1), .bist_addr(sram_bist_addr), .bist_din(sram_bist_din_tag),
        .bist_we(sram_bist_we), .bist_dout(sram_bist_dout_t1),
        .inj_en(1'b0), .inj_addr(3'd0), .inj_bit(6'd0), .inj_type(2'b00)
    );
    sram_sync_sp #(.AWIDTH(3), .DWIDTH(32)) u_sram_data_way0 (
        .clock(clk), .addr(sram_index), .din(sram_wdata), .we(sram_we0), .dout(sram_rdata0),
        .bist_en(sram_bist_en_d0), .bist_addr(sram_bist_addr), .bist_din(sram_bist_din_data),
        .bist_we(sram_bist_we), .bist_dout(sram_bist_dout_d0),
        .inj_en(1'b0), .inj_addr(3'd0), .inj_bit(6'd0), .inj_type(2'b00)
    );
    sram_sync_sp #(.AWIDTH(3), .DWIDTH(32)) u_sram_data_way1 (
        .clock(clk), .addr(sram_index), .din(sram_wdata), .we(sram_we1), .dout(sram_rdata1),
        .bist_en(sram_bist_en_d1), .bist_addr(sram_bist_addr), .bist_din(sram_bist_din_data),
        .bist_we(sram_bist_we), .bist_dout(sram_bist_dout_d1),
        .inj_en(1'b0), .inj_addr(3'd0), .inj_bit(6'd0), .inj_type(2'b00)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function automatic integer chain_len(input integer c);
        begin
            chain_len = BASE_L + ((c < REM) ? 1 : 0);
        end
    endfunction

    function automatic logic stream_bit(input integer c, input integer k);
        begin
            stream_bit = (((k >> 1) ^ (k >> 3) ^ c) & 1);
        end
    endfunction

    integer cyc, ch;
    integer err_cnt;
    integer extra_tail;
    integer seen_34;

    initial begin
        err_cnt         = 0;
        extra_tail      = 64;
        rst_n           = 1'b0;
        prog_sel        = 1'b0;
        scan_en         = 1'b0;
        scan_in         = {NUM_CHAINS{1'b0}};
        cache_cpu_wdata = 8'd0;
        cache_addr_cpu  = 16'd0;
        cache_rd_cpu    = 1'b0;
        cache_wr_cpu    = 1'b0;
        cache_mem_rdata = 8'd0;
        cache_ready_mem = 1'b0;
        bist_en         = 1'b0;
        bist_bank_sel   = 2'd0;
        bist_addr       = 3'd0;
        bist_din        = 32'd0;
        bist_we         = 1'b0;

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n   = 1'b1;
        scan_en = 1'b1;

        // Test 1: Parallel Scan Chain Shift Integrity across all NUM_CHAINS channels
        for (cyc = 0; cyc < MAX_LEN + extra_tail; cyc = cyc + 1) begin
            for (ch = 0; ch < NUM_CHAINS; ch = ch + 1) begin
                scan_in[ch] = stream_bit(ch, cyc);
            end
            @(posedge clk);
            @(negedge clk);
            for (ch = 0; ch < NUM_CHAINS; ch = ch + 1) begin
                if (cyc >= chain_len(ch) - 1) begin
                    if (scan_out[ch] !== stream_bit(ch, cyc - (chain_len(ch) - 1))) begin
                        if (err_cnt < 10) begin
                            $display("FAIL [Scan-%0d] ch=%0d len=%0d cyc=%0d exp=%b got=%b",
                                NUM_CHAINS, ch, chain_len(ch), cyc,
                                stream_bit(ch, cyc - (chain_len(ch) - 1)), scan_out[ch]);
                        end
                        err_cnt = err_cnt + 1;
                    end
                end
            end
        end

        if (err_cnt != 0) begin
            $display("FAIL [Scan-%0d]: %0d shift mismatches!", NUM_CHAINS, err_cnt);
            $fatal(1);
        end

        // Test 2: Re-reset and run Functional RV32I Fibonacci with scan_en=0
        scan_en  = 1'b0;
        scan_in  = {NUM_CHAINS{1'b0}};
        rst_n    = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n    = 1'b1;

        seen_34 = 0;
        for (cyc = 0; cyc < 100; cyc = cyc + 1) begin
            @(posedge clk);
            @(negedge clk);
            if (x14 === 32'd34) seen_34 = 1;
        end
        if (seen_34 == 0) begin
            $display("FAIL [Scan-%0d Functional]: expected x14=34 observed within 100 cycles after reset, last=%0d (0x%08x)",
                NUM_CHAINS, x14, x14);
            $fatal(1);
        end

        $display("PASS [Scan-%0d Chain GLS]: All %0d channels (%0d FFs, max_len=%0d) shift-verified + Fibonacci x14=34!",
            NUM_CHAINS, NUM_CHAINS, TOTAL_FFS, MAX_LEN);
        $finish;
    end

endmodule
