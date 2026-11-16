`timescale 1ns/1ps

// March-C Memory BIST Controller for cache_2wsa_dft's 4 synchronous SRAM banks:
//   Bank 0: u_tag_ram_w0 (8 x 14b)
//   Bank 1: u_tag_ram_w1 (8 x 14b)
//   Bank 2: u_data_ram_w0 (8 x 32b)
//   Bank 3: u_data_ram_w1 (8 x 32b)
// Implements 6-element (10N) March-C (pattern_mode=2'b00) and Checkerboard March (2'b01)
// with synchronous 1-cycle SRAM read latency and first-fail diagnostic snapshot.
module mbist_ctrl (
    input  logic        clk,
    input  logic        rst_n,

    // Control inputs (start_toggle is TCK->sys_clk CDC-synchronized internally)
    input  logic        start_toggle,
    input  logic        start_sync_pulse,
    input  logic [3:0]  bank_mask,
    input  logic        stop_on_fail,
    input  logic [1:0]  pattern_mode,

    // Cache SRAM MBIST bus (connected to cache_2wsa_dft)
    output logic        bist_en,
    output logic [1:0]  bist_bank_sel,
    output logic [2:0]  bist_addr,
    output logic [31:0] bist_din,
    output logic        bist_we,
    input  logic [31:0] bist_dout,

    // Status & 48-bit diagnostic register mapped to TDR_MBIST_STAT
    output logic        bist_done,
    output logic        bist_fail,
    output logic [47:0] mbist_stat
);

    localparam logic [2:0]
        ST_IDLE     = 3'd0,
        ST_STEP_SEL = 3'd1,
        ST_READ_REQ = 3'd2,
        ST_READ_CHK = 3'd3,
        ST_WRITE    = 3'd4,
        ST_DONE     = 3'd5;

    logic [2:0]  state_q;
    logic [1:0]  cur_bank_q;
    logic [2:0]  cur_elem_q;     // 0..5 March-C elements
    logic [2:0]  cur_addr_q;

    // CDC 3-FF edge detector for JTAG start_toggle
    logic        tgl_s0_q, tgl_s1_q, tgl_s2_q;
    wire         start_req = start_sync_pulse || (tgl_s1_q ^ tgl_s2_q);

    // Diagnostic capture registers
    logic [1:0]  fail_bank_q;
    logic [2:0]  fail_addr_q;
    logic [31:0] fail_bitmask_q;
    logic [2:0]  fail_elem_q;

    // Valid bit width mask per SRAM bank (Tag SRAMs = 14b, Data SRAMs = 32b)
    wire [31:0] bank_bit_mask = (cur_bank_q < 2'd2) ? 32'h0000_3FFF : 32'hFFFF_FFFF;

    // Logical '0' / '1' pattern data respecting Checkerboard mode (2'b01)
    wire [31:0] pat_base_zero = (pattern_mode == 2'b01) ?
                                (cur_addr_q[0] ? 32'hAAAA_AAAA : 32'h5555_5555) :
                                32'h0000_0000;
    wire [31:0] pat_base_one  = (pattern_mode == 2'b01) ?
                                (cur_addr_q[0] ? 32'h5555_5555 : 32'hAAAA_AAAA) :
                                32'hFFFF_FFFF;
    wire [31:0] pat_zero      = pat_base_zero & bank_bit_mask;
    wire [31:0] pat_one       = pat_base_one  & bank_bit_mask;

    // March-C element direction, expected read bit, write bit:
    //   M0: up   w0           (addr 0->7)
    //   M1: up   r0, w1       (addr 0->7)
    //   M2: up   r1, w0       (addr 0->7)
    //   M3: down r0, w1       (addr 7->0)
    //   M4: down r1, w0       (addr 7->0)
    //   M5: up   r0           (addr 0->7)
    wire elem_down     = (cur_elem_q == 3'd3) || (cur_elem_q == 3'd4);
    wire elem_has_read = (cur_elem_q != 3'd0);
    wire elem_has_wr   = (cur_elem_q != 3'd5);
    wire elem_rd_one   = (cur_elem_q == 3'd2) || (cur_elem_q == 3'd4);
    wire elem_wr_one   = (cur_elem_q == 3'd1) || (cur_elem_q == 3'd3);

    wire [31:0] exp_rd_word = elem_rd_one ? pat_one : pat_zero;
    wire [31:0] cur_wr_word = elem_wr_one ? pat_one : pat_zero;
    wire [31:0] mismatch    = (bist_dout ^ exp_rd_word) & bank_bit_mask;

    wire addr_last = elem_down ? (cur_addr_q == 3'd0) : (cur_addr_q == 3'd7);
    wire [2:0] next_addr_val = elem_down ? (cur_addr_q - 3'd1) : (cur_addr_q + 3'd1);

    // Combinational priority selection for first and next enabled bank
    logic [2:0] first_bank;
    logic [2:0] next_bank_after_cur;

    always @(*) begin
        first_bank = 3'd4;
        if (bank_mask[0])      first_bank = 3'd0;
        else if (bank_mask[1]) first_bank = 3'd1;
        else if (bank_mask[2]) first_bank = 3'd2;
        else if (bank_mask[3]) first_bank = 3'd3;

        next_bank_after_cur = 3'd4;
        if (cur_bank_q == 2'd0) begin
            if (bank_mask[1])      next_bank_after_cur = 3'd1;
            else if (bank_mask[2]) next_bank_after_cur = 3'd2;
            else if (bank_mask[3]) next_bank_after_cur = 3'd3;
        end else if (cur_bank_q == 2'd1) begin
            if (bank_mask[2])      next_bank_after_cur = 3'd2;
            else if (bank_mask[3]) next_bank_after_cur = 3'd3;
        end else if (cur_bank_q == 2'd2) begin
            if (bank_mask[3])      next_bank_after_cur = 3'd3;
        end
    end

    assign mbist_stat = {
        5'd0, fail_elem_q,
        fail_bitmask_q,
        1'b0,
        fail_addr_q,
        fail_bank_q,
        bist_fail,
        bist_done
    };

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q        <= ST_IDLE;
            cur_bank_q     <= 2'd0;
            cur_elem_q     <= 3'd0;
            cur_addr_q     <= 3'd0;
            tgl_s0_q       <= 1'b0;
            tgl_s1_q       <= 1'b0;
            tgl_s2_q       <= 1'b0;
            bist_en        <= 1'b0;
            bist_bank_sel  <= 2'd0;
            bist_addr      <= 3'd0;
            bist_din       <= 32'd0;
            bist_we        <= 1'b0;
            bist_done      <= 1'b0;
            bist_fail      <= 1'b0;
            fail_bank_q    <= 2'd0;
            fail_addr_q    <= 3'd0;
            fail_bitmask_q <= 32'd0;
            fail_elem_q    <= 3'd0;
        end else begin
            tgl_s0_q <= start_toggle;
            tgl_s1_q <= tgl_s0_q;
            tgl_s2_q <= tgl_s1_q;

            case (state_q)
                ST_IDLE,
                ST_DONE: begin
                    bist_en <= 1'b0;
                    bist_we <= 1'b0;
                    if (start_req) begin
                        bist_done      <= 1'b0;
                        bist_fail      <= 1'b0;
                        fail_bank_q    <= 2'd0;
                        fail_addr_q    <= 3'd0;
                        fail_bitmask_q <= 32'd0;
                        fail_elem_q    <= 3'd0;
                        if (first_bank == 3'd4) begin
                            bist_done <= 1'b1;
                            state_q   <= ST_DONE;
                        end else begin
                            cur_bank_q <= first_bank[1:0];
                            cur_elem_q <= 3'd0;
                            cur_addr_q <= 3'd0;
                            bist_en    <= 1'b1;
                            state_q    <= ST_STEP_SEL;
                        end
                    end
                end

                ST_STEP_SEL: begin
                    bist_en       <= 1'b1;
                    bist_bank_sel <= cur_bank_q;
                    bist_addr     <= cur_addr_q;
                    if (elem_has_read) begin
                        bist_we <= 1'b0;
                        state_q <= ST_READ_REQ;
                    end else begin
                        bist_we  <= 1'b1;
                        bist_din <= cur_wr_word;
                        state_q  <= ST_WRITE;
                    end
                end

                ST_READ_REQ: begin
                    // SRAM latches cur_addr_q on this posedge; bist_dout settles for ST_READ_CHK
                    bist_we <= 1'b0;
                    state_q <= ST_READ_CHK;
                end

                ST_READ_CHK: begin
                    if (mismatch != 32'd0 && !bist_fail) begin
                        bist_fail      <= 1'b1;
                        fail_bank_q    <= cur_bank_q;
                        fail_addr_q    <= cur_addr_q;
                        fail_bitmask_q <= mismatch;
                        fail_elem_q    <= cur_elem_q;
                    end

                    if ((mismatch != 32'd0) && stop_on_fail) begin
                        bist_en   <= 1'b0;
                        bist_we   <= 1'b0;
                        bist_done <= 1'b1;
                        state_q   <= ST_DONE;
                    end else if (elem_has_wr) begin
                        bist_addr <= cur_addr_q;
                        bist_din  <= cur_wr_word;
                        bist_we   <= 1'b1;
                        state_q   <= ST_WRITE;
                    end else if (!addr_last) begin
                        cur_addr_q <= next_addr_val;
                        bist_addr  <= next_addr_val;
                        bist_we    <= 1'b0;
                        state_q    <= ST_READ_REQ;
                    end else if (next_bank_after_cur != 3'd4) begin
                        cur_bank_q <= next_bank_after_cur[1:0];
                        cur_elem_q <= 3'd0;
                        cur_addr_q <= 3'd0;
                        bist_we    <= 1'b0;
                        state_q    <= ST_STEP_SEL;
                    end else begin
                        bist_en   <= 1'b0;
                        bist_we   <= 1'b0;
                        bist_done <= 1'b1;
                        state_q   <= ST_DONE;
                    end
                end

                ST_WRITE: begin
                    // SRAM executes write on this posedge; prepare next address or advance to next element
                    bist_we <= 1'b0;
                    if (!addr_last) begin
                        cur_addr_q <= next_addr_val;
                        bist_addr  <= next_addr_val;
                        state_q    <= elem_has_read ? ST_READ_REQ : ST_STEP_SEL;
                    end else begin
                        cur_elem_q <= cur_elem_q + 3'd1;
                        cur_addr_q <= ((cur_elem_q + 3'd1) == 3'd3 || (cur_elem_q + 3'd1) == 3'd4) ? 3'd7 : 3'd0;
                        state_q    <= ST_STEP_SEL;
                    end
                end

                default: state_q <= ST_IDLE;
            endcase
        end
    end

endmodule
