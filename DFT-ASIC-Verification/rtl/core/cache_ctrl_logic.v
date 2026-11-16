`timescale 1ns/1ps

// Pure standard-cell controller logic for the 2-way set-associative cache
// (separated from sram_sync_sp macros so ATPG cut and multi-chain scan stitching
// operate cleanly without blackbox boundary corruption).
module cache_ctrl_logic #(
    parameter integer AWIDTH    = 16,
    parameter integer DWIDTH    = 8,
    parameter integer BLOCKSIZE = 4,
    parameter integer VALIDBIT  = 1,
    parameter integer DIRTYBIT  = 1,
    parameter integer USEDBIT   = 1,
    parameter integer TAGWIDTH  = 11
) (
    input  wire                        clock,
    input  wire                        reset_n,

    // Unidirectional CPU interface
    input  wire [DWIDTH-1:0]           cpu_wdata,
    output wire [DWIDTH-1:0]           cpu_rdata,
    output wire                        cpu_rdata_oe,
    input  wire [AWIDTH-1:0]           addr_cpu,
    input  wire                        rd_cpu,
    input  wire                        wr_cpu,
    output reg                         stall_cpu,

    // Unidirectional Main Memory interface
    input  wire [DWIDTH-1:0]           mem_rdata,
    output wire [DWIDTH-1:0]           mem_wdata,
    output wire                        mem_wdata_oe,
    output reg  [AWIDTH-1:0]           addr_mem,
    output reg                         rd_mem,
    output reg                         wr_mem,
    input  wire                        ready_mem,

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
    output wire [DWIDTH*BLOCKSIZE-1:0] sram_wdata,
    output wire                        sram_we0,
    output wire                        sram_we1,
    input  wire [VALIDBIT+USEDBIT+DIRTYBIT+TAGWIDTH-1:0] sram_rtag0,
    input  wire [VALIDBIT+USEDBIT+DIRTYBIT+TAGWIDTH-1:0] sram_rtag1,
    input  wire [DWIDTH*BLOCKSIZE-1:0] sram_rdata0,
    input  wire [DWIDTH*BLOCKSIZE-1:0] sram_rdata1,

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
    input  wire [DWIDTH*BLOCKSIZE-1:0] sram_bist_dout_d0,
    input  wire [DWIDTH*BLOCKSIZE-1:0] sram_bist_dout_d1
);
    localparam integer TAG_ENTRY_W = VALIDBIT + USEDBIT + DIRTYBIT + TAGWIDTH; // 14
    localparam integer LINE_W      = DWIDTH * BLOCKSIZE;                      // 32

    localparam [2:0]
        IDLE        = 3'd0,
        READ        = 3'd1,
        WRITE       = 3'd2,
        READMM      = 3'd3,
        WAITFORMM   = 3'd4,
        UPDATEMM    = 3'd5,
        UPDATECACHE = 3'd6;

    wire [10:0] tagdata;
    wire [2:0]  index;
    wire [1:0]  bytsel;
    reg  [DWIDTH-1:0] rdata_byte;
    reg  [DWIDTH-1:0] wdata_byte;
    reg  [DWIDTH-1:0] wmem_byte;
    reg  [LINE_W-1:0] rmem_4byte;
    reg  [LINE_W-1:0] wmem_4byte;
    reg  [3:0]        count;
    reg               rdwr;
    reg               we0, we1, wet0, wet1;
    reg               update_flag;

    wire hit, hit_w0, hit_w1;
    wire valid, vw0, vw1;
    wire uw0, uw1;
    wire dirty, dw0, dw1;

    wire [TAG_ENTRY_W-1:0] rtag0 = sram_rtag0;
    wire [TAG_ENTRY_W-1:0] rtag1 = sram_rtag1;
    wire [LINE_W-1:0]      rdata0 = sram_rdata0;
    wire [LINE_W-1:0]      rdata1 = sram_rdata1;
    wire [DWIDTH-1:0]      bytew0, bytew1;

    reg  [LINE_W-1:0]      wdata;
    reg  [LINE_W-1:0]      strdata0, strdata1;
    reg  [TAG_ENTRY_W-1:0] wtag0, wtag1;
    reg  [TAG_ENTRY_W-1:0] strtag0, strtag1;
    reg  [AWIDTH-1:0]      addrlatch;
    reg  [2:0]             state;

    assign sram_index         = index;
    assign sram_wtag0         = wtag0;
    assign sram_wtag1         = wtag1;
    assign sram_wet0          = wet0;
    assign sram_wet1          = wet1;
    assign sram_wdata         = wdata;
    assign sram_we0           = we0;
    assign sram_we1           = we1;
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

    assign tagdata = (state == IDLE) ? addr_cpu[15:5] : addrlatch[15:5];
    assign index   = (state == IDLE) ? addr_cpu[4:2]  : addrlatch[4:2];
    assign bytsel  = (state == IDLE) ? addr_cpu[1:0]  : addrlatch[1:0];

    assign vw0   = rtag0[13];
    assign vw1   = rtag1[13];
    assign valid = vw0 & vw1;

    assign uw0   = rtag0[12];
    assign uw1   = rtag1[12];

    assign dw0   = rtag0[11];
    assign dw1   = rtag1[11];
    assign dirty = dw0 | dw1;

    assign hit_w0 = vw0 & (tagdata == rtag0[10:0]);
    assign hit_w1 = vw1 & (tagdata == rtag1[10:0]);
    assign hit    = hit_w0 | hit_w1;

    assign bytew0 = (bytsel == 2'd0) ? rdata0[7:0]   :
                    (bytsel == 2'd1) ? rdata0[15:8]  :
                    (bytsel == 2'd2) ? rdata0[23:16] : rdata0[31:24];
    assign bytew1 = (bytsel == 2'd0) ? rdata1[7:0]   :
                    (bytsel == 2'd1) ? rdata1[15:8]  :
                    (bytsel == 2'd2) ? rdata1[23:16] : rdata1[31:24];

    assign cpu_rdata    = rdata_byte;
    assign cpu_rdata_oe = !wr_cpu;
    assign mem_wdata    = wmem_byte;
    assign mem_wdata_oe = wr_mem;

    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            addrlatch   <= {AWIDTH{1'b0}};
            addr_mem    <= {AWIDTH{1'b0}};
            rd_mem      <= 1'b0;
            wr_mem      <= 1'b0;
            stall_cpu   <= 1'b0;
            state       <= IDLE;
            rdata_byte  <= {DWIDTH{1'b0}};
            wdata_byte  <= {DWIDTH{1'b0}};
            wmem_byte   <= {DWIDTH{1'b0}};
            rmem_4byte  <= {LINE_W{1'b0}};
            wmem_4byte  <= {LINE_W{1'b0}};
            wdata       <= {LINE_W{1'b0}};
            wtag0       <= {TAG_ENTRY_W{1'b0}};
            wtag1       <= {TAG_ENTRY_W{1'b0}};
            we0         <= 1'b0;
            we1         <= 1'b0;
            wet0        <= 1'b0;
            wet1        <= 1'b0;
            rdwr        <= 1'b1;
            strdata0    <= {LINE_W{1'b0}};
            strdata1    <= {LINE_W{1'b0}};
            strtag0     <= {TAG_ENTRY_W{1'b0}};
            strtag1     <= {TAG_ENTRY_W{1'b0}};
            count       <= 4'd0;
            update_flag <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    addrlatch   <= addr_cpu;
                    we0         <= 1'b0;
                    we1         <= 1'b0;
                    wet0        <= 1'b0;
                    wet1        <= 1'b0;
                    stall_cpu   <= 1'b0;
                    rd_mem      <= 1'b0;
                    wr_mem      <= 1'b0;
                    wmem_byte   <= {DWIDTH{1'b0}};
                    rmem_4byte  <= {LINE_W{1'b0}};
                    wdata       <= {LINE_W{1'b0}};
                    wtag0       <= {TAG_ENTRY_W{1'b0}};
                    wtag1       <= {TAG_ENTRY_W{1'b0}};
                    update_flag <= 1'b0;
                    count       <= 4'd0;

                    if (rd_cpu) begin
                        state <= READ;
                        rdwr  <= 1'b1;
                    end else if (wr_cpu) begin
                        state      <= WRITE;
                        wdata_byte <= cpu_wdata;
                        rdwr       <= 1'b0;
                    end
                end

                READ: begin
                    we0 <= 1'b0;
                    we1 <= 1'b0;
                    if (!hit) begin
                        strtag0   <= rtag0;
                        strtag1   <= rtag1;
                        strdata0  <= rdata0;
                        strdata1  <= rdata1;
                        stall_cpu <= 1'b1;
                        wet0      <= 1'b0;
                        wet1      <= 1'b0;
                        if (ready_mem) begin
                            if (valid & dirty)
                                state <= UPDATEMM;
                            else
                                state <= READMM;
                        end
                    end else begin
                        state     <= IDLE;
                        wet0      <= 1'b1;
                        wet1      <= 1'b1;
                        stall_cpu <= 1'b0;
                        if (hit_w0) begin
                            rdata_byte <= bytew0;
                            wtag0      <= uw0 ? rtag0 : {rtag0[13], 1'b1, rtag0[11:0]};
                            wtag1      <= uw1 ? rtag1 : {rtag1[13], 1'b1, rtag1[11:0]};
                        end else begin
                            rdata_byte <= bytew1;
                            wtag1      <= uw1 ? {rtag1[13], 1'b0, rtag1[11:0]} : rtag1;
                            wtag0      <= uw0 ? {rtag0[13], 1'b0, rtag0[11:0]} : rtag0;
                        end
                    end
                end

                WRITE: begin
                    if (!hit) begin
                        strtag0   <= rtag0;
                        strtag1   <= rtag1;
                        strdata0  <= rdata0;
                        strdata1  <= rdata1;
                        stall_cpu <= 1'b1;
                        if (ready_mem) begin
                            if (valid & dirty)
                                state <= UPDATEMM;
                            else
                                state <= READMM;
                        end
                    end else begin
                        state     <= IDLE;
                        wet0      <= 1'b1;
                        wet1      <= 1'b1;
                        stall_cpu <= 1'b0;
                        if (hit_w0) begin
                            we0 <= 1'b1;
                            case (bytsel)
                                2'd0: wdata <= {rdata0[31:8],  wdata_byte};
                                2'd1: wdata <= {rdata0[31:16], wdata_byte, rdata0[7:0]};
                                2'd2: wdata <= {rdata0[31:24], wdata_byte, rdata0[15:0]};
                                2'd3: wdata <= {wdata_byte,    rdata0[23:0]};
                            endcase
                            wtag0 <= uw0 ? {rtag0[13:12], 1'b1, rtag0[10:0]} : {rtag0[13], 1'b1, 1'b1, rtag0[10:0]};
                            wtag1 <= uw1 ? rtag1 : {rtag1[13], 1'b1, rtag1[11:0]};
                        end else begin
                            we1 <= 1'b1;
                            case (bytsel)
                                2'd0: wdata <= {rdata1[31:8],  wdata_byte};
                                2'd1: wdata <= {rdata1[31:16], wdata_byte, rdata1[7:0]};
                                2'd2: wdata <= {rdata1[31:24], wdata_byte, rdata1[15:0]};
                                2'd3: wdata <= {wdata_byte,    rdata1[23:0]};
                            endcase
                            wtag1 <= uw1 ? {rtag1[13], 1'b0, 1'b1, rtag1[10:0]} : {rtag1[13:12], 1'b1, rtag1[10:0]};
                            wtag0 <= uw0 ? {rtag0[13], 1'b0, rtag0[11:0]} : rtag0;
                        end
                    end
                end

                READMM: begin
                    addr_mem    <= {addrlatch[15:2], 2'd0};
                    update_flag <= 1'b0;
                    if (ready_mem) begin
                        rd_mem <= 1'b1;
                        state  <= WAITFORMM;
                    end else begin
                        rd_mem <= 1'b0;
                    end
                end

                WAITFORMM: begin
                    if (ready_mem) begin
                        state  <= update_flag ? READMM : UPDATECACHE;
                        rd_mem <= 1'b0;
                        wr_mem <= 1'b0;
                    end else if (wr_mem) begin
                        wmem_byte  <= wmem_4byte[7:0];
                        wmem_4byte <= {8'd0, wmem_4byte[31:8]};
                    end
                end

                UPDATEMM: begin
                    update_flag <= 1'b1;
                    if (uw0) begin
                        addr_mem   <= {strtag1[10:0], addrlatch[4:2], 2'd0};
                        wmem_4byte <= strdata1;
                    end else begin
                        addr_mem   <= {strtag0[10:0], addrlatch[4:2], 2'd0};
                        wmem_4byte <= strdata0;
                    end
                    if (ready_mem) begin
                        wr_mem <= 1'b1;
                        state  <= WAITFORMM;
                    end else begin
                        wr_mem <= 1'b0;
                    end
                end

                UPDATECACHE: begin
                    update_flag <= 1'b0;
                    if (count != 4'b1111) begin
                        rmem_4byte <= {mem_rdata, rmem_4byte[31:8]};
                        count      <= {1'b1, count[3:1]};
                    end else begin
                        wdata <= rmem_4byte;
                        state <= IDLE;
                        if (uw0) begin
                            wtag1 <= {1'b1, 1'b0, 1'b0, addrlatch[15:5]};
                            wtag0 <= {strtag0[13], 1'b0, strtag0[11:0]};
                            we1   <= 1'b1;
                            we0   <= 1'b0;
                            wet0  <= 1'b1;
                            wet1  <= 1'b1;
                        end else begin
                            wtag0 <= {1'b1, 1'b1, 1'b0, addrlatch[15:5]};
                            wtag1 <= {strtag1[13], 1'b1, strtag1[11:0]};
                            we0   <= 1'b1;
                            we1   <= 1'b0;
                            wet0  <= 1'b1;
                            wet1  <= 1'b1;
                        end
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
