`timescale 1ns/1ps

module tb_jtag_tap;
    reg         tck;
    reg         trst_n;
    reg         tms;
    reg         tdi;
    wire        tdo;
    wire        tdo_en;
    wire [3:0]  tap_state;
    wire [3:0]  ir_reg;

    wire        w1500_wrst_n, w1500_tlr_sync;
    wire        w1500_select_wir, w1500_select_wbr;
    wire        w1500_capture, w1500_shift, w1500_update;
    wire        w1500_mode_extest, w1500_mode_sample, w1500_mode_intest;
    wire        w1500_wsi;
    reg         w1500_wso;

    wire [7:0]  tdr_dft_ctrl;
    wire [7:0]  tdr_mbist_cmd;
    wire        mbist_start_toggle;
    reg  [47:0] mbist_stat_in;
    wire [15:0] tdr_comp_cfg;

    jtag_tap dut (
        .tck                (tck),
        .trst_n             (trst_n),
        .tms                (tms),
        .tdi                (tdi),
        .tdo                (tdo),
        .tdo_en             (tdo_en),
        .tap_state          (tap_state),
        .ir_reg             (ir_reg),
        .w1500_wrst_n       (w1500_wrst_n),
        .w1500_tlr_sync     (w1500_tlr_sync),
        .w1500_select_wir   (w1500_select_wir),
        .w1500_select_wbr   (w1500_select_wbr),
        .w1500_capture      (w1500_capture),
        .w1500_shift        (w1500_shift),
        .w1500_update       (w1500_update),
        .w1500_mode_extest  (w1500_mode_extest),
        .w1500_mode_sample  (w1500_mode_sample),
        .w1500_mode_intest  (w1500_mode_intest),
        .w1500_wsi          (w1500_wsi),
        .w1500_wso          (w1500_wso),
        .tdr_dft_ctrl       (tdr_dft_ctrl),
        .tdr_mbist_cmd      (tdr_mbist_cmd),
        .mbist_start_toggle (mbist_start_toggle),
        .mbist_stat_in      (mbist_stat_in),
        .tdr_comp_cfg       (tdr_comp_cfg)
    );

    initial tck = 1'b0;
    always #50 tck = ~tck; // 10 MHz TCK

`ifdef VERILATOR
    /* verilator lint_off SYNCASYNCNET */
    property p_tdo_en_only_shift;
        @(posedge tck) disable iff (!trst_n)
            tdo_en |-> (tap_state == 4'h4 || tap_state == 4'hB);
    endproperty
    assert property (p_tdo_en_only_shift)
        else $error("SVA failure: tdo_en asserted outside SHF_DR/SHF_IR");
    /* verilator lint_on SYNCASYNCNET */
