`timescale 1ns/1ps
//=====================================================================
// out_mem : behavioral output memory for the conv results.
//           254 x 254 x 8-bit SIGNED = 64516 entries ("valid" conv
//           output of a 3x3 kernel on a 256x256 image).
//           addr = row*254 + col   (row,col in [0,253])
//=====================================================================
module P2out_mem #(
    parameter OUT_W = 254,
    parameter OUT_H = 254,
    parameter DEPTH = OUT_W*OUT_H,   // 64516
    parameter AW    = 16             // ceil(log2(64516)) = 16
)(
    input                    clk,
    input                    we,
    input      [AW-1:0]      waddr,
    input  signed [23:0]      din,

    input                    re,      // present for interface completeness
    input      [AW-1:0]      raddr,
    output reg signed [23:0]  dout
);

    reg signed [23:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (we) mem[waddr] <= din;
    end

    always @(*) begin
        dout = mem[raddr];   // asynchronous read, for TB / readback convenience
    end

endmodule
