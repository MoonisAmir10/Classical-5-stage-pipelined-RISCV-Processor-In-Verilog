`timescale 1ns/1ps

// Pure standard-cell controller logic for the 32-bit 2-way set-associative D-cache
// (Write-Back, Write-Allocate, LRU, 8-cycle S_INIT reset tag invalidation,
// synchronous req/ready_mem handshake, and MBIST muxing for 4x sram_sync_sp macros).
module cache_ctrl_logic #(
    parameter integer AWIDTH    = 16,
    parameter integer DWIDTH    = 32,
    parameter integer VALIDBIT  = 1,
    parameter integer DIRTYBIT  = 1,
    parameter integer USEDBIT   = 1,
    parameter integer TAGWIDTH  = 11
) (
    input  wire                        clock,
    input  wire                        reset_n,

    // Unidirectional 32-bit CPU interface (standard req / !stall_cpu)
    input  wire [AWIDTH-1:0]           addr_cpu,
    input  wire [DWIDTH-1:0]           cpu_wdata,
    input  wire [3:0]                  cpu_wstrb,
    input  wire                        rd_cpu,
    input  wire                        wr_cpu,
    output reg  [DWIDTH-1:0]           cpu_rdata,
    output reg                         stall_cpu,

    // Unidirectional 32-bit synchronous Main Memory interface
    output reg  [AWIDTH-1:0]           addr_mem,
    output reg  [DWIDTH-1:0]           mem_wdata,
    input  wire [DWIDTH-1:0]           mem_rdata,
    output reg                         rd_mem,
    output reg                         wr_mem,
    input  wire                        ready_mem,

    // Single-cycle observability pulses
    output wire                        cache_hit,
    output wire                        cache_miss,
    output wire                        cache_wb,

    // MBIST interface (controls all 4 cache SRAM banks: 0=t0, 1=t1, 2=d0, 3=d1)
    input  wire                        bist_en,
    input  wire [1:0]                  bist_bank_sel,
    input  wire [2:0]                  bist_addr,
    input  wire [31:0]                 bist_din,
    input  wire                        bist_we,
    output reg  [31:0]                 bist_dout,

    // Exposed SRAM array ports (to external sram_sync_sp macros)
    output wire [2:0]                  sram_index,
    output wire [VALIDBIT+USEDBIT+DIRTYBIT+TAGWIDTH-1:0] sram_wtag0,
    output wire [VALIDBIT+USEDBIT+DIRTYBIT+TAGWIDTH-1:0] sram_wtag1,
    output wire                        sram_wet0,
    output wire                        sram_wet1,
    output wire [DWIDTH-1:0]           sram_wdata,
    output wire                        sram_we0,
    output wire                        sram_we1,
    input  wire [VALIDBIT+USEDBIT+DIRTYBIT+TAGWIDTH-1:0] sram_rtag0,
    input  wire [VALIDBIT+USEDBIT+DIRTYBIT+TAGWIDTH-1:0] sram_rtag1,
    input  wire [DWIDTH-1:0]           sram_rdata0,
    input  wire [DWIDTH-1:0]           sram_rdata1,

    output wire                        sram_bist_en_t0,
    output wire                        sram_bist_en_t1,
    output wire                        sram_bist_en_d0,
    output wire                        sram_bist_en_d1,
    output wire [2:0]                  sram_bist_addr,
    output wire [VALIDBIT+USEDBIT+DIRTYBIT+TAGWIDTH-1:0] sram_bist_din_tag,
    output wire [31:0]                 sram_bist_din_data,
    output wire                        sram_bist_we,
    input  wire [VALIDBIT+USEDBIT+DIRTYBIT+TAGWIDTH-1:0] sram_bist_dout_t0,
    input  wire [VALIDBIT+USEDBIT+DIRTYBIT+TAGWIDTH-1:0] sram_bist_dout_t1,
    input  wire [DWIDTH-1:0]           sram_bist_dout_d0,
    input  wire [DWIDTH-1:0]           sram_bist_dout_d1
);
    localparam integer TAG_ENTRY_W = VALIDBIT + USEDBIT + DIRTYBIT + TAGWIDTH; // 14

    localparam [2:0]
        S_INIT    = 3'd0,
        S_IDLE    = 3'd1,
        S_LOOKUP  = 3'd2,
        S_WB_WAIT = 3'd3,
        S_RD_WAIT = 3'd4,
        S_REFILL  = 3'd5;

    reg [2:0]             state;
    reg [2:0]             init_idx;
    reg [AWIDTH-1:0]      req_addr;
    reg                   req_wr;
    reg [DWIDTH-1:0]      req_wdata;
    reg [3:0]             req_wstrb;
    reg                   evict_way;
    reg [TAG_ENTRY_W-1:0] other_tag;
    reg [DWIDTH-1:0]      refill_data;

    reg [2:0]             sram_addr_c;
    reg                   we0_c, we1_c, wet0_c, wet1_c;
    reg [DWIDTH-1:0]      wdata_c;
    reg [TAG_ENTRY_W-1:0] wtag0_c, wtag1_c;

    // SRAM port assignments
    assign sram_index         = sram_addr_c;
    assign sram_wtag0         = wtag0_c;
    assign sram_wtag1         = wtag1_c;
    assign sram_wet0          = wet0_c;
    assign sram_wet1          = wet1_c;
    assign sram_wdata         = wdata_c;
    assign sram_we0           = we0_c;
    assign sram_we1           = we1_c;

    assign sram_bist_en_t0    = bist_en && (bist_bank_sel == 2'd0);
    assign sram_bist_en_t1    = bist_en && (bist_bank_sel == 2'd1);
    assign sram_bist_en_d0    = bist_en && (bist_bank_sel == 2'd2);
    assign sram_bist_en_d1    = bist_en && (bist_bank_sel == 2'd3);
    assign sram_bist_addr     = bist_addr;
    assign sram_bist_din_tag  = bist_din[TAG_ENTRY_W-1:0];
    assign sram_bist_din_data = bist_din;
    assign sram_bist_we       = bist_we;

    always @(*) begin
        case (bist_bank_sel)
            2'd0: bist_dout = {{(32-TAG_ENTRY_W){1'b0}}, sram_bist_dout_t0};
            2'd1: bist_dout = {{(32-TAG_ENTRY_W){1'b0}}, sram_bist_dout_t1};
            2'd2: bist_dout = sram_bist_dout_d0;
            2'd3: bist_dout = sram_bist_dout_d1;
            default: bist_dout = 32'd0;
        endcase
    end

    // Tag decode
    wire        vw0  = sram_rtag0[13];
    wire        uw0  = sram_rtag0[12];
    wire        dw0  = sram_rtag0[11];
    wire [10:0] tag0 = sram_rtag0[10:0];

    wire        vw1  = sram_rtag1[13];
    wire        dw1  = sram_rtag1[11];
    wire [10:0] tag1 = sram_rtag1[10:0];

    wire hit_w0 = vw0 && (req_addr[15:5] == tag0);
    wire hit_w1 = vw1 && (req_addr[15:5] == tag1);
    wire hit    = hit_w0 || hit_w1;

    // Victim selection: fill invalid way first, else evict LRU way
    wire victim_way   = (!vw0) ? 1'b0 :
                        (!vw1) ? 1'b1 :
                        uw0;
    wire victim_valid = victim_way ? vw1 : vw0;
    wire victim_dirty = victim_way ? dw1 : dw0;
    wire need_wb      = victim_valid && victim_dirty;

    // Byte-masked write merge helpers
    wire [31:0] hit_line = hit_w0 ? sram_rdata0 : sram_rdata1;
    wire [31:0] merged_hit_wdata = {
        req_wstrb[3] ? req_wdata[31:24] : hit_line[31:24],
        req_wstrb[2] ? req_wdata[23:16] : hit_line[23:16],
        req_wstrb[1] ? req_wdata[15:8]  : hit_line[15:8],
        req_wstrb[0] ? req_wdata[7:0]   : hit_line[7:0]
    };

    wire [31:0] merged_refill_wdata = {
        req_wstrb[3] ? req_wdata[31:24] : refill_data[31:24],
        req_wstrb[2] ? req_wdata[23:16] : refill_data[23:16],
        req_wstrb[1] ? req_wdata[15:8]  : refill_data[15:8],
        req_wstrb[0] ? req_wdata[7:0]   : refill_data[7:0]
    };

    wire req_modifies = req_wr && (|req_wstrb);

    assign cache_hit  = (state == S_LOOKUP) && hit;
    assign cache_miss = (state == S_LOOKUP) && !hit;
    assign cache_wb   = (state == S_LOOKUP) && !hit && need_wb;

    // Combinational SRAM control, cpu_rdata, and stall_cpu
    always @(*) begin
        sram_addr_c = req_addr[4:2];
        we0_c       = 1'b0;
        we1_c       = 1'b0;
        wet0_c      = 1'b0;
        wet1_c      = 1'b0;
        wdata_c     = {DWIDTH{1'b0}};
        wtag0_c     = {TAG_ENTRY_W{1'b0}};
        wtag1_c     = {TAG_ENTRY_W{1'b0}};
        cpu_rdata   = {DWIDTH{1'b0}};
        stall_cpu   = 1'b0;

        case (state)
            S_INIT: begin
                sram_addr_c = init_idx;
                wet0_c      = 1'b1;
                wet1_c      = 1'b1;
                wtag0_c     = {TAG_ENTRY_W{1'b0}};
                wtag1_c     = {TAG_ENTRY_W{1'b0}};
                stall_cpu   = rd_cpu || wr_cpu;
            end

            S_IDLE: begin
                sram_addr_c = addr_cpu[4:2];
                stall_cpu   = rd_cpu || wr_cpu;
            end

            S_LOOKUP: begin
                sram_addr_c = req_addr[4:2];
                if (hit) begin
                    stall_cpu = 1'b0;
                    cpu_rdata = hit_line;
                    wet0_c    = 1'b1;
                    wet1_c    = 1'b1;
                    if (hit_w0) begin
                        we0_c   = req_modifies;
                        wdata_c = merged_hit_wdata;
                        wtag0_c = {1'b1, 1'b1, (req_modifies ? 1'b1 : dw0), tag0};
                        wtag1_c = {vw1,  1'b1, dw1,                         tag1};
                    end else begin
                        we1_c   = req_modifies;
                        wdata_c = merged_hit_wdata;
                        wtag0_c = {vw0,  1'b0, dw0,                         tag0};
                        wtag1_c = {1'b1, 1'b0, (req_modifies ? 1'b1 : dw1), tag1};
                    end
                end else begin
                    stall_cpu = 1'b1;
                end
            end

            S_WB_WAIT: begin
                sram_addr_c = req_addr[4:2];
                stall_cpu   = 1'b1;
            end

            S_RD_WAIT: begin
                sram_addr_c = req_addr[4:2];
                stall_cpu   = 1'b1;
            end

            S_REFILL: begin
                sram_addr_c = req_addr[4:2];
                stall_cpu   = 1'b0;
                cpu_rdata   = refill_data;
                wdata_c     = req_wr ? merged_refill_wdata : refill_data;
                we0_c       = !evict_way;
                we1_c       = evict_way;
                wet0_c      = 1'b1;
                wet1_c      = 1'b1;
                if (!evict_way) begin
                    wtag0_c = {1'b1, 1'b1, req_modifies, req_addr[15:5]};
                    wtag1_c = {other_tag[13], 1'b1, other_tag[11:0]};
                end else begin
                    wtag0_c = {other_tag[13], 1'b0, other_tag[11:0]};
                    wtag1_c = {1'b1, 1'b0, req_modifies, req_addr[15:5]};
                end
            end

            default: begin
                stall_cpu = 1'b0;
            end
        endcase
    end

    // Sequential FSM
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            state       <= S_INIT;
            init_idx    <= 3'd0;
            req_addr    <= {AWIDTH{1'b0}};
            req_wr      <= 1'b0;
            req_wdata   <= {DWIDTH{1'b0}};
            req_wstrb   <= 4'd0;
            evict_way   <= 1'b0;
            other_tag   <= {TAG_ENTRY_W{1'b0}};
            refill_data <= {DWIDTH{1'b0}};
            addr_mem    <= {AWIDTH{1'b0}};
            mem_wdata   <= {DWIDTH{1'b0}};
            rd_mem      <= 1'b0;
            wr_mem      <= 1'b0;
        end else begin
            case (state)
                S_INIT: begin
                    if (init_idx == 3'd7) begin
                        state    <= S_IDLE;
                        init_idx <= 3'd0;
                    end else begin
                        init_idx <= init_idx + 3'd1;
                    end
                end

                S_IDLE: begin
                    rd_mem <= 1'b0;
                    wr_mem <= 1'b0;
                    if (rd_cpu || wr_cpu) begin
                        req_addr  <= addr_cpu;
                        req_wr    <= wr_cpu && !rd_cpu;
                        req_wdata <= cpu_wdata;
                        req_wstrb <= cpu_wstrb;
                        state     <= S_LOOKUP;
                    end
                end

                S_LOOKUP: begin
                    if (hit) begin
                        state <= S_IDLE;
                    end else begin
                        evict_way <= victim_way;
                        other_tag <= victim_way ? sram_rtag0 : sram_rtag1;
                        if (need_wb) begin
                            addr_mem  <= {(victim_way ? tag1 : tag0), req_addr[4:2], 2'b00};
                            mem_wdata <= victim_way ? sram_rdata1 : sram_rdata0;
                            wr_mem    <= 1'b1;
                            rd_mem    <= 1'b0;
                            state     <= S_WB_WAIT;
                        end else begin
                            addr_mem  <= {req_addr[15:2], 2'b00};
                            rd_mem    <= 1'b1;
                            wr_mem    <= 1'b0;
                            state     <= S_RD_WAIT;
                        end
                    end
                end

                S_WB_WAIT: begin
                    if (ready_mem) begin
                        wr_mem   <= 1'b0;
                        rd_mem   <= 1'b1;
                        addr_mem <= {req_addr[15:2], 2'b00};
                        state    <= S_RD_WAIT;
                    end
                end

                S_RD_WAIT: begin
                    if (ready_mem) begin
                        rd_mem      <= 1'b0;
                        refill_data <= mem_rdata;
                        state       <= S_REFILL;
                    end
                end

                S_REFILL: begin
                    state <= S_IDLE;
                end

                default: begin
                    state  <= S_INIT;
                    rd_mem <= 1'b0;
                    wr_mem <= 1'b0;
                end
            endcase
        end
    end

endmodule
