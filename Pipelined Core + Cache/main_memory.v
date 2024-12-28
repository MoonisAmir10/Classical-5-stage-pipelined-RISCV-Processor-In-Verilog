`timescale 1ns / 1ps

module main_memory (
    input wire clk,                  // Clock signal
    input wire rst,                  // Reset signal
    input wire read_mem,             // Read signal from cache controller
    input wire write_mem,            // Write signal from cache controller
    input wire [15:0] addr_mem,      // Memory address from cache controller
    inout wire [7:0] data_mem,       // Bidirectional data bus
    output reg ready_mem             // Memory ready signal
);

    // Internal memory: 64KB of 8-bit locations
    reg [7:0] memory [0:65535];      // 2^16 addresses of 1 byte each

    // Internal signals
    reg [7:0] data_out;              // Data to send during read
    reg data_bus_dir;                // Direction control for data bus

    // Tri-state buffer for bidirectional data bus
  //  assign data_mem = (!write_mem) ? data_out : 8'bz;
  	assign data_mem = (!write_mem)? data_out : 8'dZ;


    // Memory Ready Simulation
    reg [2:0] cycle_count;           // Counter to simulate memory delay

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ready_mem <= 1'b1;       // Memory is ready after reset
            data_bus_dir <= 1'b0;
            data_out <= 8'b0;
            cycle_count <= 0;
        end else begin
            // Default to ready state
            ready_mem <= 1'b1;

            if (read_mem) begin
//                // Simulate memory read delay
//                if (cycle_count < 4) begin
                    ready_mem <= 1'b0;  // Memory is busy
                    //cycle_count <= cycle_count + 1; 
                 //   end
               //  else begin
                    data_bus_dir <= 1'b1;  // Set data bus direction to output
                    data_out <= memory[addr_mem];  // Send data to bus
                  //  cycle_count <= 0;
                end
               else if (write_mem) begin
                // Simulate memory write delay
                if (cycle_count < 1) begin
                    ready_mem <= 1'b0;  // Memory is busy
                    cycle_count <= cycle_count + 1; end
                 else begin
                    memory[addr_mem] <= data_mem;  // Write data to memory
                    cycle_count <= 0;
                end
            end else begin
            //    data_bus_dir <= 1'b0;  // Set data bus to high impedance
                data_out <= 8'b0;
            end
        end
    end
endmodule

