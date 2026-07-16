`timescale 1ns / 1ps
// ============================================================================
// tb_msg_nav_rom - checks msg_nav_rom against the generated golden table.
//
// Proves: all 72 (index, action) vectors match msg_nav_golden.vh; no output is
// ever > 17 (a value that would index past the message set); and KEY3 (action 2)
// jumps to the emergency screen (16) from every index.
// ============================================================================

module tb_msg_nav_rom;

    reg  [4:0] cur_index;
    reg  [1:0] action;
    wire [4:0] next_index;

    msg_nav_rom dut (
        .cur_index  (cur_index),
        .action     (action),
        .next_index (next_index)
    );

    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num   = 0;

    reg [4:0] golden_nav [0:71];
    integer i, a;
    reg [4:0] exp;
    reg range_ok, key3_ok;

    localparam [1:0] ACT_KEY3 = 2'd2;
    localparam [4:0] EMERGENCY = 5'd16;

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

    initial begin
        `include "msg_nav_golden.vh"

        // All 72 vectors match golden, and none exceeds 17.
        range_ok = 1'b1;
        for (i = 0; i < 18; i = i + 1) begin
            for (a = 0; a < 4; a = a + 1) begin
                cur_index = i[4:0];
                action    = a[1:0];
                #1;
                exp = golden_nav[i*4 + a];
                if (next_index !== exp) begin
                    $display("  nav mismatch (idx %0d, act %0d): got %0d want %0d",
                             i, a, next_index, exp);
                    check(1'b0, "nav vector match");
                end
                if (next_index > 5'd17) range_ok = 1'b0;
            end
        end
        // One aggregate PASS for the full-vector sweep if nothing failed above.
        check(fail_count == 0, "all 72 nav vectors match golden");
        check(range_ok, "no next_index exceeds 17");

        // KEY3 -> emergency (16) from every index.
        key3_ok = 1'b1;
        for (i = 0; i < 18; i = i + 1) begin
            cur_index = i[4:0];
            action    = ACT_KEY3;
            #1;
            if (next_index !== EMERGENCY) key3_ok = 1'b0;
        end
        check(key3_ok, "KEY3 reaches emergency from every index");

        $display("=== RESULTS: %0d PASSED, %0d FAILED out of %0d tests ===",
                 pass_count, fail_count, test_num);
        if (fail_count == 0) $display("*** ALL TESTS PASSED ***");
        else                 $display("*** SOME TESTS FAILED ***");
        $finish;
    end

endmodule
