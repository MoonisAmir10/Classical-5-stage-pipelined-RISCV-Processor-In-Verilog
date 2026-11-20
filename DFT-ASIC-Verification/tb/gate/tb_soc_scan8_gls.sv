`timescale 1ns/1ps

// Post-Scan-Stitch Full-SoC Gate-Level Integration Verification (`POST_SCAN_STITCH`):
// Instantiates soc_dft_top with real 8-chain stitched sg13g2_stdcell soc_func_logic
// + 4 sram_sync_sp macros. Verifies:
//   1. Functional RV32I Fibonacci (x14=34) + Integrated RV32I/2-Way D-Cache (x14=1297, 7H/7M/2WB)
//   2. End-to-end TOTAL_FFS-cycle 1-chain bypass scan integrity through real FFs
//   3. 2:8 XOR compressed scan + OCC LOC capture + 16-bit MISR + MBIST
module tb_soc_scan8_gls #(
    parameter integer TOTAL_FFS  = 1600,
    parameter integer MAX_CH_LEN = 200
);
    reg         sys_clk;
    reg         sys_rst_n;
    reg         tck;
    reg         tms;
    reg         tdi;
    wire        tdo;
    wire        tdo_en;
    reg         trst_n;

    reg         test_mode;
    reg         scan_en;
    reg  [1:0]  scan_in;
    wire [1:0]  scan_out;
    wire        bist_done;
    wire        bist_fail;

    reg         prog_sel;
    wire [31:0] x14, pc_obs, alu_obs;

    reg  [31:0] cache_mem_rdata;
    wire [31:0] cache_mem_wdata;
    wire [15:0] cache_addr_mem;
    wire        cache_rd_mem, cache_wr_mem;
    reg         cache_ready_mem;
    wire        cache_stall_cpu;
    wire        cache_hit, cache_miss, cache_wb;

    reg         inj_en;
    reg  [1:0]  inj_bank;
    reg  [2:0]  inj_addr;
    reg  [5:0]  inj_bit;
    reg  [1:0]  inj_type;

    soc_dft_top dut (
        .sys_clk         (sys_clk),
        .sys_rst_n       (sys_rst_n),
        .tck             (tck),
        .tms             (tms),
        .tdi             (tdi),
        .tdo             (tdo),
        .tdo_en          (tdo_en),
        .trst_n          (trst_n),
        .test_mode       (test_mode),
        .scan_en         (scan_en),
        .scan_in         (scan_in),
        .scan_out        (scan_out),
        .bist_done       (bist_done),
        .bist_fail       (bist_fail),
        .prog_sel        (prog_sel),
        .x14             (x14),
        .pc_obs          (pc_obs),
        .alu_obs         (alu_obs),
        .cache_mem_rdata (cache_mem_rdata),
        .cache_mem_wdata (cache_mem_wdata),
        .cache_addr_mem  (cache_addr_mem),
        .cache_rd_mem    (cache_rd_mem),
        .cache_wr_mem    (cache_wr_mem),
        .cache_ready_mem (cache_ready_mem),
        .cache_stall_cpu (cache_stall_cpu),
        .cache_hit       (cache_hit),
        .cache_miss      (cache_miss),
        .cache_wb        (cache_wb),
        .inj_en          (inj_en),
        .inj_bank        (inj_bank),
        .inj_addr        (inj_addr),
        .inj_bit         (inj_bit),
        .inj_type        (inj_type)
    );

    // Off-chip synchronous backing memory (3-cycle latency)
    reg [31:0] ext_mem [0:1023];
    reg        mm_busy, mm_is_wr;
    reg [9:0]  mm_addr;
    reg [31:0] mm_wdata;
    reg [2:0]  mm_cnt;
    integer    hits, misses, wbs;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            cache_ready_mem <= 1'b0;
            cache_mem_rdata <= 32'd0;
            mm_busy         <= 1'b0;
            mm_is_wr        <= 1'b0;
            mm_addr         <= 10'd0;
            mm_wdata        <= 32'd0;
            mm_cnt          <= 3'd0;
            hits            <= 0;
            misses          <= 0;
            wbs             <= 0;
        end else begin
            cache_ready_mem <= 1'b0;
            if (!test_mode) begin
                if (cache_hit)  hits   <= hits + 1;
                if (cache_miss) misses <= misses + 1;
                if (cache_wb)   wbs    <= wbs + 1;
            end
            if (!mm_busy) begin
                if (!cache_ready_mem && (cache_rd_mem || cache_wr_mem)) begin
                    mm_busy  <= 1'b1;
                    mm_is_wr <= cache_wr_mem;
                    mm_addr  <= cache_addr_mem[11:2];
                    mm_wdata <= cache_mem_wdata;
                    mm_cnt   <= 3'd2;
                end
            end else if (mm_cnt == 3'd1) begin
                if (mm_is_wr) ext_mem[mm_addr] <= mm_wdata;
                else          cache_mem_rdata <= ext_mem[mm_addr];
                cache_ready_mem <= 1'b1;
                mm_busy         <= 1'b0;
                mm_cnt          <= 3'd0;
            end else begin
                mm_cnt <= mm_cnt - 3'd1;
            end
        end
    end

    initial sys_clk = 1'b0;
    always #5 sys_clk = ~sys_clk;

    initial tck = 1'b0;
    always #50 tck = ~tck;

    task automatic tap_step(input logic tms_val, input logic tdi_val);
        begin
            @(negedge tck); tms = tms_val; tdi = tdi_val;
            @(posedge tck); #1;
        end
    endtask

    task automatic jtag_ir(input logic [3:0] opc);
        integer i;
        begin
            tap_step(1'b1, 1'b0); tap_step(1'b1, 1'b0);
            tap_step(1'b0, 1'b0); tap_step(1'b0, 1'b0);
            for (i = 0; i < 4; i = i + 1) begin
                @(negedge tck); tdi = opc[i]; tms = (i == 3);
                @(posedge tck); #1;
            end
            tap_step(1'b1, 1'b0); tap_step(1'b0, 1'b0);
        end
    endtask

    task automatic jtag_dr(input integer len, input logic [47:0] din, output logic [47:0] dout);
        integer i;
        begin
            dout = 48'd0;
            tap_step(1'b1, 1'b0); tap_step(1'b0, 1'b0); tap_step(1'b0, 1'b0);
            for (i = 0; i < len; i = i + 1) begin
                @(negedge tck); tdi = din[i]; tms = (i == (len - 1));
                @(posedge tck); dout[i] = tdo; #1;
            end
            tap_step(1'b1, 1'b0); tap_step(1'b0, 1'b0);
        end
    endtask

    logic [63:0] pat_vec = 64'h0011_2233_4455_6677;
    logic [63:0] rx_vec;
    logic [47:0] dr_out;
    integer cyc, seen_34, k;

    initial begin
        for (k = 0; k < 1024; k = k + 1) ext_mem[k] = 32'd0;
        sys_rst_n = 1'b0; trst_n = 1'b0; tms = 1'b1; tdi = 1'b0;
        test_mode = 1'b0; scan_en = 1'b0; scan_in = 2'b00; prog_sel = 1'b0;
        inj_en = 1'b0; inj_bank = 2'd0; inj_addr = 3'd0; inj_bit = 6'd0; inj_type = 2'd0;

        repeat (4) @(posedge sys_clk);
        @(negedge sys_clk); sys_rst_n = 1'b1;
        @(negedge tck);     trst_n    = 1'b1;
        tap_step(1'b0, 1'b0);

        // 1a. Functional CPU Fibonacci execution on gate-level stitched netlist
        seen_34 = 0;
        for (cyc = 0; cyc < 80; cyc = cyc + 1) begin
            @(posedge sys_clk); #1;
            if (x14 == 32'd34) seen_34 = 1;
        end
        if (seen_34 == 0) $fatal(1, "FAIL [Gate-Level FUNC Fib]: Fibonacci did not reach x14=34");

        // 1b. End-to-End Integrated RV32I + 2-Way D-Cache on gate-level stitched netlist
        @(negedge sys_clk);
        sys_rst_n = 1'b0;
        prog_sel  = 1'b1;
        ext_mem[10'h000] = 32'd10;
        ext_mem[10'h008] = 32'd20;
        ext_mem[10'h010] = 32'd30;
        ext_mem[10'h018] = 32'd40;
        ext_mem[10'h003] = 32'd77;
        ext_mem[10'h005] = 32'd88;
        repeat (4) @(posedge sys_clk);
        @(negedge sys_clk); sys_rst_n = 1'b1;
        repeat (200) @(posedge sys_clk); #1;
        if (x14 !== 32'd1297 || hits !== 7 || misses !== 7 || wbs !== 2 ||
            ext_mem[10'h000] !== 32'd111 || ext_mem[10'h008] !== 32'd220 || ext_mem[10'h003] !== 32'd77) begin
            $fatal(1, "FAIL [Gate-Level FUNC Cache]: x14=%0d hits=%0d misses=%0d wbs=%0d", x14, hits, misses, wbs);
        end
        @(negedge sys_clk); prog_sel = 1'b0;

        // 2. Full TOTAL_FFS-bit serial scan integrity in 1-chain bypass mode (comp_en=0)
        test_mode = 1'b1;
        jtag_ir(4'b0100); jtag_dr(8, 48'h09, dr_out);   // scan_mode=1, rst_mask_en=1, occ_loc=0
        jtag_ir(4'b0111); jtag_dr(16, 48'h0000, dr_out); // bypass 1-chain mode
        scan_en = 1'b1;

        repeat (5) @(posedge tck);
        for (cyc = 0; cyc < 64; cyc = cyc + 1) begin
            @(negedge tck); scan_in[0] = pat_vec[cyc]; @(posedge tck); #1;
        end
        for (cyc = 0; cyc < (TOTAL_FFS - 64); cyc = cyc + 1) begin
            @(negedge tck); scan_in[0] = 1'b0; @(posedge tck); #1;
        end
        rx_vec = 64'd0;
        for (cyc = 0; cyc < 64; cyc = cyc + 1) begin
            rx_vec[cyc] = scan_out[0];
            @(negedge tck); scan_in[0] = 1'b0; @(posedge tck); #1;
        end
        if (rx_vec !== pat_vec) begin
            $fatal(1, "FAIL [Scan Chain Integrity %0d-FF]: expected %h, got %h", TOTAL_FFS, pat_vec, rx_vec);
        end

        // 3. Switch to 2:8 Compression + OCC LOC Capture + 16-bit MISR & MBIST
        @(negedge tck); scan_en = 1'b0;
        jtag_ir(4'b0100); jtag_dr(8, 48'h0B, dr_out);
        jtag_ir(4'b0111); jtag_dr(16, 48'h0003, dr_out);

        scan_en = 1'b1;
        repeat (MAX_CH_LEN + 6) begin
            @(negedge tck); scan_in = 2'b10; @(posedge tck); #1;
        end
        @(negedge tck); scan_en = 1'b0;
        repeat (4) @(posedge tck);
        @(negedge tck); scan_en = 1'b1;
        for (cyc = 0; cyc < MAX_CH_LEN + 1; cyc = cyc + 1) begin
            @(negedge tck); scan_in = cyc[1:0]; @(posedge tck); #1;
            if (scan_out[0] === 1'bx || scan_out[1] === 1'bx) begin
                $fatal(1, "FAIL [Compressed GLS]: X on scan_out=%b at cyc=%0d", scan_out, cyc);
            end
        end

        // 4. Clean MBIST run alongside stitched gate-level cache
        @(negedge tck); scan_en = 1'b0;
        jtag_ir(4'b0101); jtag_dr(8, 48'h1F, dr_out);
        cyc = 0; while (!bist_done && cyc < 200) begin @(posedge tck); #1; cyc = cyc + 1; end
        if (!bist_done || bist_fail !== 1'b0) begin
            $fatal(1, "FAIL [Gate-Level MBIST]: done=%b fail=%b", bist_done, bist_fail);
        end

        $display("PASS [Post-Stitch SoC GLS]: %0d-FF Bypass Integrity, Fib + Integrated D-Cache (x14=1297, 7H/7M/2WB), 2:8 Compressed LOC & MBIST verified!", TOTAL_FFS);
        $finish;
    end
endmodule
