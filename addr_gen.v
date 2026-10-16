`timescale 1ns/1ps
//=====================================================================
// addr_gen : Address generator for Layer-1 CNN "read 3 consecutive
//            pixels/cycle" access pattern.
//
// Image   : 256 x 256, 8-bit pixels
// SRAM    : 4 banks, each 256 rows x 64 columns x 8-bit (256x64 Bytes)
// Storage : pixel(r,c) -> bank = c % 4 , bank_row = r , bank_col = c/4
//           (row-major within a bank: 1st pixel of a row -> bank0,
//            2nd -> bank1, 3rd -> bank2, 4th -> bank3, 5th -> bank0 ...)
//
// Behaviour (per spec):
//   - pick the 3 (of 4) banks holding columns {c0,c0+1,c0+2}
//   - compute the column address for each of those banks
//   - hold column addresses fixed and scan ALL 256 rows (row_addr++)
//   - after the row scan finishes, advance c0 by 1 (stride = 1) and
//     repeat, until c0+2 reaches the last image column (c0 = 253)
//
// Output address bus:
//   col_addr_bus[23:0] = {bank3_col[5:0],bank2_col[5:0],
//                          bank1_col[5:0],bank0_col[5:0]}   -> 4x6 = 24 bit
//   row_addr[7:0]                                           -> common row
//   bank_en[3:0]                                            -> active banks
// Full per-bank SRAM address (14-bit) = {row_addr, col_addr_bus[bank*6+:6]}
//=====================================================================
module addr_gen #(
    parameter IMG_W  = 256,
    parameter IMG_H  = 256,
    parameter NBANKS = 4,
    parameter BROWS  = 256,   // rows per bank   = IMG_H
    parameter BCOLS  = 64,    // cols per bank   = IMG_W/NBANKS
    parameter WIN    = 3,     // pixels read / cycle
    parameter RW     = 8,     // row  addr width = log2(BROWS)
    parameter CW     = 6      // col  addr width = log2(BCOLS)
)(
    input                        clk,
    input                        rst_n,
    input                        start,        // pulse to (re)start a full scan

    output reg [NBANKS-1:0]      bank_en,       // which banks are read this cycle
    output reg [RW-1:0]          row_addr,      // common row address (broadcast)
    output reg [NBANKS*CW-1:0]   col_addr_bus,  // 24-bit SRAM column-address bus
    output reg                   valid,         // address bus is valid this cycle
    output reg                   done,          // full image scan complete

    // debug / testbench convenience (not required by the SRAM itself)
    output reg [7:0]             col_start_o,
    output reg [7:0]             pix_col0_o,
    output reg [7:0]             pix_col1_o,
    output reg [7:0]             pix_col2_o
);

    localparam LAST_START = IMG_W - WIN;   // 253 : last valid window start

    localparam S_IDLE = 2'd0,
               S_RUN  = 2'd1,
               S_DONE = 2'd2;

    reg [1:0]    state;
    reg [7:0]    col_start;   // window start column, 0..253
    reg [RW-1:0] row_cnt;     // current row,        0..255

    // ---- combinational: which 3 columns / banks / col-addrs for current col_start
    wire [7:0] c0 = col_start;
    wire [7:0] c1 = col_start + 8'd1;
    wire [7:0] c2 = col_start + 8'd2;

    wire [1:0] b0 = c0[1:0];   // bank index = c mod 4
    wire [1:0] b1 = c1[1:0];
    wire [1:0] b2 = c2[1:0];

    wire [CW-1:0] ca0 = c0[7:2];  // column addr = c / 4
    wire [CW-1:0] ca1 = c1[7:2];
    wire [CW-1:0] ca2 = c2[7:2];

    integer j;
    reg [CW-1:0]     col_arr [0:NBANKS-1];
    reg [NBANKS-1:0] en_comb;

    always @(*) begin
	  en_comb = {NBANKS{1'b0}};
        for (j = 0; j < NBANKS; j = j + 1)
            col_arr[j] = {CW{1'b0}};

        // b0,b1,b2 are guaranteed distinct (3 consecutive values mod 4)
        en_comb[b0] = 1'b1;  col_arr[b0] = ca0;
        en_comb[b1] = 1'b1;  col_arr[b1] = ca1;
        en_comb[b2] = 1'b1;  col_arr[b2] = ca2;
    end  
   
    

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            col_start    <= 8'd0;
            row_cnt      <= {RW{1'b0}};
            valid        <= 1'b0;
            done         <= 1'b0;
            bank_en      <= {NBANKS{1'b0}};
            row_addr     <= {RW{1'b0}};
            col_addr_bus <= {(NBANKS*CW){1'b0}};
            col_start_o  <= 8'd0;
            pix_col0_o   <= 8'd0;
            pix_col1_o   <= 8'd0;
            pix_col2_o   <= 8'd0;
        end else begin
            case (state)

            S_IDLE: begin
                valid <= 1'b0;
                done  <= 1'b0;
                if (start) begin
                    col_start <= 8'd0;
                    row_cnt   <= {RW{1'b0}};
                    state     <= S_RUN;
                end
            end

            S_RUN: begin
                // ---- drive the address bus for the CURRENT (col_start,row_cnt)
                bank_en     <= en_comb;
                row_addr    <= row_cnt;
                for (k = 0; k < NBANKS; k = k + 1)
                    col_addr_bus[k*CW +: CW] <= col_arr[k];
                valid       <= 1'b1;

                col_start_o <= col_start;
                pix_col0_o  <= c0;
                pix_col1_o  <= c1;
                pix_col2_o  <= c2;

                // ---- advance counters: row first (inner loop), then column (outer)
                if (row_cnt == BROWS-1) begin
                    row_cnt <= {RW{1'b0}};
                    if (col_start == LAST_START) begin
                        state <= S_DONE;          // whole image scanned
                    end else begin
                        col_start <= col_start + 8'd1;   // stride = 1 pixel
                    end
                end else begin
                    row_cnt <= row_cnt + 1'b1;
                end
            end

            S_DONE: begin
                valid <= 1'b0;
                done  <= 1'b1;
            end

            default: state <= S_IDLE;
            endcase
        end
    end

endmodule
