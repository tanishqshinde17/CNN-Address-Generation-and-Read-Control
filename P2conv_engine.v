`timescale 1ns/1ps
//=====================================================================
// conv_engine : 3x3 convolution MAC unit for the Layer-1 CNN datapath.
//
//   Weight port (load mode):
//     wt_wr_en=1, wt_addr = 0..8 (row-major: idx = krow*3+kcol),
//     wt_data = signed 8-bit kernel tap -> stored in local kernel[] regfile.
//     (Independent of the pixel pipeline - load before asserting 'start'
//      on the address generator.)
//
//   Pixel stream (compute mode):
//     Driven directly by cnn_l1_read_top: each valid cycle delivers 3
//     pixels {pixel0,pixel1,pixel2} = 3 consecutive columns of the row
//     'row_addr', for the current column window 'col_start'.
//     Because the address generator holds col_start fixed and scans all
//     rows before moving on, 3 CONSECUTIVE valid cycles = 3 consecutive
//     image rows at the same 3 columns = one 3x3 patch. A 3-entry row
//     FIFO (shift register) buffers exactly that.
//
//   Result:
//     out_valid/out_row/out_col/out_data stream one conv result per
//     cycle (1 cycle after the 3rd+ row of each column-window arrives),
//     out_row/out_col in [0,253] -> 254x254 "valid" convolution output.
//     out_data = 8-bit SIGNED TRUNCATION (low byte) of the 24-bit
//     accumulator (wraps on overflow; swap for a saturate() if desired).
//=====================================================================
module P2conv_engine (
    input                    clk,
    input                    rst_n,

    // ---- weight (kernel) load port ----
    input                    wt_wr_en,
    input      [3:0]         wt_addr,     // 0..8
    input  signed [7:0]      wt_data,

    // ---- pixel stream from address generator / SRAM ----
    input                    pix_valid,
    input      [7:0]         pixel0, pixel1, pixel2,  // 3 consecutive cols, current row
    input      [7:0]         row_addr,    // 0..255 : current row within column window
    input      [7:0]         col_start,   // 0..253 : current column-window start

    // ---- convolution result stream ----
    output reg               out_valid,
    output reg [7:0]         out_row,     // 0..253 output memory row address
    output reg [7:0]         out_col,     // 0..253  output memory col address
    output reg signed [23:0]  out_data
);

    // ---------------- kernel (weight) regfile ----------------
    reg signed [7:0] kernel [0:8];   // kernel[krow*3+kcol]

    always @(posedge clk) begin
        if (wt_wr_en) kernel[wt_addr] <= wt_data;
    end

    // ---------------- 3-stage row FIFO : pix_win[row][col] ----------------
    // row0 = oldest row in the current 3x3 patch, row2 = newest (just arrived)
    reg [7:0] pix_win [0:2][0:2];
    reg [1:0] fill_cnt;               // # of rows loaded in current column-window (sat @3)

    // combinational "next window" = window contents AFTER shifting in the
    // incoming triplet (this is the window the MAC uses THIS cycle)
    wire [7:0] nw00 = pix_win[1][0], nw01 = pix_win[1][1], nw02 = pix_win[1][2];
    wire [7:0] nw10 = pix_win[2][0], nw11 = pix_win[2][1], nw12 = pix_win[2][2];
    wire [7:0] nw20 = pixel0,        nw21 = pixel1,        nw22 = pixel2;

    wire [1:0] fill_cnt_next  = (row_addr == 8'd0) ? 2'd1 :
                                 (fill_cnt < 2'd3)  ? (fill_cnt + 2'd1) : 2'd3;
    wire       win_valid_next = (row_addr != 8'd0) && (fill_cnt >= 2'd2);

    // ---------------- 3x3 MAC (combinational, on the next window) ----------------
    // pixels are unsigned 0..255 -> zero-extend to 9 bits, cast signed, so
    // sign of the product is driven purely by the (signed) kernel weight.
    wire signed [17:0] p00 = $signed({1'b0,nw00}) * kernel[0];
    wire signed [17:0] p01 = $signed({1'b0,nw01}) * kernel[1];
    wire signed [17:0] p02 = $signed({1'b0,nw02}) * kernel[2];
    wire signed [17:0] p10 = $signed({1'b0,nw10}) * kernel[3];
    wire signed [17:0] p11 = $signed({1'b0,nw11}) * kernel[4];
    wire signed [17:0] p12 = $signed({1'b0,nw12}) * kernel[5];
    wire signed [17:0] p20 = $signed({1'b0,nw20}) * kernel[6];
    wire signed [17:0] p21 = $signed({1'b0,nw21}) * kernel[7];
    wire signed [17:0] p22 = $signed({1'b0,nw22}) * kernel[8];

    wire signed [23:0] mac_sum = p00+p01+p02 + p10+p11+p12 + p20+p21+p22;

    // ---------------- sequential update ----------------
    integer ii, jj;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fill_cnt  <= 2'd0;
            out_valid <= 1'b0;
            out_row   <= 8'd0;
            out_col   <= 8'd0;
            out_data  <= 8'sd0;
            for (ii=0; ii<3; ii=ii+1)
                for (jj=0; jj<3; jj=jj+1)
                    pix_win[ii][jj] <= 8'd0;
        end else begin
            if (pix_valid) begin
                // shift in the new row -> becomes the FIFO's newest entry
                pix_win[0][0] <= nw00; pix_win[0][1] <= nw01; pix_win[0][2] <= nw02;
                pix_win[1][0] <= nw10; pix_win[1][1] <= nw11; pix_win[1][2] <= nw12;
                pix_win[2][0] <= nw20; pix_win[2][1] <= nw21; pix_win[2][2] <= nw22;

                fill_cnt  <= fill_cnt_next;
                out_valid <= win_valid_next;
                out_row   <= row_addr - 8'd2;   // top row of the completed window
                out_col   <= col_start;         // left col of the completed window
                out_data  <= mac_sum[23:0];      // <-- truncate to 8-bit signed
            end else begin
                out_valid <= 1'b0;              // no new sample -> no new result
            end
        end
    end

endmodule
