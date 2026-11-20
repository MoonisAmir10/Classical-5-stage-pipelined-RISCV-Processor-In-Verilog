`timescale 1ns/1ps

`ifndef DBG03_MUX_WIRE
`define DBG03_MUX_WIRE _scan_mux_d_642_
`endif

// Phase 5 Full-SoC Back-Annotated SDF Gate-Level Verification & Debug Suite:
// Targets `build/phase5/soc_dft_top_cts.v` annotated via `$sdf_annotate` (+SDF=...).
// Covers:
//   - FUNC: 100 MHz RV32I Fibonacci (`x14 == 34`) + Integrated RV32I/D-Cache (`x14 == 1297`)
//   - ATPG-01 / GLS-01: TOTAL_FFS-FF `00110011...` bypass scan integrity @ 10 MHz TCK
//   - MBIST: Clean March-C run across all 4 SRAM banks under clock-balanced SDF
//   - COMP+LOC: 2:8 Decompressor + 100 MHz 2-pulse LOC Capture + 16-bit MISR
//   - DBG-01: Un-masked async reset leak corrupting scan shift -> fixed by rst_mask_en=1
//   - DBG-03: Uninitialized Chain-3 X-flop corrupting MISR -> diagnosed to
//             reports/ate_sim_fail.log & isolated via chain_x_mask[3]=1 (`TDR_COMP_CFG`)
module tb_soc_sdf_gls #(
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
        .cache_wb        (cache_wb)
    );

    // Off-chip synchronous backing memory for 100 MHz SDF functional cache verification
    reg [31:0] ext_mem [0:1023];
    reg        mm_busy, mm_is_wr;
    reg [9:0]  mm_addr;
    reg [31:0] mm_wdata;
    reg [2:0]  mm_cnt;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            cache_ready_mem <= 1'b0;
            cache_mem_rdata <= 32'd0;
            mm_busy         <= 1'b0;
            mm_is_wr        <= 1'b0;
            mm_addr         <= 10'd0;
            mm_wdata        <= 32'd0;
            mm_cnt          <= 3'd0;
        end else begin
            cache_ready_mem <= 1'b0;
            if (!mm_busy) begin
                if (!cache_ready_mem && (cache_rd_mem === 1'b1 || cache_wr_mem === 1'b1)) begin
                    mm_busy  <= 1'b1;
                    mm_is_wr <= (cache_wr_mem === 1'b1);
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
    always #5 sys_clk = ~sys_clk; // 100 MHz

    initial tck = 1'b0;
    always #50 tck = ~tck; // 10 MHz

    task automatic tap_step(input logic tms_val, input logic tdi_val);
        begin
            @(negedge tck); tms = tms_val; tdi = tdi_val;
            @(posedge tck); #2;
        end
    endtask

    task automatic jtag_ir(input logic [3:0] opc);
        integer i;
        begin
            tap_step(1'b1, 1'b0); tap_step(1'b1, 1'b0);
            tap_step(1'b0, 1'b0); tap_step(1'b0, 1'b0);
            for (i = 0; i < 4; i = i + 1) begin
                @(negedge tck); tdi = opc[i]; tms = (i == 3);
                @(posedge tck); #2;
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
                @(posedge tck); #2; dout[i] = tdo;
            end
            tap_step(1'b1, 1'b0); tap_step(1'b0, 1'b0);
        end
    endtask

    function automatic logic pat0011(input integer k);
        begin
            pat0011 = ((k >> 1) & 1);
        end
    endfunction

    string  sdf_file;
    string  fail_log_path;
    integer fail_fd;
    integer write_fail_log;
    integer quick_corner;
    integer cyc, seen_34, k;
    integer mismatch_cnt, x_cnt;
    integer inj_at;
    logic [47:0] dr_out;
    logic [15:0] golden_misr;
    logic [15:0] masked_misr;

    initial begin
        for (k = 0; k < 1024; k = k + 1) ext_mem[k] = 32'd0;
        if (!$value$plusargs("SDF=%s", sdf_file)) begin
            sdf_file = "build/phase5/soc_dft_top_slow.sdf";
        end
        quick_corner = $test$plusargs("QUICK_CORNER");
        write_fail_log = $value$plusargs("FAIL_LOG=%s", fail_log_path);
        $sdf_annotate(sdf_file, dut, , , "MAXIMUM");
        if (write_fail_log) begin
            fail_fd = $fopen(fail_log_path, "w");
        end else begin
            fail_fd = 0;
        end

        sys_rst_n = 1'b0; trst_n = 1'b0; tms = 1'b1; tdi = 1'b0;
        test_mode = 1'b0; scan_en = 1'b0; scan_in = 2'b00; prog_sel = 1'b0;

        repeat (6) @(posedge sys_clk);
        @(negedge sys_clk); sys_rst_n = 1'b1;
        @(negedge tck);     trst_n    = 1'b1;
        tap_step(1'b0, 1'b0); // Run-Test/Idle

        // -----------------------------------------------------------------
        // 1a. FUNC Mode @ 100 MHz (Fibonacci x14 == 34 under SDF back-annotation)
        // -----------------------------------------------------------------
        seen_34 = 0;
        for (cyc = 0; cyc < 100; cyc = cyc + 1) begin
            @(posedge sys_clk); #2;
            if (x14 === 32'd34) seen_34 = 1;
        end
        if (seen_34 == 0) begin
            $display("FAIL [SDF FUNC 100MHz Fib]: RV32I Fibonacci failed to reach x14=34 under %s", sdf_file);
            $fatal(1);
        end
        $display("PASS [SDF FUNC 100MHz Fib]: RV32I Fibonacci reached x14=34 cleanly (%s)", sdf_file);

        // -----------------------------------------------------------------
        // 1b. FUNC Mode @ 100 MHz (Integrated RV32I + 2-Way D-Cache x14 == 1297)
        // -----------------------------------------------------------------
        @(negedge sys_clk);
        sys_rst_n = 1'b0;
        prog_sel  = 1'b1;
        ext_mem[10'h000] = 32'd10;
        ext_mem[10'h008] = 32'd20;
        ext_mem[10'h010] = 32'd30;
        ext_mem[10'h018] = 32'd40;
        ext_mem[10'h003] = 32'd77;
        ext_mem[10'h005] = 32'd88;
        repeat (6) @(posedge sys_clk);
        @(negedge sys_clk); sys_rst_n = 1'b1;
        repeat (220) @(posedge sys_clk); #2;
        if (x14 !== 32'd1297 || ext_mem[10'h000] !== 32'd111 ||
            ext_mem[10'h008] !== 32'd220 || ext_mem[10'h003] !== 32'd77) begin
            $display("FAIL [SDF FUNC 100MHz Cache]: x14=%0d mm0=%0d mm8=%0d mm3=%0d (%s)",
                     x14, ext_mem[10'h000], ext_mem[10'h008], ext_mem[10'h003], sdf_file);
            $fatal(1);
        end
        $display("PASS [SDF FUNC 100MHz Cache]: Integrated RV32I + 2-Way D-Cache reached x14=1297 cleanly (%s)", sdf_file);
        @(negedge sys_clk); prog_sel = 1'b0;

        // -----------------------------------------------------------------
        // 2. GLS-01 / ATPG-01: 00110011... Scan Integrity in 1-Chain Bypass
        // -----------------------------------------------------------------
        test_mode = 1'b1;
        if (!quick_corner) begin
        jtag_ir(4'b0100); jtag_dr(8, 48'h09, dr_out);   // scan_mode=1, rst_mask_en=1
        jtag_ir(4'b0111); jtag_dr(16, 48'h0000, dr_out); // bypass 1-chain
        @(negedge tck); scan_en = 1'b1;
        repeat (5) @(posedge tck);

        mismatch_cnt = 0;
        @(negedge tck);
        for (cyc = 0; cyc < TOTAL_FFS + 128; cyc = cyc + 1) begin
            scan_in[0] = pat0011(cyc);
            @(posedge tck);
            @(negedge tck);
            if (cyc >= (TOTAL_FFS - 1)) begin
                if (scan_out[0] !== pat0011(cyc - (TOTAL_FFS - 1))) begin
                    if (mismatch_cnt < 5) begin
                        $display("FAIL [SDF Bypass Shift]: cyc=%0d exp=%b got=%b",
                            cyc, pat0011(cyc - (TOTAL_FFS - 1)), scan_out[0]);
                    end
                    mismatch_cnt = mismatch_cnt + 1;
                end
            end
        end
        if (mismatch_cnt != 0) $fatal(1, "FAIL [SDF Bypass Shift]: %0d errors", mismatch_cnt);
        $display("PASS [SDF Bypass Shift]: %0d-FF 00110011... shift verified cleanly @ 10 MHz", TOTAL_FFS);
        end

        // -----------------------------------------------------------------
        // 3. Clean March-C MBIST under SDF timing
        // -----------------------------------------------------------------
        @(negedge tck); scan_en = 1'b0;
        jtag_ir(4'b0101); jtag_dr(8, 48'h1F, dr_out);
        cyc = 0;
        while (!bist_done && cyc < 250) begin
            @(posedge tck); #2;
            cyc = cyc + 1;
        end
        if (!bist_done || bist_fail !== 1'b0) begin
            $fatal(1, "FAIL [SDF MBIST]: done=%b fail=%b", bist_done, bist_fail);
        end
        $display("PASS [SDF MBIST]: Clean March-C completed in %0d TCK cycles (fail=0)", cyc);

        // -----------------------------------------------------------------
        // 4. Clean 2:8 / 8:2 Compressed ATPG Vector + 100 MHz 2-Pulse LOC + MISR
        // -----------------------------------------------------------------
        jtag_ir(4'b0100); jtag_dr(8, 48'h0B, dr_out);   // scan_mode=1, occ_loc_en=1, rst_mask_en=1
        jtag_ir(4'b0111); jtag_dr(16, 48'h0007, dr_out); // misr_clr=1
        jtag_ir(4'b0111); jtag_dr(16, 48'h0003, dr_out); // comp_en=1, misr_en=1

        @(negedge tck); scan_en = 1'b1;
        repeat (5) @(posedge tck);
        for (cyc = 0; cyc < MAX_CH_LEN + 4; cyc = cyc + 1) begin
            @(negedge tck);
            scan_in = (cyc[1] ^ cyc[0]) ? 2'b10 : 2'b01;
            @(posedge tck);
        end
        @(negedge tck); scan_en = 1'b0;
        repeat (5) @(posedge tck);

        @(negedge tck); scan_en = 1'b1;
        x_cnt = 0;
        @(negedge tck);
        for (cyc = 0; cyc < MAX_CH_LEN; cyc = cyc + 1) begin
            scan_in = 2'b00;
            @(posedge tck);
            @(negedge tck);
            if (scan_out[0] === 1'bx || scan_out[1] === 1'bx) x_cnt = x_cnt + 1;
        end
        golden_misr = dut.misr_sig;
        if (x_cnt != 0 || (^golden_misr === 1'bx) || golden_misr == 16'h0000) begin
            $fatal(1, "FAIL [SDF Compressed LOC]: x_cnt=%0d misr=%h", x_cnt, golden_misr);
        end
        $display("PASS [SDF Compressed LOC]: 2:8 decomp + 100 MHz LOC capture clean (MISR=0x%04h)", golden_misr);
        if (quick_corner) begin
            $display("PASS [Phase 5 Corner SDF Smoke]: FUNC(Fib+Cache), MBIST & Compressed LOC verified (%s)", sdf_file);
            $finish;
        end

        // -----------------------------------------------------------------
        // 5. DBG-01: Async Reset Leak Corrupting Scan Shift -> Masked Fix
        // -----------------------------------------------------------------
        @(negedge tck); scan_en = 1'b0;
        jtag_ir(4'b0111); jtag_dr(16, 48'h0000, dr_out);
        jtag_ir(4'b0100); jtag_dr(8, 48'h01, dr_out); // BUG: rst_mask_en=0
        @(negedge tck); scan_en = 1'b1;
        repeat (5) @(posedge tck);

        for (cyc = 0; cyc < TOTAL_FFS + 10; cyc = cyc + 1) begin
            @(negedge tck); scan_in[0] = 1'b1;
            @(posedge tck);
        end
        @(negedge tck); sys_rst_n = 1'b0;
        @(posedge tck); #5;
        @(negedge tck); sys_rst_n = 1'b1;

        mismatch_cnt = 0;
        @(negedge tck);
        for (cyc = 0; cyc < 16; cyc = cyc + 1) begin
            scan_in[0] = 1'b1;
            @(posedge tck);
            @(negedge tck);
            if (scan_out[0] !== 1'b1) begin
                if (mismatch_cnt == 0 && fail_fd != 0) begin
                    $fwrite(fail_fd, "ATE_FAIL mode=BYPASS pat=0 cyc=%0d ext_pin=0 exp=1 got=%b note=DBG01_RESET_LEAK\n", cyc, scan_out[0]);
                end
                mismatch_cnt = mismatch_cnt + 1;
            end
        end
        if (mismatch_cnt == 0) $fatal(1, "FAIL [DBG-01 Buggy]: reset leak was not observed!");
        $display("PASS [DBG-01 Buggy Reproduced]: un-masked sys_rst_n corrupted %0d/16 shifted bits!", mismatch_cnt);

        @(negedge tck); scan_en = 1'b0;
        jtag_ir(4'b0100); jtag_dr(8, 48'h09, dr_out); // FIX: rst_mask_en=1
        @(negedge tck); scan_en = 1'b1;
        repeat (5) @(posedge tck);
        for (cyc = 0; cyc < TOTAL_FFS + 10; cyc = cyc + 1) begin
            @(negedge tck); scan_in[0] = 1'b1;
            @(posedge tck);
        end
        @(negedge tck); sys_rst_n = 1'b0;
        @(posedge tck); #5;
        @(negedge tck); sys_rst_n = 1'b1;

        mismatch_cnt = 0;
        @(negedge tck);
        for (cyc = 0; cyc < 64; cyc = cyc + 1) begin
            scan_in[0] = 1'b1;
            @(posedge tck);
            @(negedge tck);
            if (scan_out[0] !== 1'b1) mismatch_cnt = mismatch_cnt + 1;
        end
        if (mismatch_cnt != 0) $fatal(1, "FAIL [DBG-01 Fixed]: rst_mask_en=1 still failed (%0d errors)", mismatch_cnt);
        $display("PASS [DBG-01 Fixed]: rst_mask_en=1 protected %0d-FF chain across sys_rst_n glitch (0 errors)", TOTAL_FFS);

        // -----------------------------------------------------------------
        // 6. Targeted SA0 Failure on Chain 3 bit 42 for ATE Diagnosis
        // -----------------------------------------------------------------
        for (cyc = 0; cyc < TOTAL_FFS + 10; cyc = cyc + 1) begin
            @(negedge tck); scan_in[0] = 1'b1;
            @(posedge tck);
        end
        @(negedge tck);
        force dut.u_func_logic.`DBG03_MUX_WIRE = 1'b0;
        @(posedge tck);
        @(negedge tck);
        release dut.u_func_logic.`DBG03_MUX_WIRE;

        mismatch_cnt = 0;
        for (cyc = 1; cyc < TOTAL_FFS; cyc = cyc + 1) begin
            scan_in[0] = 1'b1;
            @(posedge tck);
            @(negedge tck);
            if (scan_out[0] !== 1'b1) begin
                if (fail_fd != 0) begin
                    $fwrite(fail_fd, "ATE_FAIL mode=BYPASS pat=1 cyc=%0d ext_pin=0 exp=1 got=%b note=SA0_CH3_BIT42\n", cyc, scan_out[0]);
                end
                $display("DIAG [SA0 Pin Log]: observed fail on bypass scan_out[0] at unload cyc=%0d", cyc);
                mismatch_cnt = mismatch_cnt + 1;
            end
        end
        if (mismatch_cnt != 1) $fatal(1, "FAIL [SA0 ATE Capture]: expected 1 fail event, got %0d", mismatch_cnt);

        // -----------------------------------------------------------------
        // 7. DBG-03: Uninitialized Chain-3 X-Flop Corrupting MISR -> X-Mask Fix
        // -----------------------------------------------------------------
        @(negedge tck); scan_en = 1'b0;
        jtag_ir(4'b0111); jtag_dr(16, 48'h0007, dr_out);
        jtag_ir(4'b0111); jtag_dr(16, 48'h0003, dr_out);
        @(negedge tck); scan_en = 1'b1;
        repeat (5) @(posedge tck);

        for (cyc = 0; cyc < MAX_CH_LEN + 4; cyc = cyc + 1) begin
            @(negedge tck); scan_in = 2'b00;
            @(posedge tck);
        end
        @(negedge tck);
        force dut.u_func_logic.`DBG03_MUX_WIRE = 1'bx;
        @(posedge tck);
        @(negedge tck);
        release dut.u_func_logic.`DBG03_MUX_WIRE;

        x_cnt = 0;
        inj_at = -1;
        for (cyc = 1; cyc < MAX_CH_LEN; cyc = cyc + 1) begin
            scan_in = 2'b00;
            @(posedge tck);
            @(negedge tck);
            if (scan_out[1] === 1'bx) begin
                if (inj_at < 0) inj_at = cyc;
                if (fail_fd != 0) begin
                    $fwrite(fail_fd, "ATE_FAIL mode=COMP82 pat=2 cyc=%0d ext_pin=1 exp=0 got=x note=DBG03_X_INJECT\n", cyc);
                end
                x_cnt = x_cnt + 1;
            end
        end
        if (x_cnt == 0 || (^dut.misr_sig !== 1'bx)) begin
            $fatal(1, "FAIL [DBG-03 Buggy]: expected X on scan_out[1] and MISR, got x_cnt=%0d misr=%h", x_cnt, dut.misr_sig);
        end
        $display("PASS [DBG-03 Buggy Reproduced]: X at ch3[42] escaped at unload cyc=%0d and poisoned MISR=0x%04h!", inj_at, dut.misr_sig);

        @(negedge tck); scan_en = 1'b0;
        jtag_ir(4'b0111); jtag_dr(16, 48'h0047, dr_out);
        jtag_ir(4'b0111); jtag_dr(16, 48'h0043, dr_out);
        @(negedge tck); scan_en = 1'b1;
        repeat (5) @(posedge tck);

        for (cyc = 0; cyc < MAX_CH_LEN + 4; cyc = cyc + 1) begin
            @(negedge tck); scan_in = 2'b00;
            @(posedge tck);
        end
        @(negedge tck);
        force dut.u_func_logic.`DBG03_MUX_WIRE = 1'bx;
        @(posedge tck);
        @(negedge tck);
        release dut.u_func_logic.`DBG03_MUX_WIRE;

        x_cnt = 0;
        for (cyc = 1; cyc < MAX_CH_LEN; cyc = cyc + 1) begin
            scan_in = 2'b00;
            @(posedge tck);
            @(negedge tck);
            if (scan_out[0] === 1'bx || scan_out[1] === 1'bx) x_cnt = x_cnt + 1;
        end
        masked_misr = dut.misr_sig;
        if (x_cnt != 0 || (^masked_misr === 1'bx)) begin
            $fatal(1, "FAIL [DBG-03 Fixed]: chain_x_mask=8'h08 leaked X (x_cnt=%0d misr=%h)", x_cnt, masked_misr);
        end
        if (fail_fd != 0) begin
            $fwrite(fail_fd, "MASK_PROBE pat=2 mask=0x08 clean=1\n");
            $fclose(fail_fd);
        end
        $display("PASS [DBG-03 Fixed]: chain_x_mask=8'h08 blocked Chain-3 X cleanly -> deterministic MISR=0x%04h!", masked_misr);
        $display("PASS [Phase 5 Full-SoC SDF GLS]: All FUNC(Fib+Cache), Bypass, MBIST, LOC+MISR, DBG-01 & DBG-03 verified!");
        $finish;
    end

endmodule
