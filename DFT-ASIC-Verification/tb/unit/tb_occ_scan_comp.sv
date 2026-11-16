`timescale 1ns/1ps

module tb_occ_scan_comp;
    // OCC instance signals
    reg        sys_clk;
    reg        sys_rst_n;
    reg        tck;
    reg        trst_n;
    reg        test_mode;
    reg        scan_en;
    reg        mbist_active;
    reg        occ_loc_en;
    reg        occ_bypass;
    reg        rst_mask_en;
    wire       occ_clk;
    wire       dft_rst_n;

    occ_clk_ctrl u_occ (
        .sys_clk      (sys_clk),
        .sys_rst_n    (sys_rst_n),
        .tck          (tck),
        .trst_n       (trst_n),
        .test_mode    (test_mode),
        .scan_en      (scan_en),
        .mbist_active (mbist_active),
        .occ_loc_en   (occ_loc_en),
        .occ_bypass   (occ_bypass),
        .rst_mask_en  (rst_mask_en),
        .occ_clk      (occ_clk),
        .dft_rst_n    (dft_rst_n)
    );

    // Scan Compression & X-Masking instance
    reg        comp_clk;
    reg        comp_rst_n;
    reg        comp_scan_en;
    reg        comp_en;
    reg        misr_en;
    reg        misr_clr;
    reg  [7:0] chain_x_mask;
    reg  [1:0] ext_scan_in;
    wire [1:0] ext_scan_out;
    wire [7:0] chain_scan_in;
    wire [7:0] chain_scan_out;
    wire [15:0] misr_sig;

    // 8 x 8-bit surrogate scan chains + intentional X injection on chain 3
    reg  [7:0] chain_q [0:7];
    reg        inject_x_ch3;

    genvar k;
    generate
        for (k = 0; k < 8; k = k + 1) begin : g_chains
            always @(posedge comp_clk or negedge comp_rst_n) begin
                if (!comp_rst_n) begin
                    chain_q[k] <= 8'd0;
                end else if (comp_scan_en) begin
                    chain_q[k] <= {chain_scan_in[k], chain_q[k][7:1]};
                end else begin
                    chain_q[k] <= 8'hA0 ^ k[7:0]; // deterministic capture word
                end
            end
        end
    endgenerate

    assign chain_scan_out[0] = chain_q[0][0];
    assign chain_scan_out[1] = chain_q[1][0];
    assign chain_scan_out[2] = chain_q[2][0];
    assign chain_scan_out[3] = inject_x_ch3 ? 1'bx : chain_q[3][0];
    assign chain_scan_out[4] = chain_q[4][0];
    assign chain_scan_out[5] = chain_q[5][0];
    assign chain_scan_out[6] = chain_q[6][0];
    assign chain_scan_out[7] = chain_q[7][0];

    scan_comp_wrap u_comp (
        .clk            (comp_clk),
        .rst_n          (comp_rst_n),
        .scan_en        (comp_scan_en),
        .comp_en        (comp_en),
        .misr_en        (misr_en),
        .misr_clr       (misr_clr),
        .chain_x_mask   (chain_x_mask),
        .ext_scan_in    (ext_scan_in),
        .ext_scan_out   (ext_scan_out),
        .chain_scan_in  (chain_scan_in),
        .chain_scan_out (chain_scan_out),
        .misr_sig       (misr_sig)
    );

    initial sys_clk = 1'b0;
    always #5 sys_clk = ~sys_clk; // 100 MHz

    initial tck = 1'b0;
    always #50 tck = ~tck; // 10 MHz

    initial comp_clk = 1'b0;
    always #5 comp_clk = ~comp_clk;

    // Count occ_clk rising edges during LOC capture window
    reg     counting_loc;
    integer loc_edges;
    always @(posedge occ_clk) begin
        if (counting_loc)
            loc_edges <= loc_edges + 1;
    end

    // Glitch detector: check minimum pulse width on occ_clk transitions
    time last_occ_edge;
    reg  check_glitch;
    always @(occ_clk) begin
        if (check_glitch && ($time - last_occ_edge > 0) && ($time - last_occ_edge < 4)) begin
            $display("FAIL [OCC Glitch]: short pulse of %0t ns detected at %0t", $time - last_occ_edge, $time);
            $fatal(1, "Assertion failed");
        end
        last_occ_edge = $time;
    end

    reg [63:0] bypass_rx;
    reg [15:0] golden_sig;
    integer    i;

    initial begin
        last_occ_edge = 0;
        check_glitch  = 1'b0;
        counting_loc  = 1'b0;
        loc_edges     = 0;

        sys_rst_n    = 1'b0;
        trst_n       = 1'b0;
        test_mode    = 1'b0;
        scan_en      = 1'b0;
        mbist_active = 1'b0;
        occ_loc_en   = 1'b0;
        occ_bypass   = 1'b0;
        rst_mask_en  = 1'b1;

        comp_rst_n   = 1'b0;
        comp_scan_en = 1'b0;
        comp_en      = 1'b0;
        misr_en      = 1'b0;
        misr_clr     = 1'b0;
        chain_x_mask = 8'h00;
        ext_scan_in  = 2'b00;
        inject_x_ch3 = 1'b0;

        repeat (3) @(posedge sys_clk);
        @(negedge sys_clk);
        sys_rst_n  = 1'b1;
        trst_n     = 1'b1;
        comp_rst_n = 1'b1;
        check_glitch = 1'b1;

        // 1. OCC Reset-Masking & Shift Switch -> LOC 2-Pulse Capture
        test_mode   = 1'b1;
        scan_en     = 1'b1;
        occ_loc_en  = 1'b1;
        repeat (5) @(posedge tck);
        @(negedge tck);
        sys_rst_n = 1'b0;
        #20;
        if (dft_rst_n !== 1'b1) begin
            $display("FAIL [OCC Reset Mask]: dft_rst_n=%b while sys_rst_n=0 in test_mode", dft_rst_n);
            $fatal(1, "Assertion failed");
        end
        sys_rst_n = 1'b1;

        // Drop scan_en for LOC capture window (expect EXACTLY 2 fast sys_clk pulses)
        @(negedge tck);
        scan_en      = 1'b0;
        #1;
        loc_edges    = 0;
        counting_loc = 1'b1;
        repeat (4) @(posedge tck); // wait 400ns (plenty of sys_clk cycles)
        counting_loc = 1'b0;
        if (loc_edges !== 2) begin
            $display("FAIL [OCC LOC]: expected 2 capture pulses, counted %0d", loc_edges);
            $fatal(1, "Assertion failed");
        end

        // Check return from LOC to TCK shift + occ_bypass check
        @(negedge tck);
        scan_en = 1'b1;
        repeat (4) @(posedge tck);
        check_glitch = 1'b0; // disable glitch monitor across static bypass config toggle
        @(negedge tck);
        occ_bypass = 1'b1;
        #1; check_glitch = 1'b1;
        repeat (2) @(posedge tck);
        check_glitch = 1'b0;
        @(negedge tck);
        occ_bypass = 1'b0;
        test_mode  = 1'b0;
        scan_en    = 1'b0;

        // 2. Scan Wrap: Uncompressed 1-chain 64-bit Bypass Shift
        comp_en      = 1'b0;
        comp_scan_en = 1'b1;
        bypass_rx    = 64'd0;
        for (i = 0; i < 64; i = i + 1) begin
            @(negedge comp_clk);
            ext_scan_in[0] = (i % 3 == 0);
            @(posedge comp_clk);
            #1;
        end
        // Shift 64 bits out
        for (i = 0; i < 64; i = i + 1) begin
            bypass_rx[i] = ext_scan_out[0];
            @(negedge comp_clk);
            ext_scan_in[0] = 1'b0;
            @(posedge comp_clk);
            #1;
        end
        // Verify bit-by-bit recovery of (i % 3 == 0) pattern
        for (i = 0; i < 64; i = i + 1) begin
            if (bypass_rx[i] !== ((i % 3 == 0) ? 1'b1 : 1'b0)) begin
                $display("FAIL [1-Chain Bypass bit %0d]: expected %b got %b",
                         i, (i % 3 == 0), bypass_rx[i]);
                $fatal(1, "Bypass shift mismatch");
            end
        end

        // 3. Compressed 2:8 + 16-bit MISR + Repeatability + Chain-3 X-Masking
        comp_en = 1'b1;
        // Run capture with chain 3 masked clean (0) first to get golden signature
        chain_x_mask = 8'b0000_1000;
        @(negedge comp_clk); misr_clr = 1'b1; comp_scan_en = 1'b0;
        @(posedge comp_clk); #1;
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge comp_clk);
            misr_clr     = 1'b0;
            misr_en      = 1'b1;
            comp_scan_en = 1'b1;
            ext_scan_in  = i[1:0];
            @(posedge comp_clk); #1;
            if (ext_scan_out[0] === 1'bx || ext_scan_out[1] === 1'bx) begin
                $fatal(1, "FAIL [Comp Golden X]");
            end
        end
        golden_sig = misr_sig;
        if (golden_sig == 16'd0) begin
            $fatal(1, "FAIL [MISR]: expected non-zero compacted signature");
        end

        // Re-run SAME sequence with chain 3 FORCED to 1'bx while masked (chain_x_mask[3]=1)
        inject_x_ch3 = 1'b1;
`ifndef VERILATOR
        // Verify unmasked X DOES corrupt odd compactor output (non-vacuous check)
        chain_x_mask = 8'h00;
        #1;
        if (ext_scan_out[1] !== 1'bx) begin
            $fatal(1, "FAIL [Non-vacuous X]: expected X on ext_scan_out[1] when unmasked");
        end
        chain_x_mask = 8'b0000_1000;
`endif
        @(negedge comp_clk); misr_clr = 1'b1; comp_scan_en = 1'b0;
        @(posedge comp_clk); #1;
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge comp_clk);
            misr_clr     = 1'b0;
            misr_en      = 1'b1;
            comp_scan_en = 1'b1;
            ext_scan_in  = i[1:0];
            @(posedge comp_clk); #1;
            if (ext_scan_out[0] === 1'bx || ext_scan_out[1] === 1'bx) begin
                $fatal(1, "FAIL [X-Mask]: X leaked onto ext_scan_out=%b", ext_scan_out);
            end
        end
        if (misr_sig !== golden_sig) begin
            $fatal(1, "FAIL [MISR X-Mask]: expected %h, got %h", golden_sig, misr_sig);
        end

        $display("PASS [OCC & Scan Comp]: glitch-free switch, 2-pulse LOC, 64b bypass, 2:8 comp+MISR, and X-masking verified");
        $finish;
    end
endmodule
