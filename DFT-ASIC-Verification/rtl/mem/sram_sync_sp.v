`timescale 1ns/1ps

// Synthesizable single-port synchronous-read SRAM wrapper with MBIST muxing
// and simulation-only fault-injection hooks.
// When SYNTHESIS_SRAM_BLACKBOX is defined during logic scan/ATPG synthesis,
// the module acts as a black-box boundary so internal arrays are tested via MBIST
// rather than exploded into scan flip-flops.
`ifdef SYNTHESIS_SRAM_BLACKBOX
(* blackbox *)
`endif
module sram_sync_sp #(
    parameter integer AWIDTH = 3,
    parameter integer DWIDTH = 32
) (
    input  wire              clock,
    // Functional port
    input  wire [AWIDTH-1:0] addr,
    input  wire [DWIDTH-1:0] din,
    input  wire              we,
    output wire [DWIDTH-1:0] dout,
    // MBIST mux port
    input  wire              bist_en,
    input  wire [AWIDTH-1:0] bist_addr,
    input  wire [DWIDTH-1:0] bist_din,
    input  wire              bist_we,
    output wire [DWIDTH-1:0] bist_dout
`ifndef SYNTHESIS
    ,
    // Simulation-only fault injection interface for MBIST verification
    input  wire              inj_en,
    input  wire [AWIDTH-1:0] inj_addr,
    input  wire [5:0]        inj_bit,
    input  wire [1:0]        inj_type  // 2'b01=SA0, 2'b10=SA1, 2'b11=bit-flip
`endif
);
    localparam integer DEPTH = (1 << AWIDTH);
    localparam integer BIT_W = (DWIDTH > 1) ? $clog2(DWIDTH) : 1;

`ifndef SYNTHESIS_SRAM_BLACKBOX
    reg [DWIDTH-1:0] mem_array [0:DEPTH-1];
    reg [AWIDTH-1:0] rd_addr;

    wire [AWIDTH-1:0] eff_addr = bist_en ? bist_addr : addr;
    wire [DWIDTH-1:0] eff_din  = bist_en ? bist_din  : din;
    wire              eff_we   = bist_en ? bist_we   : we;

`ifndef SYNTHESIS
    integer idx;
    initial begin
        for (idx = 0; idx < DEPTH; idx = idx + 1) begin
            mem_array[idx] = {DWIDTH{1'b0}};
        end
        rd_addr = {AWIDTH{1'b0}};
    end
`endif

    always @(posedge clock) begin
        if (eff_we) begin
            mem_array[eff_addr] <= eff_din;
        end
        rd_addr <= eff_addr;
    end

    wire [DWIDTH-1:0] raw_dout = mem_array[rd_addr];

`ifndef SYNTHESIS
    reg [DWIDTH-1:0] faulted_dout;
    wire [BIT_W-1:0] inj_bit_idx = inj_bit[BIT_W-1:0];
    always @(*) begin
        faulted_dout = raw_dout;
        if (inj_en && (rd_addr == inj_addr) && ({1'b0, inj_bit} < DWIDTH[6:0])) begin
            case (inj_type)
                2'b01: faulted_dout[inj_bit_idx] = 1'b0;
                2'b10: faulted_dout[inj_bit_idx] = 1'b1;
                2'b11: faulted_dout[inj_bit_idx] = ~raw_dout[inj_bit_idx];
                default: faulted_dout = raw_dout;
            endcase
        end
    end
    assign dout      = faulted_dout;
    assign bist_dout = faulted_dout;
`else
    assign dout      = raw_dout;
    assign bist_dout = raw_dout;
`endif
`else
    assign dout      = {DWIDTH{1'b0}};
    assign bist_dout = {DWIDTH{1'b0}};
`endif

endmodule
