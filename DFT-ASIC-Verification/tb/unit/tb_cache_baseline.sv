`timescale 1ns/1ps

module tb_cache_baseline;
    reg         clock;
    reg         reset_n;

    reg  [7:0]  cpu_wdata;
    wire [7:0]  cpu_rdata;
    wire        cpu_rdata_oe;
    reg  [15:0] addr_cpu;
    reg         rd_cpu;
    reg         wr_cpu;
    wire        stall_cpu;

    reg  [7:0]  mem_rdata;
    wire [7:0]  mem_wdata;
    wire        mem_wdata_oe;
    wire [15:0] addr_mem;
    wire        rd_mem;
    wire        wr_mem;
    reg         ready_mem_r;
    wire        ready_mem;

    reg         bist_en;
    reg  [1:0]  bist_bank_sel;
    reg  [2:0]  bist_addr;
    reg  [31:0] bist_din;
    reg         bist_we;
    wire [31:0] bist_dout;

    reg         inj_en;
    reg  [1:0]  inj_bank;
    reg  [2:0]  inj_addr;
    reg  [5:0]  inj_bit;
    reg  [1:0]  inj_type;

    cache_2wsa_dft dut (
        .clock         (clock),
        .reset_n       (reset_n),
        .cpu_wdata     (cpu_wdata),
        .cpu_rdata     (cpu_rdata),
        .cpu_rdata_oe  (cpu_rdata_oe),
        .addr_cpu      (addr_cpu),
        .rd_cpu        (rd_cpu),
        .wr_cpu        (wr_cpu),
        .stall_cpu     (stall_cpu),
        .mem_rdata     (mem_rdata),
        .mem_wdata     (mem_wdata),
        .mem_wdata_oe  (mem_wdata_oe),
        .addr_mem      (addr_mem),
        .rd_mem        (rd_mem),
        .wr_mem        (wr_mem),
        .ready_mem     (ready_mem),
        .bist_en       (bist_en),
        .bist_bank_sel (bist_bank_sel),
        .bist_addr     (bist_addr),
        .bist_din      (bist_din),
        .bist_we       (bist_we),
        .bist_dout     (bist_dout),
        .inj_en        (inj_en),
        .inj_bank      (inj_bank),
        .inj_addr      (inj_addr),
        .inj_bit       (inj_bit),
        .inj_type      (inj_type)
    );

    initial clock = 1'b0;
    always #5 clock = ~clock;

    // Backing memory model matching cache_2wsa_dft protocol
    reg [7:0] ext_mem [0:65535];
    reg [2:0] mm_cnt;
    reg [1:0] mm_mode; // 0=idle, 1=read_wait, 2=write_burst, 3=read_burst
    reg [15:0] mm_base_addr;
    integer k;

    reg        rd_mem_d, wr_mem_d;
    wire       new_req = (rd_mem && !rd_mem_d) || (wr_mem && !wr_mem_d);
    assign ready_mem = (mm_mode == 2'd0 && new_req) ? 1'b0 : ready_mem_r;

    /* verilator lint_off SYNCASYNCNET */
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            ready_mem_r  <= 1'b1;
            mem_rdata    <= 8'd0;
            mm_cnt       <= 3'd0;
            mm_mode      <= 2'd0;
            mm_base_addr <= 16'd0;
            rd_mem_d     <= 1'b0;
            wr_mem_d     <= 1'b0;
        end else begin
            rd_mem_d <= rd_mem;
            wr_mem_d <= wr_mem;
            case (mm_mode)
                2'd0: begin
                    ready_mem_r <= 1'b1;
                    if (rd_mem && !rd_mem_d) begin
                        ready_mem_r  <= 1'b0;
                        mm_base_addr <= addr_mem;
                        mm_cnt       <= 3'd0;
                        mm_mode      <= 2'd1;
                    end else if (wr_mem && !wr_mem_d) begin
                        ready_mem_r  <= 1'b0;
                        mm_base_addr <= addr_mem;
                        mm_cnt       <= 3'd0;
                        mm_mode      <= 2'd2;
                    end
                end
                2'd1: begin
                    ready_mem_r <= 1'b1;
                    mm_mode     <= 2'd3;
                    mm_cnt      <= 3'd0;
                end
                2'd3: begin
                    mem_rdata <= ext_mem[mm_base_addr + {13'd0, mm_cnt}];
                    if (mm_cnt == 3'd3) begin
                        mm_mode <= 2'd0;
                    end else begin
                        mm_cnt <= mm_cnt + 3'd1;
                    end
                end
                2'd2: begin
                    if (mm_cnt < 3'd4) begin
                        ext_mem[mm_base_addr + {13'd0, mm_cnt}] <= mem_wdata;
                    end
                    if (mm_cnt == 3'd3) begin
                        ready_mem_r <= 1'b1;
                        mm_mode     <= 2'd0;
                    end else begin
                        mm_cnt <= mm_cnt + 3'd1;
                    end
                end
                default: mm_mode <= 2'd0;
            endcase
        end
    end
    /* verilator lint_on SYNCASYNCNET */

    task automatic cpu_read(input [15:0] addr, output [7:0] val);
        integer guard;
        reg missed;
        begin
            @(negedge clock);
            addr_cpu = addr;
            rd_cpu   = 1'b1;
            wr_cpu   = 1'b0;
            @(negedge clock); // IDLE -> READ sampled
            @(negedge clock); // READ decision sampled (hit -> IDLE; miss -> stall_cpu=1)
            missed = stall_cpu;
            guard  = 0;
            while (stall_cpu && guard < 40) begin
                @(negedge clock);
                guard = guard + 1;
            end
            if (guard >= 40) begin
                $display("FAIL: timeout waiting on cpu_read(0x%h)", addr);
                $finish(1);
            end
            if (missed) begin
                // Allow SRAM write in IDLE, then 2 cycles for hit READ -> rdata_byte
                @(negedge clock);
                @(negedge clock);
                @(negedge clock);
            end
            rd_cpu = 1'b0;
            val    = cpu_rdata;
        end
    endtask

    task automatic cpu_write(input [15:0] addr, input [7:0] val);
        integer guard;
        reg missed;
        begin
            @(negedge clock);
            addr_cpu  = addr;
            cpu_wdata = val;
            wr_cpu    = 1'b1;
            rd_cpu    = 1'b0;
            @(negedge clock); // IDLE -> WRITE sampled
            @(negedge clock); // WRITE decision sampled
            missed = stall_cpu;
            guard  = 0;
            while (stall_cpu && guard < 40) begin
                @(negedge clock);
                guard = guard + 1;
            end
            if (guard >= 40) begin
                $display("FAIL: timeout waiting on cpu_write(0x%h)", addr);
                $finish(1);
            end
            if (missed) begin
                // Allow SRAM write in IDLE, then complete write-hit cycle
                @(negedge clock);
                @(negedge clock);
                @(negedge clock);
            end
            wr_cpu = 1'b0;
            @(negedge clock); // commit SRAM write on IDLE edge
        end
    endtask

    reg [7:0] rval;

    initial begin
        cpu_wdata     = 8'd0;
        addr_cpu      = 16'd0;
        rd_cpu        = 1'b0;
        wr_cpu        = 1'b0;
        bist_en       = 1'b0;
        bist_bank_sel = 2'd0;
        bist_addr     = 3'd0;
        bist_din      = 32'd0;
        bist_we       = 1'b0;
        inj_en        = 1'b0;
        inj_bank      = 2'd0;
        inj_addr      = 3'd0;
        inj_bit       = 6'd0;
        inj_type      = 2'd0;

        for (k = 0; k < 65536; k = k + 1) begin
            ext_mem[k] = 8'd0;
        end
        ext_mem[16'h0000] = 8'hA0;
        ext_mem[16'h0001] = 8'hA1;
        ext_mem[16'h0002] = 8'hA2;
        ext_mem[16'h0003] = 8'hA3;

        ext_mem[16'h0020] = 8'hB0;
        ext_mem[16'h0021] = 8'hB1;
        ext_mem[16'h0022] = 8'hB2;
        ext_mem[16'h0023] = 8'hB3;

        ext_mem[16'h0040] = 8'hC0;
        ext_mem[16'h0041] = 8'hC1;
        ext_mem[16'h0042] = 8'hC2;
        ext_mem[16'h0043] = 8'hC3;

        reset_n = 1'b1;
        #2;
        reset_n = 1'b0;
        repeat (3) @(posedge clock);
        @(negedge clock);
        reset_n = 1'b1;

        // 1. Read miss & refill on tag 0, index 0
        cpu_read(16'h0002, rval);
        if (rval !== 8'hA2) begin
            $display("FAIL [read miss/hit]: expected 0xA2, got 0x%h", rval);
            $finish(1);
        end

        // 2. Write hit dirty byte on tag 0, index 0
        cpu_write(16'h0002, 8'h5A);
        cpu_read(16'h0002, rval);
        if (rval !== 8'h5A) begin
            $display("FAIL [write hit]: expected 0x5A, got 0x%h", rval);
            $finish(1);
        end

        // 3. Fill Way 1 with tag 1, index 0 and dirty it
        cpu_write(16'h0021, 8'h77);
        cpu_read(16'h0021, rval);
        if (rval !== 8'h77) begin
            $display("FAIL [way1 write]: expected 0x77, got 0x%h", rval);
            $finish(1);
        end

        // 4. Access tag 2, index 0 -> forces dirty eviction of LRU way
        cpu_read(16'h0043, rval);
        if (rval !== 8'hC3) begin
            $display("FAIL [eviction fill]: expected 0xC3, got 0x%h", rval);
            $finish(1);
        end
        if (ext_mem[16'h0002] !== 8'h5A) begin
            $display("FAIL [writeback]: expected ext_mem[0x0002]=0x5A, got 0x%h", ext_mem[16'h0002]);
            $finish(1);
        end
        $display("PASS [Cache Functional]: miss, refill, dirty write hit, and LRU writeback verified");

        // 5. MBIST port + fault-injection verification on bank 2 (data RAM way 0)
        @(negedge clock);
        bist_en       = 1'b1;
        bist_bank_sel = 2'd2;
        bist_addr     = 3'd5;
        bist_din      = 32'hDEADBEEF;
        bist_we       = 1'b1;
        @(posedge clock);
        @(negedge clock);
        bist_we = 1'b0;
        @(posedge clock);
        #1;
        if (bist_dout !== 32'hDEADBEEF) begin
            $display("FAIL [MBIST port]: expected 0xDEADBEEF, got 0x%h", bist_dout);
            $finish(1);
        end

        // Inject stuck-at-0 fault at bit 0 of address 5
        inj_en   = 1'b1;
        inj_bank = 2'd2;
        inj_addr = 3'd5;
        inj_bit  = 6'd0;
        inj_type = 2'd1; // SA0
        #1;
        if (bist_dout !== 32'hDEADBEEE) begin
            $display("FAIL [Fault Inject]: expected 0xDEADBEEE, got 0x%h", bist_dout);
            $finish(1);
        end
        inj_en  = 1'b0;
        bist_en = 1'b0;
        $display("PASS [MBIST Hook & Fault Injection]: SRAM mux and SA0 fault hook verified");
        $finish;
    end
endmodule
