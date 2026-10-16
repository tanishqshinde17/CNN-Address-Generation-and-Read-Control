`timescale 1ns/1ps
//=====================================================================
// sram_bank : behavioral model of ONE bank of the input SRAM
//             256 rows x 64 cols x 8-bit = 16384 Bytes, 14-bit address
//             8-bit read/write port (as specified).
//
// Read is modeled as asynchronous (combinational) to keep the address-
// generation testbench simple. For a real (registered-read) SRAM, add
// a 1-cycle pipeline register on dout and delay the checker by 1 cycle.
//=====================================================================
module sram_bank #(
    parameter DEPTH = 256,          // rows
    parameter WIDTH = 64,           // columns
    parameter AW    = 14            // = log2(DEPTH*WIDTH)
)(
    input               clk,
    input               we,
    input               re,         // present for interface completeness
    input      [AW-1:0] addr,
    input      [7:0]    din,
    output reg [7:0]    dout
);

    reg [7:0] mem [0:DEPTH*WIDTH-1];

    always @(posedge clk) begin
        if (we) mem[addr] <= din;
    end

    always @(*) begin
        dout = mem[addr];
    end

endmodule
