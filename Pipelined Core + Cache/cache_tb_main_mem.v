`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/19/2024 04:41:06 PM
// Design Name: 
// Module Name: cache_tb_main_mem
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module cache_tb_main_mem;

    // Inputs
    reg clock;
    reg reset_n;
    reg [15:0] addr_cpu;
    reg rd_cpu;
    reg wr_cpu;
    reg ready_mem;
    wire ready_mem_mm;

    // Outputs
    wire [15:0] addr_mem;
    wire rd_mem;
    wire wr_mem;
    wire stall_cpu;

    // Bidirectional
    wire [7:0] data_cpu;
    wire [7:0] data_mem;
    wire [7:0] dmem;
    
    reg [7:0] wcpu;

    // Instantiate Cache Controller (DUT)
    cache_2wsa uut (
        .clock(clock), 
        .reset_n(reset_n), 
        .data_cpu(data_cpu), 
        .data_mem(data_mem), 
        .addr_cpu(addr_cpu), 
        .addr_mem(addr_mem), 
        .rd_cpu(rd_cpu), 
        .wr_cpu(wr_cpu), 
        .rd_mem(rd_mem), 
        .wr_mem(wr_mem), 
        .stall_cpu(stall_cpu), 
        .ready_mem(ready_mem)
    );

    // Instantiate Main Memory Module
    main_memory mem_inst (
        .clk(clock),
        .rst(~reset_n),
        .read_mem(rd_mem),
        .write_mem(wr_mem),
        .addr_mem(addr_mem),
        .data_mem(data_mem),
        .ready_mem(ready_mem_mm)
    );
    
    always@(*)
      ready_mem = ready_mem_mm;
    
    assign data_cpu = wr_cpu? wcpu : 8'dZ;
   // assign data_mem = !wr_mem? dmem : 8'dz;


    // Clock generator
    initial begin
        clock = 1'd0;
        forever #10 clock = ~clock;
    end

    // Task for clock delay
    task delay;
    begin
        @(negedge clock);
    end
    endtask

    // Test Sequence
    initial begin
        // Initialize inputs
        reset_n = 0;
        addr_cpu = 0;
        rd_cpu = 0;
        wr_cpu = 0;
        wcpu = 0;

        // Reset sequence
        repeat(4) delay;
        reset_n = 1;

        delay;
        delay;
        // Simple Read
        rd_cpu = 1'd1;
        addr_cpu = 16'b0000_0000_1001_0011;
        delay;
        delay;
        rd_cpu = 1'd0;
        
        delay;
        delay;
        // Simple Write
        wr_cpu = 1'd1;
        wcpu = 8'h23;
        addr_cpu = 16'b0000_0000_1001_0011;
        delay;  
        delay;
        wr_cpu = 1'd0;
        delay;
        delay;

        // Read back data
        delay;
        rd_cpu = 1;
        addr_cpu = 16'b0000_0000_1001_0011;
        delay;
        rd_cpu = 0;
        delay;

        // End of Simulation
        #100 $finish;
    end
endmodule

