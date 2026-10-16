`timescale 1ns/1ps
//=====================================================================
// cnn_l1_read_top : glues addr_gen to the 4 physical SRAM banks and
//                   muxes the 3 read data bytes back in pixel order
//                   (pixel0 = col_start, pixel1 = col_start+1, pixel2 = col_start+2)
//=====================================================================
module cnn_l1_read_top (
    input        clk,
    input        rst_n,
    input        start,

    output       valid,
    output       done,

    output [7:0] pixel0,
    output [7:0] pixel1,
    output [7:0] pixel2,

    // debug (for testbench self-checking, mirrors addr_gen internals)
    output [7:0] col_start_o,
    output [7:0] pix_col0_o,
    output [7:0] pix_col1_o,
    output [7:0] pix_col2_o,
    output [3:0] bank_en_o,
    output [7:0] row_addr_o,
    output [23:0] col_addr_bus_o
);

    localparam NB = 4, RW = 8, CW = 6;

    wire [NB-1:0]     bank_en;
    wire [RW-1:0]     row_addr;
    wire [NB*CW-1:0]  col_bus;
    wire [7:0]        c0, c1, c2;

    addr_gen u_ag (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (start),
        .bank_en      (bank_en),
        .row_addr     (row_addr),
        .col_addr_bus (col_bus),
        .valid        (valid),
        .done         (done),
        .col_start_o  (col_start_o),
        .pix_col0_o   (c0),
        .pix_col1_o   (c1),
        .pix_col2_o   (c2)
    );

    assign pix_col0_o    = c0;
    assign pix_col1_o    = c1;
    assign pix_col2_o    = c2;
    assign bank_en_o     = bank_en;
    assign row_addr_o    = row_addr;
    assign col_addr_bus_o = col_bus;

    wire [7:0] dout [0:NB-1];

    genvar g;
    generate
        for (g = 0; g < NB; g = g + 1) begin : BANKS
            sram_bank u_bank (
                .clk  (clk),
                .we   (1'b0),
                .re   (bank_en[g]),
                .addr ({row_addr, col_bus[g*CW +: CW]}),
                .din  (8'd0),
                .dout (dout[g])
            );
        end
    endgenerate

    // route each active bank's data byte to the correct pixel output
    reg [7:0] p0, p1, p2;
    always @(*) begin
        p0 = dout[c0[1:0]];
        p1 = dout[c1[1:0]];
        p2 = dout[c2[1:0]];
    end

    assign pixel0 = p0;
    assign pixel1 = p1;
    assign pixel2 = p2;

endmodule
