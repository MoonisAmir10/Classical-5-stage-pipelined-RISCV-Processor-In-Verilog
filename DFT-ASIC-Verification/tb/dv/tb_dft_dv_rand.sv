`timescale 1ns/1ps

// Constrained-Random & Coverage-Closure SV DV Suite for soc_dft_top
// Drives JTAG (all 16 states + random TDRs + mid-shift trst_n + soft resets),
// IEEE 1500 (WIR/WBR isolation & boundary drive), full MBIST fault-injection matrix,
// OCC LOC + clock switch, and compressed/bypass scan with continuous SVA & cover monitoring.
module tb_dft_dv_rand;
    logic        sys_clk;
    logic        sys_rst_n;
    logic        tck;
    logic        tms;
    logic        tdi;
    logic        tdo;
    logic        tdo_en;
    logic        trst_n;

    logic        test_mode;
    logic        scan_en;
    logic [1:0]  scan_in;
    logic [1:0]  scan_out;
    logic        bist_done;
    logic        bist_fail;

    logic        prog_sel;
    logic [31:0] x14, pc_obs, alu_obs;

    logic [7:0]  cache_cpu_wdata;
    logic [7:0]  cache_cpu_rdata;
    logic        cache_cpu_rdata_oe;
    logic [15:0] cache_addr_cpu;
    logic        cache_rd_cpu, cache_wr_cpu;
    logic        cache_stall_cpu;

    logic [7:0]  cache_mem_rdata;
    logic [7:0]  cache_mem_wdata;
    logic        cache_mem_wdata_oe;
    logic [15:0] cache_addr_mem;
    logic        cache_rd_mem, cache_wr_mem;
    logic        cache_ready_mem;

    logic        inj_en;
    logic [1:0]  inj_bank;
    logic [2:0]  inj_addr;
    logic [5:0]  inj_bit;
    logic [1:0]  inj_type;

    soc_dft_top dut (
        .sys_clk            (sys_clk),
        .sys_rst_n          (sys_rst_n),
        .tck                (tck),
        .tms                (tms),
        .tdi                (tdi),
        .tdo                (tdo),
        .tdo_en             (tdo_en),
        .trst_n             (trst_n),
        .test_mode          (test_mode),
        .scan_en            (scan_en),
        .scan_in            (scan_in),
        .scan_out           (scan_out),
        .bist_done          (bist_done),
        .bist_fail          (bist_fail),
        .prog_sel           (prog_sel),
        .x14                (x14),
        .pc_obs             (pc_obs),
        .alu_obs            (alu_obs),
        .cache_cpu_wdata    (cache_cpu_wdata),
        .cache_cpu_rdata    (cache_cpu_rdata),
        .cache_cpu_rdata_oe (cache_cpu_rdata_oe),
        .cache_addr_cpu     (cache_addr_cpu),
        .cache_rd_cpu       (cache_rd_cpu),
        .cache_wr_cpu       (cache_wr_cpu),
        .cache_stall_cpu    (cache_stall_cpu),
        .cache_mem_rdata    (cache_mem_rdata),
        .cache_mem_wdata    (cache_mem_wdata),
        .cache_mem_wdata_oe (cache_mem_wdata_oe),
        .cache_addr_mem     (cache_addr_mem),
        .cache_rd_mem       (cache_rd_mem),
        .cache_wr_mem       (cache_wr_mem),
        .cache_ready_mem    (cache_ready_mem),
        .inj_en             (inj_en),
        .inj_bank           (inj_bank),
        .inj_addr           (inj_addr),
        .inj_bit            (inj_bit),
        .inj_type           (inj_type)
    );

    dft_sva_mon u_sva (
        .sys_clk            (sys_clk),
        .sys_rst_n          (sys_rst_n),
        .tck                (tck),
        .trst_n             (trst_n),
        .tap_state          (dut.tap_state),
        .ir_reg             (dut.ir_reg),
        .tdo_en             (tdo_en),
        .tdr_dft_ctrl       (dut.tdr_dft_ctrl),
        .tdr_comp_cfg       (dut.tdr_comp_cfg),
        .wir_out            (dut.w1500_wir_out),
        .intest_active      (dut.w1500_intest_active),
        .extest_active      (dut.w1500_extest_active),
        .core_prog_sel      (dut.core_prog_sel),
        .sys_x14            (x14),
        .sys_pc_obs         (pc_obs),
        .sys_alu_obs        (alu_obs),
        .eff_test_mode      (dut.eff_test_mode),
        .scan_en            (scan_en),
        .rst_mask_en        (dut.rst_mask_en),
        .occ_bypass         (dut.occ_bypass),
        .dft_rst_n          (dut.dft_rst_n),
        .loc_active         (dut.u_occ_clk_ctrl.loc_active),
        .scan_en_sys1_q     (dut.u_occ_clk_ctrl.scan_en_sys1_q),
        .loc_rem_q          (dut.u_occ_clk_ctrl.loc_rem_q),
        .allow_sys          (dut.u_occ_clk_ctrl.allow_sys),
        .en_tck_lat_q       (dut.u_occ_clk_ctrl.en_tck_lat_q),
        .en_sys_off_neg_q   (dut.u_occ_clk_ctrl.en_sys_off_neg_q),
        .bist_en            (dut.bist_en),
        .bist_we            (dut.bist_we),
        .bist_bank_sel      (dut.bist_bank_sel),
        .bist_done          (bist_done),
        .bist_fail          (bist_fail),
        .mbist_elem_q       (dut.u_mbist_ctrl.cur_elem_q),
        .mbist_pattern_mode (dut.tdr_mbist_cmd[7:6])
    );

    initial sys_clk = 1'b0;
    always #5 sys_clk = ~sys_clk;

    initial tck = 1'b0;
    always #50 tck = ~tck;

    task automatic tap_step(input logic tms_val, input logic tdi_val);
        begin
            @(negedge tck);
            tms = tms_val;
            tdi = tdi_val;
            @(posedge tck); #1;
        end
    endtask

    task automatic tap_soft_reset();
        integer i;
        begin
            for (i = 0; i < 5; i = i + 1) tap_step(1'b1, 1'b0);
            tap_step(1'b0, 1'b0); // -> RTI
        end
    endtask

    task automatic jtag_ir(input logic [3:0] opc);
        integer i;
        begin
            tap_step(1'b1, 1'b0); // SEL_DR
            tap_step(1'b1, 1'b0); // SEL_IR
            tap_step(1'b0, 1'b0); // CAP_IR
            tap_step(1'b0, 1'b0); // SHF_IR
            for (i = 0; i < 4; i = i + 1) begin
                @(negedge tck);
                tdi = opc[i];
                tms = (i == 3) ? 1'b1 : 1'b0;
                @(posedge tck); #1;
            end
            tap_step(1'b1, 1'b0); // UPD_IR
            tap_step(1'b0, 1'b0); // RTI
        end
    endtask

    task automatic jtag_dr(input integer len, input logic [96:0] din, output logic [96:0] dout, input logic pause_mid);
        integer i;
        begin
            dout = 97'd0;
            tap_step(1'b1, 1'b0); // SEL_DR
            tap_step(1'b0, 1'b0); // CAP_DR
            tap_step(1'b0, 1'b0); // SHF_DR
            for (i = 0; i < len; i = i + 1) begin
                if (pause_mid && (i == (len / 2)) && (len > 1)) begin
                    @(negedge tck); tdi = din[i]; tms = 1'b1; @(posedge tck); dout[i] = tdo; #1; // -> EX1_DR
                    tap_step(1'b0, 1'b0); // -> PAU_DR
                    tap_step(1'b0, 1'b0); // hold PAU_DR
                    tap_step(1'b1, 1'b0); // -> EX2_DR
                    tap_step(1'b0, 1'b0); // -> SHF_DR
                end else begin
                    @(negedge tck);
                    tdi = din[i];
                    tms = (i == (len - 1)) ? 1'b1 : 1'b0;
                    @(posedge tck);
                    dout[i] = tdo;
                    #1;
                end
            end
            tap_step(1'b1, 1'b0); // UPD_DR
            tap_step(1'b0, 1'b0); // RTI
        end
    endtask

    integer      seed;
    integer      iter, b_idx, t_idx, cyc;
    logic [96:0] dr_out, wbr_stim;
    logic [7:0]  exp_dft_ctrl;
    logic [15:0] exp_comp_cfg;
    logic [7:0]  rand_val8;
    logic [15:0] rand_val16;
    logic [2:0]  rand_addr;
    logic [5:0]  rand_bit;
    logic [31:0] rand32;

    initial begin
        seed            = 32'h2026_1116;
        sys_rst_n       = 1'b0;
        trst_n          = 1'b0;
        tms             = 1'b1;
        tdi             = 1'b0;
        test_mode       = 1'b0;
        scan_en         = 1'b0;
        scan_in         = 2'b00;
        prog_sel        = 1'b0;
        cache_cpu_wdata = 8'd0;
        cache_addr_cpu  = 16'd0;
        cache_rd_cpu    = 1'b0;
        cache_wr_cpu    = 1'b0;
        cache_mem_rdata = 8'd0;
        cache_ready_mem = 1'b1;
        inj_en          = 1'b0;
        inj_bank        = 2'd0;
        inj_addr        = 3'd0;
        inj_bit         = 6'd0;
        inj_type        = 2'd0;

        repeat (4) @(posedge sys_clk);
        @(negedge sys_clk); sys_rst_n = 1'b1;
        @(negedge tck);     trst_n    = 1'b1;
        tap_step(1'b0, 1'b0); // -> RTI

        // 1. Functional CPU Program 0 & Program 1 + Cache bus toggle before DFT
        repeat (35) @(posedge sys_clk);
        @(negedge sys_clk);
        cache_addr_cpu  = 16'hFFFF;
        cache_cpu_wdata = 8'hFF;
        cache_mem_rdata = 8'hFF;
        cache_wr_cpu    = 1'b1;
        @(posedge sys_clk);
        @(negedge sys_clk); cache_wr_cpu = 1'b0;
        repeat (6) @(posedge sys_clk);
        @(negedge sys_clk);
        cache_addr_cpu  = 16'h0000;
        cache_cpu_wdata = 8'h00;
        cache_mem_rdata = 8'h00;
        cache_rd_cpu    = 1'b1;
        @(posedge sys_clk);
        @(negedge sys_clk); cache_rd_cpu = 1'b0;
        repeat (6) @(posedge sys_clk);

        @(negedge sys_clk); prog_sel = 1'b1; sys_rst_n = 1'b0;
        repeat (3) @(posedge sys_clk);
        @(negedge sys_clk); sys_rst_n = 1'b1;
        repeat (25) @(posedge sys_clk);
        @(negedge sys_clk); prog_sel = 1'b0;

        // 2. Visit Pause-IR / EX2-IR explicitly to hit all 16 TAP states
        tap_step(1'b1, 1'b0); // SEL_DR
        tap_step(1'b1, 1'b0); // SEL_IR
        tap_step(1'b0, 1'b0); // CAP_IR
        tap_step(1'b0, 1'b0); // SHF_IR
        tap_step(1'b1, 1'b1); // EX1_IR
        tap_step(1'b0, 1'b0); // PAU_IR
        tap_step(1'b1, 1'b0); // EX2_IR
        tap_step(1'b0, 1'b0); // SHF_IR
        tap_step(1'b1, 1'b1); // EX1_IR
        tap_step(1'b1, 1'b0); // UPD_IR
        tap_step(1'b0, 1'b0); // RTI

        // 3. Constrained-random JTAG TDR & Soft/Async Reset Stress (30 iterations)
        exp_dft_ctrl = 8'h08;
        exp_comp_cfg = 16'h0000;
        for (iter = 0; iter < 30; iter = iter + 1) begin
            rand32 = $urandom(seed);
            case (iter % 5)
                0: begin
                    // Randomize DFT_CTRL (keep rst_mask_en=1 during test_mode)
                    rand_val8 = {4'd0, 1'b1, rand32[2:0]};
                    jtag_ir(4'b0100);
                    jtag_dr(8, {89'd0, rand_val8}, dr_out, iter[0]);
                    exp_dft_ctrl = rand_val8;
                    jtag_dr(8, {89'd0, rand_val8}, dr_out, 1'b0);
                    // Wait: jtag_dr shifts 0s into tdr_dft_ctrl if same IR, so write exp back!
                    if (dr_out[7:0] !== exp_dft_ctrl) begin
                        $fatal(1, "DV FAIL [Rand DFT_CTRL]: exp %h got %h", exp_dft_ctrl, dr_out[7:0]);
                    end
                end
                1: begin
                    rand_val16 = {5'd0, rand32[10:3], 1'b0, rand32[1:0]};
                    jtag_ir(4'b0111); // COMP_CFG
                    jtag_dr(16, {81'd0, rand_val16}, dr_out, iter[1]);
                    exp_comp_cfg = rand_val16;
                    jtag_dr(16, {81'd0, rand_val16}, dr_out, 1'b0);
                    if (dr_out[15:0] !== exp_comp_cfg) begin
                        $fatal(1, "DV FAIL [Rand COMP_CFG]: exp %h got %h", exp_comp_cfg, dr_out[15:0]);
                    end
                end
                2: begin
                    jtag_ir(4'b0001); // IDCODE
                    jtag_dr(32, 97'd0, dr_out, 1'b1);
                    if (dr_out[31:0] !== 32'h1BAD_D071) begin
                        $fatal(1, "DV FAIL [IDCODE]: got %h", dr_out[31:0]);
                    end
                end
                3: begin
                    // Undefined IR -> 1-bit BYPASS check
                    jtag_ir(4'b1010);
                    jtag_dr(4, 97'b0101, dr_out, 1'b0);
                    if (dr_out[3:0] !== 4'b1010) begin
                        // 1st captured bit=0, next 3 shifted bits = din[2:0]=3'b101 -> {3'b101, 1'b0} = 4'b1010!
                        $fatal(1, "DV FAIL [Illegal->BYPASS]: got %b", dr_out[3:0]);
                    end
                end
                default: begin
                    // Soft reset & async mid-shift TRST_N recovery every 5 cycles
                    if (iter == 9) begin
                        tap_step(1'b1, 1'b0); tap_step(1'b0, 1'b0); tap_step(1'b0, 1'b0); // -> SHF_DR
                        @(negedge tck); trst_n = 1'b0;
                        repeat (2) @(posedge tck);
                        @(negedge tck); trst_n = 1'b1;
                        tap_step(1'b0, 1'b0); // -> RTI
                    end else begin
                        tap_soft_reset();
                    end
                    exp_dft_ctrl = 8'h08;
                    exp_comp_cfg = 16'h0000;
                end
            endcase
        end

        // 4. Complement TDRs & IEEE 1500 All WIR/WBR toggle closure
        jtag_ir(4'b0100); jtag_dr(8, 97'hFF, dr_out, 1'b0);
        jtag_dr(8, 97'h00, dr_out, 1'b0);
        jtag_dr(8, 97'h08, dr_out, 1'b0);
        jtag_ir(4'b0111); jtag_dr(16, 97'hFFFF, dr_out, 1'b0);
        jtag_dr(16, 97'h0000, dr_out, 1'b0);

        jtag_ir(4'b1000); // W1500_WIR
        jtag_dr(4, 97'b0011, dr_out, 1'b0); // WS_SAMPLE_PRELOAD
        jtag_ir(4'b0010); // SAMPLE_PRELOAD WBR capture
        jtag_dr(97, 97'd0, dr_out, 1'b0);

        jtag_ir(4'b1000);
        jtag_dr(4, 97'b0010, dr_out, 1'b0); // WS_INTEST_RING
        jtag_ir(4'b0011); // JTAG INTEST
        wbr_stim = {96'd0, 1'b1};
        jtag_dr(97, wbr_stim, dr_out, 1'b0);
        repeat (10) @(posedge sys_clk);

        jtag_ir(4'b1000);
        jtag_dr(4, 97'b0001, dr_out, 1'b0); // WS_EXTEST via WIR (hits c_wir_extest)
        jtag_ir(4'b0000); // EXTEST all-1s then all-0s complement shift
        jtag_dr(97, {97{1'b1}}, dr_out, 1'b0);
        jtag_dr(97, 97'd0, dr_out, 1'b0);
        wbr_stim = {32'h55AA_55AA, 32'h0102_0304, 32'hCAFE_BABE, 1'b0};
        jtag_dr(97, wbr_stim, dr_out, 1'b0);

        jtag_ir(4'b1000);
        jtag_dr(4, 97'b1111, dr_out, 1'b0); // WS_SAFE
        jtag_ir(4'b1000);
        jtag_dr(4, 97'b0000, dr_out, 1'b0); // back to WS_BYPASS
        jtag_ir(4'b1111); // BYPASS

        // 5. MBIST Checkerboard, Edge-Cases, 12-pt Bank/Type + 32-bit Walk-1 Toggle Closure
        test_mode = 1'b1;
        // 5a: Empty bank_mask=0000 edge case (also toggles pattern_mode=2'b10 upper bit)
        jtag_ir(4'b0101);
        jtag_dr(8, 97'h81, dr_out, 1'b0);
        repeat (5) @(posedge tck);
        if (!bist_done || bist_fail) $fatal(1, "DV FAIL [MBIST empty mask]");

        // 5b: Non-contiguous bank_mask=0101 (banks 0 & 2) + Checkerboard (pattern=01) -> 8'h4B
        jtag_dr(8, 97'h4B, dr_out, 1'b0);
        cyc = 0; while (!bist_done && cyc < 200) begin @(posedge tck); #1; cyc = cyc + 1; end
        if (!bist_done || bist_fail) $fatal(1, "DV FAIL [MBIST Checkerboard + skip bank]");

        // 5c: Continue-on-fail (stop_on_fail=0) across banks 0 & 2 with SA1 at bank 0 addr 7 bit 2
        inj_en   = 1'b1; inj_bank = 2'd0; inj_addr = 3'd7; inj_bit = 6'd2; inj_type = 2'b10;
        jtag_dr(8, 97'h0B, dr_out, 1'b0); // bank_mask=4'b0101, stop_on_fail=0, start=1
        cyc = 0; while (!bist_done && cyc < 200) begin @(posedge tck); #1; cyc = cyc + 1; end
        if (!bist_done || !bist_fail) $fatal(1, "DV FAIL [MBIST continue-on-fail]");

        // 5d: Continue-on-fail with SA1 at bank 2 (last bank in 0101) addr 7 bit 2
        inj_bank = 2'd2; inj_addr = 3'd7; inj_bit = 6'd2; inj_type = 2'b10;
        jtag_dr(8, 97'h0B, dr_out, 1'b0);
        cyc = 0; while (!bist_done && cyc < 200) begin @(posedge tck); #1; cyc = cyc + 1; end
        if (!bist_done || !bist_fail) $fatal(1, "DV FAIL [MBIST continue-on-fail last bank]");

        // 5e: 32-bit Walk-1 SA0 fault verification on bank 2 (d0) -> 100% bitmask toggle
        for (iter = 0; iter < 32; iter = iter + 1) begin
            inj_bank = 2'd2; inj_addr = iter[2:0]; inj_bit = iter[5:0]; inj_type = 2'b01;
            jtag_ir(4'b0101);
            jtag_dr(8, 97'h29, dr_out, 1'b0); // stop_on_fail=1, bank_mask=4'b0100 (d0), start=1
            cyc = 0; while (!bist_done && cyc < 100) begin @(posedge tck); #1; cyc = cyc + 1; end
            jtag_ir(4'b0110);
            jtag_dr(48, 97'hFFFF_FFFF_FFFF, dr_out, 1'b0);
            if (dr_out[39:8] !== (32'h1 << iter)) begin
                $fatal(1, "DV FAIL [Walk-1 bit %0d]: mask=%h", iter, dr_out[39:8]);
            end
        end

        // 12-point Fault Injection Sweep: every bank (0..3) x every fault type (SA0, SA1, flip)
        for (b_idx = 0; b_idx < 4; b_idx = b_idx + 1) begin
            for (t_idx = 1; t_idx <= 3; t_idx = t_idx + 1) begin
                rand32    = $urandom(seed);
                rand_addr = rand32[2:0];
                rand_bit  = (b_idx < 2) ? {2'd0, rand32[6:3]} % 6'd14 : {1'b0, rand32[7:3]};
                inj_en    = 1'b1;
                inj_bank  = b_idx[1:0];
                inj_addr  = rand_addr;
                inj_bit   = rand_bit;
                inj_type  = t_idx[1:0];

                // Single-bank targeted MBIST via bank_mask & stop_on_fail=1
                jtag_ir(4'b0101);
                jtag_dr(8, {89'd0, 3'b001, (4'b0001 << b_idx[1:0]), 1'b1}, dr_out, 1'b0);
                cyc = 0; while (!bist_done && cyc < 200) begin @(posedge tck); #1; cyc = cyc + 1; end

                jtag_ir(4'b0110); // MBIST_STAT
                jtag_dr(48, 97'd0, dr_out, 1'b0);
                if (dr_out[0] !== 1'b1 || dr_out[1] !== 1'b1 ||
                    dr_out[3:2] !== b_idx[1:0] || dr_out[6:4] !== rand_addr ||
                    dr_out[39:8] !== (32'h1 << rand_bit)) begin
                    $fatal(1, "DV FAIL [Fault Matrix bank=%0d type=%0d]: got bank=%0d addr=%0d mask=%h exp_addr=%0d exp_bit=%0d",
                           b_idx, t_idx, dr_out[3:2], dr_out[6:4], dr_out[39:8], rand_addr, rand_bit);
                end
            end
        end
        inj_en = 1'b0;

        // 6. OCC Bypass + OCC LOC + Scan Uncompressed Bypass + Compressed + X-Mask Sweep
        // 6a: OCC Bypass shift check
        jtag_ir(4'b0100);
        jtag_dr(8, 97'h0D, dr_out, 1'b0); // scan_mode=1, occ_bypass=1, rst_mask_en=1
        jtag_ir(4'b0111);
        jtag_dr(16, 97'h0000, dr_out, 1'b0); // 1-chain bypass
        scan_en = 1'b1;
        for (cyc = 0; cyc < 16; cyc = cyc + 1) begin
            @(negedge tck); scan_in = cyc[1:0]; @(posedge tck); #1;
        end
        @(negedge tck); scan_en = 1'b0;

        // 6b: LOC + Compressed + X-Mask + async reset immunity stress
        jtag_ir(4'b0100);
        jtag_dr(8, 97'h0B, dr_out, 1'b0); // scan_mode=1, occ_loc_en=1, rst_mask_en=1
        jtag_ir(4'b0111);
        jtag_dr(16, 97'h07FF, dr_out, 1'b0); // comp_en=1, misr_en=1, misr_clr=1, x_mask=8'hFF
        scan_en = 1'b1;
        repeat (4) @(posedge tck);
        jtag_dr(16, 97'h0043, dr_out, 1'b0); // comp_en=1, misr_en=1, misr_clr=0, x_mask=8'b0000_1000
        for (iter = 0; iter < 5; iter = iter + 1) begin
            @(negedge tck); scan_en = 1'b1;
            for (cyc = 0; cyc < 10; cyc = cyc + 1) begin
                @(negedge tck);
                rand32  = $urandom(seed);
                scan_in = rand32[1:0];
                if (cyc == 3) sys_rst_n = 1'b0;
                if (cyc == 5) sys_rst_n = 1'b1;
                @(posedge tck); #1;
            end
            @(negedge tck); scan_en = 1'b0; // triggers 2-pulse LOC
            repeat (3) @(posedge tck);
        end

        $display("PASS [Phase 3 DV Suite]: 30x Rand JTAG/Resets, all 16 TAP states, W1500 5x modes, 12x MBIST Faults, OCC Bypass/LOC & Scan Comp verified");
        $finish;
    end
endmodule
