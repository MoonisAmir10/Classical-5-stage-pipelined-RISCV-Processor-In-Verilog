`timescale 1ns / 1ps

// Self-checking integration testbench for cache_2wsa + main_memory.v
module cache_tb_main_mem #(
    parameter MEM_LATENCY = 4
);

    reg         clock;
    reg         reset_n;
    reg  [15:0] addr_cpu;
    reg  [31:0] cpu_wdata;
    reg  [3:0]  cpu_wstrb;
    reg         rd_cpu;
    reg         wr_cpu;
    wire [31:0] cpu_rdata;
    wire        stall_cpu;

    wire [15:0] addr_mem;
    wire [31:0] mem_wdata;
    wire [31:0] mem_rdata;
    wire        rd_mem;
    wire        wr_mem;
    wire        ready_mem;

    wire        cache_hit;
    wire        cache_miss;
    wire        cache_wb;

    cache_2wsa uut (
        .clock      (clock),
        .reset_n    (reset_n),
        .addr_cpu   (addr_cpu),
        .cpu_wdata  (cpu_wdata),
        .cpu_wstrb  (cpu_wstrb),
        .rd_cpu     (rd_cpu),
        .wr_cpu     (wr_cpu),
        .cpu_rdata  (cpu_rdata),
        .stall_cpu  (stall_cpu),
        .addr_mem   (addr_mem),
        .mem_wdata  (mem_wdata),
        .mem_rdata  (mem_rdata),
        .rd_mem     (rd_mem),
        .wr_mem     (wr_mem),
        .ready_mem  (ready_mem),
        .cache_hit  (cache_hit),
        .cache_miss (cache_miss),
        .cache_wb   (cache_wb)
    );

    main_memory #(
        .WORD_BITS (10),
        .LATENCY   (MEM_LATENCY)
    ) mem_inst (
        .clk       (clock),
        .rst_n     (reset_n),
        .read_mem  (rd_mem),
        .write_mem (wr_mem),
        .addr_mem  (addr_mem),
        .wdata_mem (mem_wdata),
        .rdata_mem (mem_rdata),
        .ready_mem (ready_mem)
    );

    initial clock = 1'b0;
    always #5 clock = ~clock;

    task automatic cpu_read(input [15:0] addr, output [31:0] val);
        integer guard;
        begin
            addr_cpu  = addr;
            rd_cpu    = 1'b1;
            wr_cpu    = 1'b0;
            cpu_wstrb = 4'b1111;
            #1;
            guard = 0;
            while (stall_cpu && guard < 60) begin
                @(posedge clock);
                #1;
                guard = guard + 1;
            end
            if (guard >= 60) begin
                $display("FAIL: cpu_read(0x%04h) timed out", addr);
                $finish(1);
            end
            val = cpu_rdata;
            @(posedge clock);
            #1;
            rd_cpu = 1'b0;
        end
    endtask

    task automatic cpu_write(input [15:0] addr, input [31:0] val, input [3:0] strb);
        integer guard;
        begin
            addr_cpu  = addr;
            cpu_wdata = val;
            cpu_wstrb = strb;
            rd_cpu    = 1'b0;
            wr_cpu    = 1'b1;
            #1;
            guard = 0;
            while (stall_cpu && guard < 60) begin
                @(posedge clock);
                #1;
                guard = guard + 1;
            end
            if (guard >= 60) begin
                $display("FAIL: cpu_write(0x%04h) timed out", addr);
                $finish(1);
            end
            @(posedge clock);
            #1;
            wr_cpu = 1'b0;
        end
    endtask

    reg [31:0] rval;

    initial begin
        addr_cpu  = 16'd0;
        cpu_wdata = 32'd0;
        cpu_wstrb = 4'b1111;
        rd_cpu    = 1'b0;
        wr_cpu    = 1'b0;

        // Preload main_memory words (addresses 0x0000, 0x0020, 0x0040 all map to Set 0!)
        mem_inst.memory[10'h000] = 32'h1111_0001; // 0x0000
        mem_inst.memory[10'h008] = 32'h2222_0002; // 0x0020
        mem_inst.memory[10'h010] = 32'h3333_0003; // 0x0040

        reset_n = 1'b0;
        repeat (3) @(posedge clock);
        #1;
        reset_n = 1'b1;

        // 1. Cold read miss on 0x0000
        cpu_read(16'h0000, rval);
        if (rval !== 32'h1111_0001) begin
            $display("FAIL [cold miss]: got 0x%08h exp 0x11110001", rval);
            $finish(1);
        end

        // 2. Write hit on 0x0000 (write-back -> main_memory stays 0x1111_0001!)
        cpu_write(16'h0000, 32'hCAFE_BABE, 4'b1111);
        if (mem_inst.memory[10'h000] !== 32'h1111_0001) begin
            $display("FAIL [write-back]: main_memory prematurely updated to 0x%08h", mem_inst.memory[10'h000]);
            $finish(1);
        end

        // 3. Read hit returns updated cached value
        cpu_read(16'h0000, rval);
        if (rval !== 32'hCAFE_BABE) begin
            $display("FAIL [read hit]: got 0x%08h exp 0xCAFEBABE", rval);
            $finish(1);
        end

        // 4. Fill Way 1 with 0x0020, making 0x0000 LRU
        cpu_read(16'h0020, rval);
        if (rval !== 32'h2222_0002) begin
            $display("FAIL [way1 miss]: got 0x%08h exp 0x22220002", rval);
            $finish(1);
        end

        // 5. Access 0x0040 -> forces dirty eviction of LRU Way 0 (0x0000 -> CAFE_BABE written to main_memory!)
        cpu_read(16'h0040, rval);
        if (rval !== 32'h3333_0003) begin
            $display("FAIL [evict refill]: got 0x%08h exp 0x33330003", rval);
            $finish(1);
        end
        if (mem_inst.memory[10'h000] !== 32'hCAFE_BABE) begin
            $display("FAIL [dirty WB]: main_memory[0x0000]=0x%08h exp 0xCAFEBABE", mem_inst.memory[10'h000]);
            $finish(1);
        end

        $display("PASS [cache_tb_main_mem]: cache_2wsa + main_memory (LATENCY=%0d) miss/hit/write-back/eviction verified", MEM_LATENCY);
        $finish;
    end
endmodule
