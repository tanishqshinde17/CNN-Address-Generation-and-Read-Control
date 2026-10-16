`timescale 1ns/1ps
//=====================================================================
// P2tb_cnn_conv_top : self-checking testbench for cnn_conv_top
//
//  - Preloads the 4 SRAM banks with pixel(r,c) = (r+c) & 0xFF
//  - Loads a 3x3 Sobel-X kernel through the weight port
//  - Runs the full 256x256 scan
//  - For every conv_out_valid cycle, independently recomputes the
//    expected 3x3 convolution (same image formula + same kernel) and
//    compares (row,col,data) against the DUT's streamed result AND
//    against an independently-incremented expected (row,col) sequence
//  - Reports total result count (expect 254*254 = 64516) and PASS/FAIL
//=====================================================================

`include "P2cnn_conv_top.v"
`include "P2conv_engine.v"
`include "P2out_mem.v"
`include "cnn_l1_read_top.v"
`include "addr_gen.v"
`include "sram_bank.v"

module P2tb_cnn_conv_top;

    localparam IMG_W = 256, IMG_H = 256;
    localparam OUT_W = 254, OUT_H = 254;
    localparam EXPECT_RESULTS = OUT_W * OUT_H;   // 64516

    reg clk, rst_n, start;
    reg wt_wr_en;
    reg [3:0] wt_addr;
    reg signed [7:0] wt_data;

    wire scan_done;
    wire conv_out_valid;
    wire [7:0] conv_out_row, conv_out_col;
    wire signed [23:0] conv_out_data;

    reg om_re; reg [15:0] om_raddr; wire signed [23:0] om_rdata;

    integer r, c, bank, coladdr, addr;
    integer errors, results;

    P2cnn_conv_top dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .wt_wr_en(wt_wr_en), .wt_addr(wt_addr), .wt_data(wt_data),
        .scan_done(scan_done),
        .conv_out_valid(conv_out_valid),
        .conv_out_row(conv_out_row), .conv_out_col(conv_out_col), .conv_out_data(conv_out_data),
        .om_re(om_re), .om_raddr(om_raddr), .om_rdata(om_rdata)
    );

    // ---- clock ----
    initial clk = 0;
    always #5 clk = ~clk;

    // ---- test image (must match preload) ----
    function signed [7:0] exp_pix(input integer rr, input integer cc);
        exp_pix = (rr[7:0] + cc[7:0]) & 8'hFF;
    endfunction

    // ---- reference kernel (Sobel-X), same values loaded via wt port ----
    reg signed [7:0] kernel_ref [0:8];
    initial begin
        kernel_ref[0]= 8'sd1;  kernel_ref[1]= 8'sd0;  kernel_ref[2]=-8'sd1;
        kernel_ref[3]= 8'sd2;  kernel_ref[4]= 8'sd0;  kernel_ref[5]=-8'sd2;
        kernel_ref[6]= 8'sd1;  kernel_ref[7]= 8'sd0;  kernel_ref[8]=-8'sd1;
    end

    // ---- golden 3x3 convolution reference (top-left of window = orow,ocol) ----
    function signed [23:0] conv_ref(input integer orow, input integer ocol);
        integer i, j;
        reg signed [23:0] s;
        reg [7:0] pv;
        begin
            s = 0;
            for (i = 0; i < 3; i = i + 1)
                for (j = 0; j < 3; j = j + 1) begin
                    pv = exp_pix(orow + i, ocol + j);
                   // s  = s + ((pv) * kernel_ref[i*3 + j]);
		      s  = s + ($signed({1'b0, pv}) * kernel_ref[i*3 + j]);

                end
            conv_ref = s[23:0];
        end
    endfunction

    // ---- preload the 4 banks (same scheme as before) ----
    task preload_image;
        begin
            for (r = 0; r < IMG_H; r = r + 1) begin
                for (c = 0; c < IMG_W; c = c + 1) begin
                    bank    = c % 4;
                    coladdr = c >> 2;
                    addr    = (r * 64) + coladdr; 
                    case (bank)
                        0: dut.u_read.BANKS[0].u_bank.mem[addr] = exp_pix(r, c);
                        1: dut.u_read.BANKS[1].u_bank.mem[addr] = exp_pix(r, c);
                        2: dut.u_read.BANKS[2].u_bank.mem[addr] = exp_pix(r, c);
                        3: dut.u_read.BANKS[3].u_bank.mem[addr] = exp_pix(r, c);
                    endcase
                end
            end
            $display("[%0t] Image preload complete", $time);
        end
    endtask

    // ---- load the 9 kernel weights through the weight port ----
    task load_weights;
        integer k;
        begin
            wt_wr_en = 0; wt_addr = 0; wt_data = 0;
            @(posedge clk);
            for (k = 0; k < 9; k = k + 1) begin
                wt_wr_en = 1;
                wt_addr  = k[3:0];
                wt_data  = kernel_ref[k];
                @(posedge clk);
            end
            wt_wr_en = 0;
            $display("[%0t] Weight load complete (Sobel-X)", $time);
        end
    endtask

    // ---- independent expected (row,col) sequence : outer=col, inner=row ----
    integer exp_row, exp_col;

    // ---- stimulus ----
    initial begin
        rst_n = 0; start = 0; om_re = 0; om_raddr = 0;
        errors = 0; results = 0;
        exp_row = 0; exp_col = 0;

        preload_image;

        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        load_weights;

        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
    end

    // ---- checker : sample every conv_out_valid cycle ----
    reg signed [23:0] exp_data;
    always @(posedge clk) begin
        if (rst_n && conv_out_valid) begin
            results = results + 1;

            exp_data = conv_ref(exp_row, exp_col);

            if (conv_out_row !== exp_row[7:0] || conv_out_col !== exp_col[7:0]) begin
                errors = errors + 1;
                $display("[%0t] ERROR index: exp=(%0d,%0d) got=(%0d,%0d)",
                          $time, exp_row, exp_col, conv_out_row, conv_out_col);
            end

            if (conv_out_data !== exp_data) begin
                errors = errors + 1;
                $display("[%0t] ERROR data @ (row=%0d,col=%0d): exp=%0d got=%0d",
                          $time, exp_row, exp_col, exp_data, conv_out_data);
            end

            if (results <= 5 || results >= EXPECT_RESULTS-2)
                $display("[res %0d] row=%0d col=%0d -> conv=%0d (exp=%0d)",
                          results, conv_out_row, conv_out_col, conv_out_data, exp_data);

            // advance independent expected-index counters: row inner, col outer
            if (exp_row == OUT_H-1) begin
                exp_row = 0;
                exp_col = exp_col + 1;
            end else begin
                exp_row = exp_row + 1;
            end
        end
    end

    // ---- finish : wait a couple cycles after scan_done for the pipeline to drain ----
    initial begin
        wait (scan_done === 1'b1);
        repeat (4) @(posedge clk);

        // spot-check final memory contents via the readback port
        om_re = 1; om_raddr = 0;
        @(posedge clk);
        $display("out_mem[0] (row0,col0) = %0d (exp %0d)", om_rdata, conv_ref(0,0));
        om_raddr = EXPECT_RESULTS-1;
        @(posedge clk);
        $display("out_mem[last] (row253,col253) = %0d (exp %0d)", om_rdata, conv_ref(253,253));

        $display("--------------------------------------------------");
        $display("Total conv results observed : %0d (expected %0d)", results, EXPECT_RESULTS);
        $display("Errors                      : %0d", errors);
        if (errors == 0 && results == EXPECT_RESULTS)
            $display(">>>>>> TEST PASSED <<<<<<");
        else
            $display(">>>>>> TEST FAILED <<<<<<");
        $display("--------------------------------------------------");
        #20 $finish;
    end

    // safety timeout
    initial begin
        #20_000_000;
        $display("TIMEOUT - simulation did not finish");
        $finish;
    end

endmodule
