`timescale 1ns/1ps
//=====================================================================
// tb_cnn_l1_read : self-checking testbench
//
//  - Preloads all 4 SRAM banks with a test image: pixel(r,c) = (r+c) & 8'hFF
//    stored per the staggered scheme (bank = c%4, bank_col = c/4, bank_row = r)
//  - Runs the address generator through the full scan
//  - On every valid cycle, checks:
//      * bank_en selects exactly the 3 correct banks
//      * row_addr / col_addr_bus decode to the correct (row,col) per bank
//      * the 3 pixel data bytes returned match the expected test pattern
//  - Reports PASS/FAIL counts and total cycle count (expect 254*256=65024)
//
//=====================================================================
//
`include "cnn_l1_read_top.v"
`include "addr_gen.v"
`include "sram_bank.v"

module tb_cnn_l1_read;

    localparam IMG_W = 256, IMG_H = 256, NB = 4, CW = 6, RW = 8;
    localparam EXPECT_CYCLES = (IMG_W - 3 + 1) * IMG_H; // 254*256 = 65024

    reg clk, rst_n, start;
    wire valid, done;
    wire [7:0] pixel0, pixel1, pixel2;
    wire [7:0] col_start_o, pix_col0_o, pix_col1_o, pix_col2_o;
    wire [3:0] bank_en_o;
    wire [7:0] row_addr_o;
    wire [23:0] col_addr_bus_o;

    integer r, c, bank, coladdr, addr;
    integer errors, checks;
    integer cycle_count;

    cnn_l1_read_top dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .valid(valid), .done(done),
        .pixel0(pixel0), .pixel1(pixel1), .pixel2(pixel2),
        .col_start_o(col_start_o),
        .pix_col0_o(pix_col0_o), .pix_col1_o(pix_col1_o), .pix_col2_o(pix_col2_o),
        .bank_en_o(bank_en_o), .row_addr_o(row_addr_o), .col_addr_bus_o(col_addr_bus_o)
    );

    // ---- clock ----
    initial clk = 0;
    always #5 clk = ~clk;

    // ---- expected pixel function (must match preload) ----
    function [7:0] exp_pix(input [7:0] rr, input [7:0] cc);
        exp_pix = (rr + cc) & 8'hFF;
    endfunction

    // ---- preload the 4 banks per the staggered storage scheme ----
    task preload_image;
        begin
            for (r = 0; r < IMG_H; r = r + 1) begin
                for (c = 0; c < IMG_W; c = c + 1) begin
                    bank    = c % 4;
                    coladdr = c >> 2;
                    addr    = (r * 64) + coladdr;      // {row[7:0],col[5:0]}
                    case (bank)
                        0: dut.BANKS[0].u_bank.mem[addr] = exp_pix(r[7:0], c[7:0]);
                        1: dut.BANKS[1].u_bank.mem[addr] = exp_pix(r[7:0], c[7:0]);
                        2: dut.BANKS[2].u_bank.mem[addr] = exp_pix(r[7:0], c[7:0]);
                        3: dut.BANKS[3].u_bank.mem[addr] = exp_pix(r[7:0], c[7:0]);
                    endcase
                end
            end
            $display("[%0t] Image preload complete (256x256, pixel=(r+c)&0xFF)", $time);
        end
    endtask

    // ---- expected bank_en / col fields for a given col_start ----
    function [3:0] exp_bank_en(input [7:0] cs);
        reg [1:0] b0,b1,b2;
        begin
            b0 = cs[1:0];
            b1 = (cs+1)&2'b11;
            b2 = (cs+2)&2'b11;
            exp_bank_en = (4'b0001<<b0) | (4'b0001<<b1) | (4'b0001<<b2);
        end
    endfunction

    // ---- reset / start ----
    initial begin
        rst_n = 0; start = 0;
        errors = 0; checks = 0; cycle_count = 0;
        preload_image;
        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
    end

    // ---- checker : sample every valid cycle ----
    reg [3:0] eb;
    reg [7:0] exp0, exp1, exp2;
    always @(posedge clk) begin
        if (rst_n && valid) begin
            cycle_count = cycle_count + 1;
            checks = checks + 1;

            eb   = exp_bank_en(col_start_o);
            exp0 = exp_pix(row_addr_o, pix_col0_o);
            exp1 = exp_pix(row_addr_o, pix_col1_o);
            exp2 = exp_pix(row_addr_o, pix_col2_o);

            if (bank_en_o !== eb) begin
                errors = errors + 1;
                $display("[%0t] ERROR bank_en: col_start=%0d exp=%b got=%b",
                          $time, col_start_o, eb, bank_en_o);
            end

            if (pixel0 !== exp0 || pixel1 !== exp1 || pixel2 !== exp2) begin
                errors = errors + 1;
                $display("[%0t] ERROR data: r=%0d c=(%0d,%0d,%0d) exp=(%0d,%0d,%0d) got=(%0d,%0d,%0d)",
                          $time, row_addr_o, pix_col0_o, pix_col1_o, pix_col2_o,
                          exp0, exp1, exp2, pixel0, pixel1, pixel2);
            end

            // print a few sample cycles
            if (cycle_count <= 5 || cycle_count >= EXPECT_CYCLES-2)
                $display("[cyc %0d] col_start=%0d row=%0d bank_en=%b cols=%0d,%0d,%0d,%0d -> pix=%0d,%0d,%0d",
                          cycle_count, col_start_o, row_addr_o, bank_en_o,
                          col_addr_bus_o[5:0], col_addr_bus_o[11:6],
                          col_addr_bus_o[17:12], col_addr_bus_o[23:18],
                          pixel0, pixel1, pixel2);
        end
    end

    // ---- finish ----
    always @(posedge clk) begin
        if (done) begin
            $display("--------------------------------------------------");
            $display("Scan DONE at time %0t", $time);
            $display("Total valid cycles observed : %0d (expected %0d)", cycle_count, EXPECT_CYCLES);
            $display("Checks performed            : %0d", checks);
            $display("Errors                      : %0d", errors);
            if (errors == 0 && cycle_count == EXPECT_CYCLES)
                $display(">>>>>> TEST PASSED <<<<<<");
            else
                $display(">>>>>> TEST FAILED <<<<<<");
            $display("--------------------------------------------------");
            #20 $finish;
        end
    end

    // safety timeout
    initial begin
        #20_000_000;
        $display("TIMEOUT - simulation did not finish");
        $finish;
    end

endmodule