`endif

    task automatic tap_step(input logic tms_val, input logic tdi_val);
        begin
            @(negedge tck);
            tms = tms_val;
            tdi = tdi_val;
            @(posedge tck);
            #1;
        end
    endtask

    task automatic tap_soft_reset();
        integer i;
        begin
            for (i = 0; i < 5; i = i + 1)
                tap_step(1'b1, 1'b0);
            tap_step(1'b0, 1'b0); // -> RTI
        end
    endtask

    task automatic shift_ir(input logic [3:0] opcode, output logic [3:0] cap_ir);
        integer i;
        begin
            tap_step(1'b1, 1'b0); // RTI -> SEL_DR
            tap_step(1'b1, 1'b0); // SEL_DR -> SEL_IR
            tap_step(1'b0, 1'b0); // SEL_IR -> CAP_IR
            tap_step(1'b0, 1'b0); // CAP_IR -> SHF_IR
            for (i = 0; i < 4; i = i + 1) begin
                // Update TDI/TMS on negedge, then check TDO/TDO_EN once settled
                @(negedge tck);
                tdi = opcode[i];
                tms = (i == 3) ? 1'b1 : 1'b0;
                #1;
                if (tdo_en !== 1'b1) begin
                    $display("FAIL: tdo_en not high in SHF_IR");
                    $fatal(1, "tdo_en check failed");
                end
                @(posedge tck);
                cap_ir[i] = tdo;
                #1;
            end
            tap_step(1'b1, 1'b0); // EX1_IR -> UPD_IR
            tap_step(1'b0, 1'b0); // UPD_IR -> RTI
        end
    endtask

    task automatic shift_dr(input integer len, input logic [47:0] din, output logic [47:0] dout);
        integer i;
        begin
            dout = 48'd0;
            tap_step(1'b1, 1'b0); // RTI -> SEL_DR
            tap_step(1'b0, 1'b0); // SEL_DR -> CAP_DR
            tap_step(1'b0, 1'b0); // CAP_DR -> SHF_DR
            for (i = 0; i < len; i = i + 1) begin
                @(negedge tck);
                tdi = din[i];
                tms = (i == (len - 1)) ? 1'b1 : 1'b0;
                #1;
                if (tdo_en !== 1'b1) begin
                    $display("FAIL: tdo_en not high in SHF_DR bit %0d", i);
                    $fatal(1, "tdo_en check failed");
                end
                @(posedge tck);
                dout[i] = tdo;
                #1;
            end
            tap_step(1'b1, 1'b0); // EX1_DR -> UPD_DR
            tap_step(1'b0, 1'b0); // UPD_DR -> RTI
        end
    endtask

    logic [3:0]  cap_ir;
    logic [47:0] dr_out;
    logic        prev_tgl;

    initial begin
        trst_n        = 1'b0;
        tms           = 1'b1;
        tdi           = 1'b0;
        w1500_wso     = 1'b0;
        mbist_stat_in = 48'h03_DEAD_BEEF_4B;

        repeat (2) @(posedge tck);
        @(negedge tck);
        trst_n = 1'b1;
        tap_step(1'b0, 1'b0); // TLR -> RTI

        if (ir_reg !== 4'b0001 || tdr_dft_ctrl !== 8'h08) begin
            $display("FAIL [Reset defaults]: ir=%b dft_ctrl=%h", ir_reg, tdr_dft_ctrl);
            $fatal(1, "Assertion failed");
        end

        // 1. Default IDCODE readback
        shift_dr(32, 48'd0, dr_out);
        if (dr_out[31:0] !== 32'h1BAD_D071) begin
            $display("FAIL [IDCODE]: expected 1BADD071, got %h", dr_out[31:0]);
            $fatal(1, "Assertion failed");
        end

        // 2. Write and readback TDR_DFT_CTRL (IR=4'b0100), check IR capture=4'b0001
        shift_ir(4'b0100, cap_ir);
        if (cap_ir !== 4'b0001) begin
            $display("FAIL [CAP_IR]: expected 0001, got %b", cap_ir);
            $fatal(1, "Assertion failed");
        end
        shift_dr(8, 48'h0F, dr_out);
        if (tdr_dft_ctrl !== 8'h0F) begin
            $display("FAIL [DFT_CTRL write]: got %h", tdr_dft_ctrl);
            $fatal(1, "Assertion failed");
        end
        shift_dr(8, 48'h0F, dr_out);
        if (dr_out[7:0] !== 8'h0F) begin
            $display("FAIL [DFT_CTRL readback]: got %h", dr_out[7:0]);
            $fatal(1, "Assertion failed");
        end

        // 3. MBIST_CMD start_toggle check & self-clearing bit[0]
        shift_ir(4'b0101, cap_ir);
        prev_tgl = mbist_start_toggle;
        shift_dr(8, 48'h3F, dr_out);
        if (mbist_start_toggle === prev_tgl) begin
            $display("FAIL [MBIST_CMD toggle]: toggle did not fire on bit[0]=1");
            $fatal(1, "Assertion failed");
        end
        shift_dr(8, 48'h3E, dr_out);
        if (dr_out[7:0] !== 8'h3E || mbist_start_toggle !== (~prev_tgl)) begin
            $display("FAIL [MBIST_CMD readback/no-toggle]: dr=%h", dr_out[7:0]);
            $fatal(1, "Assertion failed");
        end

        // 4. MBIST_STAT 48-bit readback
        shift_ir(4'b0110, cap_ir);
        shift_dr(48, 48'd0, dr_out);
        if (dr_out !== 48'h03_DEAD_BEEF_4B) begin
            $display("FAIL [MBIST_STAT]: expected 03DEADBEEF4B, got %h", dr_out);
            $fatal(1, "Assertion failed");
        end

        // 5. COMP_CFG 16-bit write/readback
        shift_ir(4'b0111, cap_ir);
        shift_dr(16, 48'h05AB, dr_out);
        if (tdr_comp_cfg !== 16'h05AB) begin
            $display("FAIL [COMP_CFG]: got %h", tdr_comp_cfg);
            $fatal(1, "Assertion failed");
        end

        // 6. Pause-DR, Pause-IR, and Illegal opcode -> 1-bit BYPASS verification
        shift_ir(4'b1010, cap_ir); // undefined opcode -> selects 1-bit BYPASS
        tap_step(1'b1, 1'b0); // SEL_DR
        tap_step(1'b0, 1'b0); // CAP_DR
        tap_step(1'b0, 1'b0); // SHF_DR (cap bit 0)
        // Drive pause cycle mid-shift
        @(negedge tck); tms = 1'b1; tdi = 1'b1; @(posedge tck); #1; // -> EX1_DR (shifts bit 1 in)
        if (tdo !== 1'b0) begin
            $display("FAIL [BYPASS capture]: expected 0, got %b", tdo);
            $fatal(1, "Assertion failed");
        end
        tap_step(1'b0, 1'b0); // -> PAU_DR
        if (tap_state !== 4'h6 || tdo_en !== 1'b0) begin
            $display("FAIL [PAU_DR]: state=%h tdo_en=%b", tap_state, tdo_en);
            $fatal(1, "Assertion failed");
        end
        tap_step(1'b1, 1'b0); // -> EX2_DR
        tap_step(1'b0, 1'b0); // -> SHF_DR
        @(negedge tck); tms = 1'b1; tdi = 1'b0; @(posedge tck); #1; // should read back delayed 1
        if (tdo !== 1'b1) begin
            $display("FAIL [BYPASS shift]: expected 1, got %b", tdo);
            $fatal(1, "Assertion failed");
        end
        tap_step(1'b1, 1'b0); // UPD_DR
        tap_step(1'b0, 1'b0); // RTI

        // 7. 5x TMS=1 soft-reset restores IDCODE & default TDRs
        tap_soft_reset();
        if (ir_reg !== 4'b0001 || tdr_dft_ctrl !== 8'h08) begin
            $display("FAIL [Soft-reset]: ir=%b dft_ctrl=%h", ir_reg, tdr_dft_ctrl);
            $fatal(1, "Assertion failed");
        end

        $display("PASS [JTAG TAP]: IDCODE, 16-state traversal, TDR R/W, BYPASS, Pause, and Soft-Reset verified");
        $finish;
    end
endmodule
