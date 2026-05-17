// Project F Library - Simple Dual-Port Block RAM
// (C)2022 Will Green, Open source hardware released under the MIT License
// Learn more at https://projectf.io

`default_nettype none
`timescale 1ns / 1ps

module bram_sdp #(
    parameter WIDTH=8, 
    parameter DEPTH=256, 
    parameter INIT_F=""
    ) (
    input wire logic clk_write,
    input wire logic clk_read,
    input wire logic we,
    input wire logic [$clog2(DEPTH)-1:0] addr_write,
    input wire logic [$clog2(DEPTH)-1:0] addr_read,
    input wire logic [WIDTH-1:0] data_in,
    output     logic [WIDTH-1:0] data_out
    );

    logic [WIDTH-1:0] memory [DEPTH];

    initial begin
        if (INIT_F != 0) begin
            $display("Load init file '%s' into bram_sdp.", INIT_F);
            $readmemh(INIT_F, memory);
        end
    end

    // Port A: Sync Write
    always_ff @(posedge clk_write) begin
        if (we) memory[addr_write] <= data_in;
    end

    // Port B: Sync Read
    always_ff @(posedge clk_read) begin
        data_out <= memory[addr_read];
    end
endmodule
