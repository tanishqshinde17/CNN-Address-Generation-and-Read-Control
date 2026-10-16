`timescale 1ns/1ps
//=====================================================================
// cnn_conv_top : full Layer-1 CNN read+convolve datapath.
//
//   cnn_l1_read_top (addr_gen + 4x sram_bank + pixel mux)
//        -> conv_engine (weight regfile + 3-stage row FIFO + 3x3 MAC)
//        -> out_mem (254x254x8-bit signed conv results)
//=====================================================================
module P2cnn_conv_top (
    input                   clk,
    input                   rst_n,
    input                   start,        // kick off the image scan

    // ---- weight (kernel) load port ----
    input                   wt_wr_en,
    input      [3:0]        wt_addr,      // 0..8
    input  signed [7:0]     wt_data,

    // ---- status ----
    output                  scan_done,    // address generator finished the image

    // ---- convolution result stream (also written into out_mem) ----
    output                  conv_out_valid,
    output     [7:0]        conv_out_row,
    output     [7:0]        conv_out_col,
    output signed [23:0]     conv_out_data,

    // ---- output-memory readback port (for host / testbench) ----
    input                   om_re,
    input      [15:0]       om_raddr,
    output signed [23:0]     om_rdata
);

    // ---------------- pixel read path (address gen + SRAM banks) ----------------
    wire        rd_valid, rd_done;
    wire [7:0]  pixel0, pixel1, pixel2;
    wire [7:0]  row_addr_o, col_start_o;
    wire [7:0]  pix_col0_o, pix_col1_o, pix_col2_o;
    wire [3:0]  bank_en_o;
    wire [23:0] col_addr_bus_o;

    cnn_l1_read_top u_read (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (start),
        .valid         (rd_valid),
        .done          (rd_done),
        .pixel0        (pixel0),
        .pixel1        (pixel1),
        .pixel2        (pixel2),
        .col_start_o   (col_start_o),
        .pix_col0_o    (pix_col0_o),
        .pix_col1_o    (pix_col1_o),
        .pix_col2_o    (pix_col2_o),
        .bank_en_o     (bank_en_o),
        .row_addr_o    (row_addr_o),
        .col_addr_bus_o(col_addr_bus_o)
    );

    assign scan_done = rd_done;

    // ---------------- convolution engine ----------------
    wire        c_valid;
    wire [7:0]  c_row, c_col;
    wire signed [23:0] c_data;

    P2conv_engine u_conv (
        .clk        (clk),
        .rst_n      (rst_n),
        .wt_wr_en   (wt_wr_en),
        .wt_addr    (wt_addr),
        .wt_data    (wt_data),
        .pix_valid  (rd_valid),
        .pixel0     (pixel0),
        .pixel1     (pixel1),
        .pixel2     (pixel2),
        .row_addr   (row_addr_o),
        .col_start  (col_start_o),
        .out_valid  (c_valid),
        .out_row    (c_row),
        .out_col    (c_col),
        .out_data   (c_data)
    );

    assign conv_out_valid = c_valid;
    assign conv_out_row   = c_row;
    assign conv_out_col   = c_col;
    assign conv_out_data  = c_data;

    // ---------------- output memory ----------------
    localparam OUT_W = 256;
    wire [15:0] om_waddr = c_row * OUT_W + c_col;   // row-major, 0..64515

    P2out_mem u_outmem (
        .clk   (clk),
        .we    (c_valid),
        .waddr (om_waddr),
        .din   (c_data),
        .re    (om_re),
        .raddr (om_raddr),
        .dout  (om_rdata)
    );

endmodule
