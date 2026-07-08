// ============================================================================
// Testbench: tb_top_level
// Project: DE10-Standard LCD Message System
// Description: Standalone top-level verification for hw/rtl/top_level.v.
//              Uses defparam overrides on the internal fpga_msg_controller
//              instance to keep simulation runtime practical.
// ============================================================================

`timescale 1ns / 1ps

module tb_top_level;

    localparam CLK_PERIOD_NS = 1_000_000; // 1 kHz for fast simulation

    reg        CLOCK_50;
    reg [3:0]  KEY;
    wire [6:0] HEX0;
    wire [6:0] HEX1;
    wire [6:0] HEX2;
    wire [6:0] HEX3;
    wire [6:0] HEX4;
    wire [6:0] HEX5;
    wire [9:0] LEDR;

    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num   = 0;

    top_level dut (
        .CLOCK_50(CLOCK_50),
        .KEY(KEY),
        .HEX0(HEX0),
        .HEX1(HEX1),
        .HEX2(HEX2),
        .HEX3(HEX3),
        .HEX4(HEX4),
        .HEX5(HEX5),
        .LEDR(LEDR)
    );

    // Fast simulation overrides for internal controller instance.
    // TIMEOUT_SEC=13 (rather than a single-digit value) deliberately
    // exercises the widened seconds_remaining / HEX tens-digit division
    // logic (13/10=1, 13%10=3) — a single-digit override would never
    // catch a tens-digit regression.
    defparam dut.u_ctrl.CLK_FREQ_HZ = 1000;
    defparam dut.u_ctrl.DEBOUNCE_MS = 1;
    defparam dut.u_ctrl.TIMEOUT_SEC = 13;

    function [6:0] seven_seg;
        input [3:0] val;
        begin
            case (val)
                4'h0: seven_seg = 7'b1000000;
                4'h1: seven_seg = 7'b1111001;
                4'h2: seven_seg = 7'b0100100;
                4'h3: seven_seg = 7'b0110000;
                4'h4: seven_seg = 7'b0011001;
                4'h5: seven_seg = 7'b0010010;
                4'h6: seven_seg = 7'b0000010;
                4'h7: seven_seg = 7'b1111000;
                4'h8: seven_seg = 7'b0000000;
                4'h9: seven_seg = 7'b0010000;
                4'hA: seven_seg = 7'b0001000;
                4'hB: seven_seg = 7'b0000011;
                4'hC: seven_seg = 7'b1000110;
                4'hD: seven_seg = 7'b0100001;
                4'hE: seven_seg = 7'b0000110;
                4'hF: seven_seg = 7'b0001110;
                default: seven_seg = 7'b1111111;
            endcase
        end
    endfunction

    task check;
        input condition;
        input [255:0] name;
        begin
            test_num = test_num + 1;
            if (!condition) begin
                $display("FAIL Test %0d [%0s] @ %0t", test_num, name, $time);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS Test %0d [%0s] @ %0t", test_num, name, $time);
                pass_count = pass_count + 1;
            end
        end
    endtask

    initial CLOCK_50 = 1'b0;
    always #(CLK_PERIOD_NS/2) CLOCK_50 = ~CLOCK_50;

    initial begin
        $display("=== TB: top_level ===");

        // KEY are active-LOW: KEY[0]=reset
        KEY = 4'b1111;
        KEY[0] = 1'b0;
        repeat (5) @(posedge CLOCK_50);
        KEY[0] = 1'b1;
        repeat (2) @(posedge CLOCK_50);

        check(LEDR[4] == 1'b0, "Init timeout LED low");
        check(LEDR[3:0] == 4'b0000, "Init debounced LEDs low");
        check(HEX2 == seven_seg(4'hF), "Init HEX2 shows F");
        check(HEX5 == seven_seg(4'd1), "Init HEX5 shows timer tens");
        check(HEX4 == seven_seg(4'd3), "Init HEX4 shows timer ones");

        // Press KEY1 (bit1)
        KEY[1] = 1'b0;
        repeat (1010) @(posedge CLOCK_50);
        check(LEDR[1] == 1'b1, "KEY1 debounced reflected on LEDR[1]");
        check(HEX2 == seven_seg(4'd1), "HEX2 tracks last button KEY1");

        KEY[1] = 1'b1;
        repeat (1010) @(posedge CLOCK_50);
        check(LEDR[1] == 1'b0, "KEY1 release reflected on LEDR[1]");

        // Wait for timeout (TIMEOUT_SEC seconds with fast params — this
        // margin is a safe upper bound regardless of the exact remaining
        // countdown value at this point)
        repeat (13*1000 + 20) @(posedge CLOCK_50);
        check(LEDR[4] == 1'b1, "Timeout LED asserted");
        check(HEX5 == seven_seg(4'd0), "HEX5 shows timer tens zero on timeout");
        check(HEX4 == seven_seg(4'd0), "HEX4 shows timer ones zero on timeout");

        // Press KEY2 to reset timer and update last-button indicator
        KEY[2] = 1'b0;
        repeat (1010) @(posedge CLOCK_50);
        check(LEDR[4] == 1'b0, "Timeout cleared by key press");
        check(HEX2 == seven_seg(4'd2), "HEX2 tracks last button KEY2");

        KEY[2] = 1'b1;
        repeat (1010) @(posedge CLOCK_50);

        check(HEX0 == seven_seg(4'h0), "HEX0 reserved zero");
        check(HEX1 == seven_seg(4'h0), "HEX1 reserved zero");
        check(HEX3 == seven_seg(4'h0), "HEX3 reserved zero");
        check(HEX5 == seven_seg(4'd1), "HEX5 timer tens digit");

        $display("");
        $display("=== RESULTS: %0d PASSED, %0d FAILED out of %0d tests ===",
                 pass_count, fail_count, test_num);
        if (fail_count == 0)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** SOME TESTS FAILED ***");

        $finish;
    end

    initial begin
        $dumpfile("tb_top_level.vcd");
        $dumpvars(0, tb_top_level);
    end

endmodule
