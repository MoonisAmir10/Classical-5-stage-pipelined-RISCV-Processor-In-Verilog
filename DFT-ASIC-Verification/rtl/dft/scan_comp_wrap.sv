`timescale 1ns/1ps

// Scan Decompressor, Spatial XOR Compactor, X-Masking & 16-bit MISR Wrapper.
// Reference: docs/dft_spec.md Section 3.2 and Section 6
// Supports:
//   - Uncompressed 1-chain daisy-chain bypass (comp_en = 0):
//       ext_scan_in[0] -> chain[0] -> ... -> chain[7] -> ext_scan_out[0]
//   - Compressed 2:8 XOR+LFSR Decompressor + 8:2 XOR Compactor (comp_en = 1):
//       ext_scan_in[1:0] + 8b LFSR -> chain_scan_in[7:0]
//       masked(chain_scan_out[7:0]) -> 8:2 XOR compactor -> ext_scan_out[1:0]
//   - Per-chain X-masking: chain_x_mask[i]=1 forces masked_chain_out[i]=0 (blocks X)
//   - 16-bit MISR signature register clocked during active scan shift
module scan_comp_wrap #(
    parameter integer N_EXT    = 2,
    parameter integer N_CHAINS = 8
) (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                scan_en,
    input  logic                comp_en,
    input  logic                misr_en,
    input  logic                misr_clr,
    input  logic [N_CHAINS-1:0] chain_x_mask,

    // External ATE scan pins
    input  logic [N_EXT-1:0]    ext_scan_in,
    output logic [N_EXT-1:0]    ext_scan_out,

    // Internal parallel scan chain boundary
    output logic [N_CHAINS-1:0] chain_scan_in,
    input  logic [N_CHAINS-1:0] chain_scan_out,

    // 16-bit MISR signature
    output logic [15:0]         misr_sig
);

    // 8-bit decompressor LFSR & 16-bit signature MISR
    logic [7:0]  decomp_lfsr_q;
    logic [15:0] misr_q;

    assign misr_sig = misr_q;

    // Explicit X-blocking mask per chain: 0 & X === 0 in IEEE 1800 4-state Verilog
    logic [N_CHAINS-1:0] masked_out;
    genvar i;
    generate
        for (i = 0; i < N_CHAINS; i = i + 1) begin : g_xmask
            assign masked_out[i] = (~chain_x_mask[i]) & chain_scan_out[i];
        end
    endgenerate

    // 2:8 Decompressor (comp_en=1) vs. 1-chain serial daisy-chain bypass (comp_en=0)
    wire [7:0] decomp_expanded = {
        ext_scan_in[1] ^ decomp_lfsr_q[7] ^ decomp_lfsr_q[1],
        ext_scan_in[0] ^ decomp_lfsr_q[6] ^ decomp_lfsr_q[0],
        ext_scan_in[1] ^ decomp_lfsr_q[5],
        ext_scan_in[0] ^ decomp_lfsr_q[4],
        ext_scan_in[1] ^ decomp_lfsr_q[3] ^ ext_scan_in[0],
        ext_scan_in[0] ^ decomp_lfsr_q[2] ^ decomp_lfsr_q[7],
        ext_scan_in[1] ^ decomp_lfsr_q[1],
        ext_scan_in[0] ^ decomp_lfsr_q[0]
    };

    wire [7:0] bypass_chains = {masked_out[6:0], ext_scan_in[0]};

    assign chain_scan_in = comp_en ? decomp_expanded : bypass_chains;

    // 8:2 Spatial XOR Compactor (even chains -> out[0], odd chains -> out[1]) vs. Bypass
    wire comp_out_even = masked_out[0] ^ masked_out[2] ^ masked_out[4] ^ masked_out[6];
    wire comp_out_odd  = masked_out[1] ^ masked_out[3] ^ masked_out[5] ^ masked_out[7];

    assign ext_scan_out[0] = comp_en ? comp_out_even : masked_out[7];
    assign ext_scan_out[1] = comp_en ? comp_out_odd  : masked_out[0];

    // Sequential LFSR & 16-bit MISR (x^16 + x^14 + x^13 + x^11 + 1)
    wire lfsr_fb = decomp_lfsr_q[7] ^ decomp_lfsr_q[5] ^ decomp_lfsr_q[4] ^ decomp_lfsr_q[3];
    wire misr_fb = misr_q[15] ^ misr_q[13] ^ misr_q[12] ^ misr_q[10];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            decomp_lfsr_q <= 8'hA5;
            misr_q        <= 16'h0000;
        end else begin
            if (misr_clr) begin
                decomp_lfsr_q <= 8'hA5;
                misr_q        <= 16'h0000;
            end else begin
                if (scan_en && comp_en) begin
                    decomp_lfsr_q <= {decomp_lfsr_q[6:0], lfsr_fb ^ ext_scan_in[0] ^ ext_scan_in[1]};
                end
                if (misr_en && scan_en) begin
                    misr_q <= {misr_q[14:0], misr_fb} ^ {8'h00, masked_out};
                end
            end
        end
    end

endmodule
