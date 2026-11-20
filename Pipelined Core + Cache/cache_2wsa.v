`timescale 1ns / 1ps

/*
============================
2-Way Set-Associative 32-bit Data Cache (Write-Back, Write-Allocate, LRU)
============================
- Geometry: 8 sets x 2 ways = 16 lines, 4 bytes (32 bits) per line (64 B total)
- Address map (16-bit byte address):
    addr[15:5] : 11-bit Tag
    addr[4:2]  :  3-bit Set Index
    addr[1:0]  :  2-bit Byte Offset within 32-bit word
- Tag SRAM entry (14 bits):
    bit 13     : Valid (V)
    bit 12     : Used / MRU (U) -- 1: Way 0 is MRU (evict Way 1), 0: Way 1 is MRU (evict Way 0)
    bit 11     : Dirty (D)
    bits 10:0  : Tag
- CPU Handshake (standard req / !stall):
    Drive addr_cpu, rd_cpu / wr_cpu, cpu_wdata, cpu_wstrb and hold while stall_cpu == 1.
    Transaction completes on the rising clock edge where (rd_cpu || wr_cpu) && !stall_cpu;
    cpu_rdata is valid before that edge on reads, and writes commit on that edge.
- Main Memory Handshake (synchronous req / ready_mem ack):
    Cache asserts rd_mem or wr_mem with word-aligned addr_mem and holds until
    ready_mem pulses high for 1 clock cycle (registered ack from main memory).
- Reset:
    Active-low async reset_n triggers an automatic 8-cycle S_INIT sweep that clears
    all Valid bits in both Tag SRAMs before serving memory requests.
*/

module cache_2wsa #(
    parameter AWIDTH     = 16,
    parameter DWIDTH     = 32,
    parameter CACHELINES = 16,
    parameter BLOCKSIZE  = 4,
    parameter NUMOFSETS  = 8,
    parameter VALIDBIT   = 1,
    parameter DIRTYBIT   = 1,
    parameter USEDBIT    = 1,
    parameter TAGWIDTH   = 11
)(
    input  wire              clock,
    input  wire              reset_n,

    // Unidirectional 32-bit CPU interface
    input  wire [AWIDTH-1:0] addr_cpu,
    input  wire [DWIDTH-1:0] cpu_wdata,
    input  wire [3:0]        cpu_wstrb,
    input  wire              rd_cpu,
    input  wire              wr_cpu,
    output reg  [DWIDTH-1:0] cpu_rdata,
    output reg               stall_cpu,

    // Unidirectional 32-bit synchronous Main Memory interface
    output reg  [AWIDTH-1:0] addr_mem,
    output reg  [DWIDTH-1:0] mem_wdata,
    input  wire [DWIDTH-1:0] mem_rdata,
    output reg               rd_mem,
    output reg               wr_mem,
    input  wire              ready_mem,

    // Single-cycle observability pulses
    output wire              cache_hit,
    output wire              cache_miss,
    output wire              cache_wb
);

localparam TAG_ENTRY_W = VALIDBIT + USEDBIT + DIRTYBIT + TAGWIDTH; // 14

// FSM States
localparam [2:0]
    S_INIT    = 3'd0,
    S_IDLE    = 3'd1,
    S_LOOKUP  = 3'd2,
    S_WB_WAIT = 3'd3,
    S_RD_WAIT = 3'd4,
    S_REFILL  = 3'd5;

reg [2:0] state;
reg [2:0] init_idx;

// Latched CPU request
reg [AWIDTH-1:0]      req_addr;
reg                   req_wr;
reg [DWIDTH-1:0]      req_wdata;
reg [3:0]             req_wstrb;

// Miss / eviction tracking
reg                   evict_way;
reg [TAG_ENTRY_W-1:0] other_tag;
reg [DWIDTH-1:0]      refill_data;

// SRAM interconnect
reg  [2:0]             sram_addr;
reg                    we0, we1, wet0, wet1;
reg  [DWIDTH-1:0]      wdata;
reg  [TAG_ENTRY_W-1:0] wtag0, wtag1;
wire [TAG_ENTRY_W-1:0] rtag0, rtag1;
wire [DWIDTH-1:0]      rdata0, rdata1;

// Tag fields
wire        vw0  = rtag0[13];
wire        uw0  = rtag0[12];
wire        dw0  = rtag0[11];
wire [10:0] tag0 = rtag0[10:0];

wire        vw1  = rtag1[13];
wire        dw1  = rtag1[11];
wire [10:0] tag1 = rtag1[10:0];

// Hit detection (valid during S_LOOKUP)
wire hit_w0 = vw0 && (req_addr[15:5] == tag0);
wire hit_w1 = vw1 && (req_addr[15:5] == tag1);
wire hit    = hit_w0 || hit_w1;

// Victim selection: fill invalid way first, else evict LRU way
// Convention: uw0 == 1 -> Way 0 is MRU (Way 1 is LRU); uw0 == 0 -> Way 1 is MRU (Way 0 is LRU)
wire victim_way   = (!vw0) ? 1'b0 :
                    (!vw1) ? 1'b1 :
                    uw0;
wire victim_valid = victim_way ? vw1 : vw0;
wire victim_dirty = victim_way ? dw1 : dw0;
wire need_wb      = victim_valid && victim_dirty;

// Byte-masked write merge helpers
wire [31:0] hit_line = hit_w0 ? rdata0 : rdata1;
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

// Observability pulses
assign cache_hit  = (state == S_LOOKUP) && hit;
assign cache_miss = (state == S_LOOKUP) && !hit;
assign cache_wb   = (state == S_LOOKUP) && !hit && need_wb;

// Combinational SRAM control, cpu_rdata, and stall_cpu
always @(*) begin
    sram_addr = req_addr[4:2];
    we0       = 1'b0;
    we1       = 1'b0;
    wet0      = 1'b0;
    wet1      = 1'b0;
    wdata     = 32'd0;
    wtag0     = {TAG_ENTRY_W{1'b0}};
    wtag1     = {TAG_ENTRY_W{1'b0}};
    cpu_rdata = 32'd0;
    stall_cpu = 1'b0;

    case (state)
        S_INIT: begin
            sram_addr = init_idx;
            wet0      = 1'b1;
            wet1      = 1'b1;
            wtag0     = {TAG_ENTRY_W{1'b0}};
            wtag1     = {TAG_ENTRY_W{1'b0}};
            stall_cpu = rd_cpu || wr_cpu;
        end

        S_IDLE: begin
            sram_addr = addr_cpu[4:2];
            stall_cpu = rd_cpu || wr_cpu;
        end

        S_LOOKUP: begin
            sram_addr = req_addr[4:2];
            if (hit) begin
                stall_cpu = 1'b0;
                cpu_rdata = hit_line;
                wet0      = 1'b1;
                wet1      = 1'b1;
                if (hit_w0) begin
                    we0   = req_modifies;
                    wdata = merged_hit_wdata;
                    wtag0 = {1'b1, 1'b1, (req_modifies ? 1'b1 : dw0), tag0};
                    wtag1 = {vw1,  1'b1, dw1,                         tag1};
                end else begin
                    we1   = req_modifies;
                    wdata = merged_hit_wdata;
                    wtag0 = {vw0,  1'b0, dw0,                         tag0};
                    wtag1 = {1'b1, 1'b0, (req_modifies ? 1'b1 : dw1), tag1};
                end
            end else begin
                stall_cpu = 1'b1;
            end
        end

        S_WB_WAIT: begin
            sram_addr = req_addr[4:2];
            stall_cpu = 1'b1;
        end

        S_RD_WAIT: begin
            sram_addr = req_addr[4:2];
            stall_cpu = 1'b1;
        end

        S_REFILL: begin
            sram_addr = req_addr[4:2];
            stall_cpu = 1'b0;
            cpu_rdata = refill_data;
            wdata     = req_wr ? merged_refill_wdata : refill_data;
            we0       = !evict_way;
            we1       = evict_way;
            wet0      = 1'b1;
            wet1      = 1'b1;
            if (!evict_way) begin
                // Filling Way 0 -> Way 0 becomes MRU (U = 1)
                wtag0 = {1'b1, 1'b1, req_modifies, req_addr[15:5]};
                wtag1 = {other_tag[13], 1'b1, other_tag[11:0]};
            end else begin
                // Filling Way 1 -> Way 1 becomes MRU (U = 0)
                wtag0 = {other_tag[13], 1'b0, other_tag[11:0]};
                wtag1 = {1'b1, 1'b0, req_modifies, req_addr[15:5]};
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
                    other_tag <= victim_way ? rtag0 : rtag1;
                    if (need_wb) begin
                        addr_mem  <= {(victim_way ? tag1 : tag0), req_addr[4:2], 2'b00};
                        mem_wdata <= victim_way ? rdata1 : rdata0;
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

// Tag RAM Way 0
ram_sync_read_t0 #(
    .AWIDTH(3),
    .DWIDTH(TAG_ENTRY_W)
) tr0 (
    .clock(clock),
    .addr(sram_addr),
    .din(wtag0),
    .we(wet0),
    .dout(rtag0)
);

// Tag RAM Way 1
ram_sync_read_t1 #(
    .AWIDTH(3),
    .DWIDTH(TAG_ENTRY_W)
) tr1 (
    .clock(clock),
    .addr(sram_addr),
    .din(wtag1),
    .we(wet1),
    .dout(rtag1)
);

// Data RAM Way 0
ram_sync_read_d0 #(
    .AWIDTH(3),
    .DWIDTH(DWIDTH)
) dr0 (
    .clock(clock),
    .addr(sram_addr),
    .din(wdata),
    .we(we0),
    .dout(rdata0)
);

// Data RAM Way 1
ram_sync_read_d1 #(
    .AWIDTH(3),
    .DWIDTH(DWIDTH)
) dr1 (
    .clock(clock),
    .addr(sram_addr),
    .din(wdata),
    .we(we1),
    .dout(rdata1)
);

endmodule
