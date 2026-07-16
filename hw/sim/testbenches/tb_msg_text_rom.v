`timescale 1ns / 1ps
// ============================================================================
// tb_msg_text_rom - checks msg_text_rom against the generated golden bytes.
//
// Proves: for every index 0..17, all 64 bytes of text_out (byte B=line*16+col
// at [B*8 +: 8]) match msg_text_golden.vh; and an out-of-range index yields the
// safe "INDEX ERROR" default. This validates the ROM's bit packing end to end,
// which is the exact order the HPS decode in main.c relies on.
// ============================================================================

module tb_msg_text_rom;

    reg  [4:0]   msg_index;
    wire [511:0] text_out;

    msg_text_rom dut (
        .msg_index (msg_index),
        .text_out  (text_out)
    );

    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num   = 0;

    reg [7:0] golden_text [0:1151];
    integer m, b;
    reg [7:0] got, exp;
    reg msg_ok;

    task check;
        input condition;
        input [255:0] name;
        begin
            test_num = test_num + 1;
            if (!condition) begin
                $display("FAIL Test %0d [%0s] @ %0t", test_num, name, $time);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS Test %0d [%0s]", test_num, name);
                pass_count = pass_count + 1;
            end
        end
    endtask

    reg def_ok;

    initial begin
        `include "msg_text_golden.vh"

        // Per-message byte-exact check (one PASS/FAIL line per message).
        for (m = 0; m < 18; m = m + 1) begin
            msg_index = m[4:0];
            #1;
            msg_ok = 1'b1;
            for (b = 0; b < 64; b = b + 1) begin
                got = text_out[b*8 +: 8];
                exp = golden_text[m*64 + b];
                if (got !== exp) begin
                    msg_ok = 1'b0;
                    $display("  byte mismatch msg %0d byte %0d: got %02h want %02h",
                             m, b, got, exp);
                end
            end
            check(msg_ok, "text bytes match golden");
        end

        // Out-of-range index -> safe default: line 0 begins "INDEX", lines 1-3 blank.
        msg_index = 5'd31;
        #1;
        def_ok = (text_out[0*8 +: 8] == "I") &&
                 (text_out[1*8 +: 8] == "N") &&
                 (text_out[2*8 +: 8] == "D") &&
                 (text_out[3*8 +: 8] == "E") &&
                 (text_out[4*8 +: 8] == "X");
        for (b = 16; b < 64; b = b + 1)
            if (text_out[b*8 +: 8] !== 8'h20) def_ok = 1'b0;
        check(def_ok, "out-of-range default guard");

        $display("=== RESULTS: %0d PASSED, %0d FAILED out of %0d tests ===",
                 pass_count, fail_count, test_num);
        if (fail_count == 0) $display("*** ALL TESTS PASSED ***");
        else                 $display("*** SOME TESTS FAILED ***");
        $finish;
    end

endmodule
