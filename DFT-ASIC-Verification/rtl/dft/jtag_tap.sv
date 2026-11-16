`timescale 1ns/1ps

// IEEE 1149.1 JTAG TAP Controller with custom DFT Test Data Registers (TDRs)
// and IEEE 1500 Wrapper Serial Port (WSP) bridge.
// Reference: docs/dft_spec.md Section 3
module jtag_tap #(
    parameter logic [31:0] IDCODE_VALUE = 32'h1BAD_D071
) (
    // Physical JTAG pins
    input  logic        tck,
    input  logic        trst_n,
    input  logic        tms,
    input  logic        tdi,
    output logic        tdo,
    output logic        tdo_en,

    // TAP status & decoded IR
    output logic [3:0]  tap_state,
    output logic [3:0]  ir_reg,

    // IEEE 1500 Wrapper Serial Port (WSP) bridge
    output logic        w1500_wrst_n,
    output logic        w1500_tlr_sync,
    output logic        w1500_select_wir,
    output logic        w1500_select_wbr,
    output logic        w1500_capture,
    output logic        w1500_shift,
    output logic        w1500_update,
    output logic        w1500_mode_extest,
    output logic        w1500_mode_sample,
    output logic        w1500_mode_intest,
    output logic        w1500_wsi,
    input  logic        w1500_wso,

    // TDR_DFT_CTRL[7:0]: [0]=scan_mode, [1]=occ_loc_en, [2]=occ_bypass, [3]=rst_mask_en
    output logic [7:0]  tdr_dft_ctrl,

    // TDR_MBIST_CMD[7:0]: [0]=start, [4:1]=bank_mask, [5]=stop_on_fail, [7:6]=pattern_mode
    output logic [7:0]  tdr_mbist_cmd,
    output logic        mbist_start_toggle,

    // TDR_MBIST_STAT[47:0]: captured from sys_clk MBIST domain
    input  logic [47:0] mbist_stat_in,

    // TDR_COMP_CFG[15:0]: [0]=comp_en, [1]=misr_en, [2]=misr_clr, [10:3]=chain_x_mask
    output logic [15:0] tdr_comp_cfg
);

    // Standard 16-state IEEE 1149.1 FSM encoding
    localparam logic [3:0]
        TLR     = 4'h0,
        RTI     = 4'h1,
        SEL_DR  = 4'h2,
        CAP_DR  = 4'h3,
        SHF_DR  = 4'h4,
        EX1_DR  = 4'h5,
        PAU_DR  = 4'h6,
        EX2_DR  = 4'h7,
        UPD_DR  = 4'h8,
        SEL_IR  = 4'h9,
        CAP_IR  = 4'hA,
        SHF_IR  = 4'hB,
        EX1_IR  = 4'hC,
        PAU_IR  = 4'hD,
        EX2_IR  = 4'hE,
        UPD_IR  = 4'hF;

    // Instruction Register opcodes (docs/dft_spec.md Section 3.1)
    localparam logic [3:0]
        IR_EXTEST         = 4'b0000,
        IR_IDCODE         = 4'b0001,
        IR_SAMPLE_PRELOAD = 4'b0010,
        IR_INTEST         = 4'b0011,
        IR_DFT_CTRL       = 4'b0100,
        IR_MBIST_CMD      = 4'b0101,
        IR_MBIST_STAT     = 4'b0110,
        IR_COMP_CFG       = 4'b0111,
        IR_W1500_WIR      = 4'b1000,
        IR_BYPASS         = 4'b1111;

    logic [3:0]  state_q, next_state;
    logic [3:0]  ir_shift_q;
    logic [47:0] dr_shift_q;
    logic        bypass_q;

    assign tap_state = state_q;

    // IEEE 1149.1 Next-State Combinational Logic
    always_comb begin
        next_state = state_q;
        case (state_q)
            TLR:    next_state = tms ? TLR    : RTI;
            RTI:    next_state = tms ? SEL_DR : RTI;
            SEL_DR: next_state = tms ? SEL_IR : CAP_DR;
            CAP_DR: next_state = tms ? EX1_DR : SHF_DR;
            SHF_DR: next_state = tms ? EX1_DR : SHF_DR;
            EX1_DR: next_state = tms ? UPD_DR : PAU_DR;
            PAU_DR: next_state = tms ? EX2_DR : PAU_DR;
            EX2_DR: next_state = tms ? UPD_DR : SHF_DR;
            UPD_DR: next_state = tms ? SEL_DR : RTI;
            SEL_IR: next_state = tms ? TLR    : CAP_IR;
            CAP_IR: next_state = tms ? EX1_IR : SHF_IR;
            SHF_IR: next_state = tms ? EX1_IR : SHF_IR;
            EX1_IR: next_state = tms ? UPD_IR : PAU_IR;
            PAU_IR: next_state = tms ? EX2_IR : PAU_IR;
            EX2_IR: next_state = tms ? UPD_IR : SHF_IR;
            UPD_IR: next_state = tms ? SEL_DR : RTI;
            default: next_state = TLR;
        endcase
    end

    // Synchronous-reset indicator for downstream blocks on Test-Logic-Reset
    wire w1500_sel_any = (ir_reg == IR_W1500_WIR) ||
                         (ir_reg == IR_EXTEST) ||
                         (ir_reg == IR_SAMPLE_PRELOAD) ||
                         (ir_reg == IR_INTEST);

    assign w1500_wrst_n      = trst_n;
    assign w1500_tlr_sync    = (state_q == TLR);
    assign w1500_select_wir  = (ir_reg == IR_W1500_WIR);
    assign w1500_select_wbr  = (ir_reg == IR_EXTEST) ||
                               (ir_reg == IR_SAMPLE_PRELOAD) ||
                               (ir_reg == IR_INTEST);
    assign w1500_capture     = (state_q == CAP_DR);
    assign w1500_shift       = (state_q == SHF_DR);
    assign w1500_update      = (state_q == UPD_DR);
    assign w1500_mode_extest = (ir_reg == IR_EXTEST);
    assign w1500_mode_sample = (ir_reg == IR_SAMPLE_PRELOAD);
    assign w1500_mode_intest = (ir_reg == IR_INTEST);
    assign w1500_wsi         = tdi;

    // State, IR-Shift, and DR-Shift updated on rising edge of TCK
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            state_q    <= TLR;
            ir_shift_q <= IR_IDCODE;
            dr_shift_q <= 48'd0;
            bypass_q   <= 1'b0;
        end else begin
            state_q <= next_state;

            // Instruction shift register
            case (state_q)
                TLR:    ir_shift_q <= IR_IDCODE;
                CAP_IR: ir_shift_q <= 4'b0001; // IEEE 1149.1 mandatory LSB = 2'b01
                SHF_IR: ir_shift_q <= {tdi, ir_shift_q[3:1]};
                default: ir_shift_q <= ir_shift_q;
            endcase

            // Data shift registers
            if (state_q == CAP_DR) begin
                case (ir_reg)
                    IR_IDCODE:     dr_shift_q[31:0] <= IDCODE_VALUE;
                    IR_DFT_CTRL:   dr_shift_q[7:0]  <= tdr_dft_ctrl;
                    IR_MBIST_CMD:  dr_shift_q[7:0]  <= {tdr_mbist_cmd[7:1], 1'b0};
                    IR_MBIST_STAT: dr_shift_q[47:0] <= mbist_stat_in;
                    IR_COMP_CFG:   dr_shift_q[15:0] <= tdr_comp_cfg;
                    default:       bypass_q         <= 1'b0; // IEEE 1149.1 BYPASS capture = 0
                endcase
            end else if (state_q == SHF_DR) begin
                case (ir_reg)
                    IR_IDCODE:     dr_shift_q[31:0] <= {tdi, dr_shift_q[31:1]};
                    IR_DFT_CTRL:   dr_shift_q[7:0]  <= {tdi, dr_shift_q[7:1]};
                    IR_MBIST_CMD:  dr_shift_q[7:0]  <= {tdi, dr_shift_q[7:1]};
                    IR_MBIST_STAT: dr_shift_q[47:0] <= {tdi, dr_shift_q[47:1]};
                    IR_COMP_CFG:   dr_shift_q[15:0] <= {tdi, dr_shift_q[15:1]};
                    default:       bypass_q         <= tdi;
                endcase
            end
        end
    end

    // TDO serial mux before falling-edge launch flop
    logic raw_tdo;
    always @(*) begin
        if (state_q == SHF_IR) begin
            raw_tdo = ir_shift_q[0];
        end else if (w1500_sel_any) begin
            raw_tdo = w1500_wso;
        end else begin
            case (ir_reg)
                IR_IDCODE,
                IR_DFT_CTRL,
                IR_MBIST_CMD,
                IR_MBIST_STAT,
                IR_COMP_CFG: raw_tdo = dr_shift_q[0];
                default:     raw_tdo = bypass_q;
            endcase
        end
    end

    // IEEE 1149.1 falling-edge Update registers and TDO/TDO_EN launch
    always_ff @(negedge tck or negedge trst_n) begin
        if (!trst_n) begin
            ir_reg             <= IR_IDCODE;
            tdr_dft_ctrl       <= 8'h08;  // rst_mask_en = 1 default in test_mode
            tdr_mbist_cmd      <= 8'h1E;  // bank_mask = 4'b1111, start = 0
            mbist_start_toggle <= 1'b0;
            tdr_comp_cfg       <= 16'h0000;
            tdo                <= 1'b0;
            tdo_en             <= 1'b0;
        end else begin
            // Update TDO and output enable cleanly on falling edge of TCK
            tdo_en <= (state_q == SHF_DR) || (state_q == SHF_IR);
            if ((state_q == SHF_DR) || (state_q == SHF_IR)) begin
                tdo <= raw_tdo;
            end else begin
                tdo <= 1'b0;
            end

            // Synchronous reset to safe defaults on Test-Logic-Reset
            if (state_q == TLR) begin
                ir_reg        <= IR_IDCODE;
                tdr_dft_ctrl  <= 8'h08;
                tdr_mbist_cmd <= 8'h1E;
                tdr_comp_cfg  <= 16'h0000;
            end else begin
                if (state_q == UPD_IR) begin
                    ir_reg <= ir_shift_q;
                end
                if (state_q == UPD_DR) begin
                    case (ir_reg)
                        IR_DFT_CTRL:  tdr_dft_ctrl  <= dr_shift_q[7:0];
                        IR_MBIST_CMD: begin
                            tdr_mbist_cmd <= dr_shift_q[7:0];
                            if (dr_shift_q[0]) begin
                                mbist_start_toggle <= ~mbist_start_toggle;
                            end
                        end
                        IR_COMP_CFG:  tdr_comp_cfg  <= dr_shift_q[15:0];
                        default: ;
                    endcase
                end
            end
        end
    end

endmodule
