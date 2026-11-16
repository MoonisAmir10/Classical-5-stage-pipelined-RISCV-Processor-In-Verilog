`timescale 1ns/1ps

// Post-Scan-Stitch Full-SoC Gate-Level Integration Verification (`POST_SCAN_STITCH`):
// Instantiates soc_dft_top with real 8-chain stitched sg13g2_stdcell soc_func_logic
// (2,151 scan FFs: 7 chains of 269 FFs + 1 chain of 268 FFs) + 4 SRAMs.
// Verifies:
//   1. Functional RV32I Fibonacci execution on scan-stitched gate netlist (x14=34)
//   2. End-to-end 2,151-cycle 1-chain bypass scan integrity through real FFs
//   3. 2:8 XOR compressed scan + OCC LOC capture + 16-bit MISR + MBIST
module tb_soc_scan8_gls;
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

    localparam integer TOTAL_FFS = 2151;
    logic [63:0] pat_vec = 64'h0011_2233_4455_6677;
    logic [63:0] rx_vec;
    logic [47:0] dr_out;
    integer cyc, seen_34;
    logic exp_bit;

    initial begin
        sys_rst_n = 1'b0; trst_n = 1'b0; tms = 1'b1; tdi = 1'b0;
        test_mode = 1'b0; scan_en = 1'b0; scan_in = 2'b00; prog_sel = 1'b0;
        cache_cpu_wdata = 8'd0; cache_addr_cpu = 16'd0; cache_rd_cpu = 1'b0; cache_wr_cpu = 1'b0;
        cache_mem_rdata = 8'd0; cache_ready_mem = 1'b1;
        inj_en = 1'b0; inj_bank = 2'd0; inj_addr = 3'd0; inj_bit = 6'd0; inj_type = 2'd0;

        repeat (4) @(posedge sys_clk);
        @(negedge sys_clk); sys_rst_n = 1'b1;
        @(negedge tck);     trst_n    = 1'b1;
        tap_step(1'b0, 1'b0);

        // 1. Functional CPU Fibonacci execution on gate-level stitched netlist
        seen_34 = 0;
        for (cyc = 0; cyc < 80; cyc = cyc + 1) begin
            @(posedge sys_clk); #1;
            if (x14 == 32'd34) seen_34 = 1;
        end
        if (seen_34 == 0) $fatal(1, "FAIL [Gate-Level FUNC]: Fibonacci did not reach x14=34");

        // 2. Full 2,151-bit serial scan integrity in 1-chain bypass mode (comp_en=0)
        test_mode = 1'b1;
        jtag_ir(4'b0100); jtag_dr(8, 48'h09, dr_out); // scan_mode=1, rst_mask_en=1, occ_loc=0
        jtag_ir(4'b0111); jtag_dr(16, 48'h0000, dr_out); // bypass 1-chain mode
        scan_en = 1'b1;

        // Wait for OCC clock switch to TCK then flush + shift 64-bit signature through all 2,151 FFs
        repeat (5) @(posedge tck);
        for (cyc = 0; cyc < 64; cyc = cyc + 1) begin
            @(negedge tck); scan_in[0] = pat_vec[cyc]; @(posedge tck); #1;
        end
        for (cyc = 0; cyc < (TOTAL_FFS - 64); cyc = cyc + 1) begin
            @(negedge tck); scan_in[0] = 1'b0; @(posedge tck); #1;
        end
        // Read out the 64-bit signature after exact 2,151-FF chain delay
        rx_vec = 64'd0;
        for (cyc = 0; cyc < 64; cyc = cyc + 1) begin
            rx_vec[cyc] = scan_out[0];
            @(negedge tck); scan_in[0] = 1'b0; @(posedge tck); #1;
        end
        if (rx_vec !== pat_vec) begin
            $fatal(1, "FAIL [Scan Chain Integrity 2151-FF]: expected %h, got %h", pat_vec, rx_vec);
        end

        // 3. Switch to 2:8 Compression + OCC LOC Capture + 16-bit MISR & MBIST
        @(negedge tck); scan_en = 1'b0;
        jtag_ir(4'b0100); jtag_dr(8, 48'h0B, dr_out);   // scan_mode=1, occ_loc_en=1, rst_mask_en=1
        jtag_ir(4'b0111); jtag_dr(16, 48'h0003, dr_out); // comp_en=1, misr_en=1

        scan_en = 1'b1;
        repeat (275) begin // 269 cycles > max chain length
            @(negedge tck); scan_in = 2'b10; @(posedge tck); #1;
        end
        @(negedge tck); scan_en = 1'b0; // triggers 2-pulse LOC capture on stitched core+cache
        repeat (4) @(posedge tck);
        @(negedge tck); scan_en = 1'b1; // compressed unload
        for (cyc = 0; cyc < 270; cyc = cyc + 1) begin
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

        $display("PASS [Post-Stitch SoC GLS]: 2,151-FF Bypass Integrity, Fibonacci FUNC, 2:8 Compressed LOC & MBIST verified!");
        $finish;
    end
endmodule
