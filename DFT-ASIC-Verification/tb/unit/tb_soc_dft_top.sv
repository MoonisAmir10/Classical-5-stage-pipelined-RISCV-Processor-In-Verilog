`timescale 1ns/1ps

module tb_soc_dft_top;
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

    reg  [7:0]  cache_cpu_wdata;
    wire [7:0]  cache_cpu_rdata;
    wire        cache_cpu_rdata_oe;
    reg  [15:0] cache_addr_cpu;
    reg         cache_rd_cpu, cache_wr_cpu;
    wire        cache_stall_cpu;

    reg  [7:0]  cache_mem_rdata;
    wire [7:0]  cache_mem_wdata;
    wire        cache_mem_wdata_oe;
    wire [15:0] cache_addr_mem;
    wire        cache_rd_mem, cache_wr_mem;
    reg         cache_ready_mem;

    reg         inj_en;
    reg  [1:0]  inj_bank;
    reg  [2:0]  inj_addr;
    reg  [5:0]  inj_bit;
    reg  [1:0]  inj_type;

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

    initial sys_clk = 1'b0;
    always #5 sys_clk = ~sys_clk; // 100 MHz

    initial tck = 1'b0;
    always #50 tck = ~tck; // 10 MHz

    task automatic tap_step(input logic tms_val, input logic tdi_val);
        begin
            @(negedge tck);
            tms = tms_val;
            tdi = tdi_val;
            @(posedge tck);
            #1;
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

    task automatic jtag_dr(input integer len, input logic [47:0] din, output logic [47:0] dout);
        integer i;
        begin
            dout = 48'd0;
            tap_step(1'b1, 1'b0); // SEL_DR
            tap_step(1'b0, 1'b0); // CAP_DR
            tap_step(1'b0, 1'b0); // SHF_DR
            for (i = 0; i < len; i = i + 1) begin
                @(negedge tck);
                tdi = din[i];
                tms = (i == (len - 1)) ? 1'b1 : 1'b0;
                @(posedge tck);
                dout[i] = tdo;
                #1;
            end
            tap_step(1'b1, 1'b0); // UPD_DR
            tap_step(1'b0, 1'b0); // RTI
        end
    endtask

    logic [47:0] dr_out;
    integer      seen_34;
    integer      cyc;

    initial begin
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

        repeat (3) @(posedge sys_clk);
        @(negedge sys_clk); sys_rst_n = 1'b1;
        @(negedge tck);     trst_n    = 1'b1;
        tap_step(1'b0, 1'b0); // TLR -> RTI

        // 1. Functional Fibonacci execution through integrated soc_dft_top
        seen_34 = 0;
        for (cyc = 0; cyc < 80; cyc = cyc + 1) begin
            @(posedge sys_clk); #1;
            if (x14 == 32'd34) seen_34 = 1;
        end
        if (seen_34 == 0) begin
            $display("FAIL [SoC FUNC]: RV32I Fibonacci did not reach x14=34");
            $fatal(1, "Assertion failed");
        end

        // 2. JTAG IDCODE verification
        jtag_dr(32, 48'd0, dr_out);
        if (dr_out[31:0] !== 32'h1BAD_D071) begin
            $display("FAIL [SoC IDCODE]: got %h", dr_out[31:0]);
            $fatal(1, "Assertion failed");
        end

        // 3. Clean MBIST across all 4 banks triggered via JTAG MBIST_CMD (8'h1F)
        test_mode = 1'b1;
        jtag_ir(4'b0101); // MBIST_CMD
        jtag_dr(8, 48'h1F, dr_out);
        cyc = 0;
        while (!bist_done && cyc < 200) begin
            @(posedge tck); #1;
            cyc = cyc + 1;
        end
        if (!bist_done || bist_fail !== 1'b0) begin
            $display("FAIL [SoC Clean MBIST]: done=%b fail=%b", bist_done, bist_fail);
            $fatal(1, "Assertion failed");
        end
        jtag_ir(4'b0110); // MBIST_STAT
        jtag_dr(48, 48'd0, dr_out);
        if (dr_out[0] !== 1'b1 || dr_out[1] !== 1'b0) begin
            $display("FAIL [SoC MBIST_STAT clean]: %h", dr_out);
            $fatal(1, "Assertion failed");
        end

        // 4. Fault-Injected MBIST via JTAG (Bank 2 d0, Addr 4, Bit 19 SA0)
        inj_en   = 1'b1;
        inj_bank = 2'd2;
        inj_addr = 3'd4;
        inj_bit  = 6'd19;
        inj_type = 2'b01;
        jtag_ir(4'b0101); // MBIST_CMD
        jtag_dr(8, 48'h3F, dr_out); // stop_on_fail=1, start=1, all banks
        cyc = 0;
        while (!bist_done && cyc < 200) begin
            @(posedge tck); #1;
            cyc = cyc + 1;
        end
        jtag_ir(4'b0110); // MBIST_STAT
        jtag_dr(48, 48'd0, dr_out);
        if (dr_out[1] !== 1'b1 || dr_out[3:2] !== 2'd2 ||
            dr_out[6:4] !== 3'd4 || dr_out[39:8] !== 32'h0008_0000) begin
            $display("FAIL [SoC MBIST fault diag]: fail=%b bank=%0d addr=%0d mask=%h",
                     dr_out[1], dr_out[3:2], dr_out[6:4], dr_out[39:8]);
            $fatal(1, "Assertion failed");
        end
        inj_en = 1'b0;

        // 5. JTAG Compressed Scan + OCC LOC Capture + Reset Mask check
        jtag_ir(4'b0100); // DFT_CTRL: scan_mode=1, occ_loc_en=1, rst_mask_en=1 -> 8'h0B
        jtag_dr(8, 48'h0B, dr_out);
        jtag_ir(4'b0111); // COMP_CFG: comp_en=1, misr_en=1 -> 16'h0003
        jtag_dr(16, 48'h0003, dr_out);

        scan_en = 1'b1;
        for (cyc = 0; cyc < 10; cyc = cyc + 1) begin
            @(negedge tck);
            scan_in = cyc[1:0];
            if (cyc == 4) sys_rst_n = 1'b0; // attempt reset leak (must be masked!)
            if (cyc == 6) sys_rst_n = 1'b1;
            @(posedge tck); #1;
        end
        @(negedge tck); scan_en = 1'b0; // LOC 2-pulse capture
        repeat (3) @(posedge tck);
        @(negedge tck); scan_en = 1'b1; // Unload
        for (cyc = 0; cyc < 8; cyc = cyc + 1) begin
            @(negedge tck); scan_in = 2'b01;
            @(posedge tck); #1;
            if (scan_out[0] === 1'bx || scan_out[1] === 1'bx) begin
                $display("FAIL [SoC Scan Comp]: X on scan_out=%b", scan_out);
                $fatal(1, "Assertion failed");
            end
        end

        $display("PASS [SoC DFT Top]: FUNC Fibonacci, JTAG IDCODE, MBIST Clean+Diag, Scan Comp, OCC LOC & Reset Mask verified");
        $finish;
    end
endmodule
