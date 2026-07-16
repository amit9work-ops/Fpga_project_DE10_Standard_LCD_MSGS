`timescale 1ns / 1ps
// ============================================================================
// tb_msg_nav_rom - checks msg_nav_rom against the generated golden table
// (round 2, category-based model).
//
// Proves: all 90 (index, action) vectors match msg_nav_golden.vh; no
// next_index ever exceeds 17; each of the 4 key actions is a FIXED jump
// (identical next_index for every cur_index); the EMERGENCY entry (16)
// sticks to itself on TIMEOUT; every other category's last entry falls
// back to DEFAULT (0) on TIMEOUT; and in_default matches the DEFAULT
// category membership {0,1,2,17} exactly.
// ============================================================================

module tb_msg_nav_rom;

    reg  [4:0] cur_index;
    reg  [2:0] action;
    wire [4:0] next_index;
    wire       in_default;

    msg_nav_rom dut (
        .cur_index  (cur_index),
        .action     (action),
        .next_index (next_index),
        .in_default (in_default)
    );

    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num   = 0;

    reg [4:0] golden_nav [0:89];
    integer i, a;
    reg [4:0] exp;
    reg range_ok, fixed_jump_ok;
    reg [4:0] fixed_target;

    localparam ACT_KEY0    = 3'd0;
    localparam ACT_KEY1    = 3'd1;
    localparam ACT_KEY2    = 3'd2;
    localparam ACT_KEY3    = 3'd3;
    localparam ACT_TIMEOUT = 3'd4;

    localparam [4:0] EXERCISE_HEAD  = 5'd3;
    localparam [4:0] SESSION_HEAD   = 5'd8;
    localparam [4:0] EMERGENCY_HEAD = 5'd16;
    localparam [4:0] DEFAULT_HEAD   = 5'd0;

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

        // All 90 vectors match golden, and none exceeds 17.
        range_ok = 1'b1;
        for (i = 0; i < 18; i = i + 1) begin
            for (a = 0; a < 5; a = a + 1) begin
                cur_index = i[4:0];
                action    = a[2:0];
                #1;
                exp = golden_nav[i*5 + a];
                if (next_index !== exp) begin
                    $display("  nav mismatch (idx %0d, act %0d): got %0d want %0d",
                             i, a, next_index, exp);
                    check(1'b0, "nav vector match");
                end
                if (next_index > 5'd17) range_ok = 1'b0;
            end
        end
        check(fail_count == 0, "all 90 nav vectors match golden");
        check(range_ok, "no next_index exceeds 17");

        // Each key action is a fixed jump: identical target for every cur_index.
        fixed_jump_ok = 1'b1;
        action = ACT_KEY0;
        cur_index = 5'd0; #1; fixed_target = next_index;
        for (i = 1; i < 18; i = i + 1) begin
            cur_index = i[4:0]; #1;
            if (next_index !== fixed_target) fixed_jump_ok = 1'b0;
        end
        check(fixed_jump_ok && (fixed_target == EXERCISE_HEAD), "KEY0 fixed jump to EXERCISE head (3)");

        fixed_jump_ok = 1'b1;
        action = ACT_KEY1;
        cur_index = 5'd0; #1; fixed_target = next_index;
        for (i = 1; i < 18; i = i + 1) begin
            cur_index = i[4:0]; #1;
            if (next_index !== fixed_target) fixed_jump_ok = 1'b0;
        end
        check(fixed_jump_ok && (fixed_target == SESSION_HEAD), "KEY1 fixed jump to SESSION head (8)");

        fixed_jump_ok = 1'b1;
        action = ACT_KEY2;
        cur_index = 5'd0; #1; fixed_target = next_index;
        for (i = 1; i < 18; i = i + 1) begin
            cur_index = i[4:0]; #1;
            if (next_index !== fixed_target) fixed_jump_ok = 1'b0;
        end
        check(fixed_jump_ok && (fixed_target == EMERGENCY_HEAD), "KEY2 fixed jump to EMERGENCY head (16)");

        fixed_jump_ok = 1'b1;
        action = ACT_KEY3;
        cur_index = 5'd0; #1; fixed_target = next_index;
        for (i = 1; i < 18; i = i + 1) begin
            cur_index = i[4:0]; #1;
            if (next_index !== fixed_target) fixed_jump_ok = 1'b0;
        end
        check(fixed_jump_ok && (fixed_target == DEFAULT_HEAD), "KEY3 fixed jump to DEFAULT head (0)");

        // Emergency's entry (16) sticks to itself on TIMEOUT.
        cur_index = 5'd16; action = ACT_TIMEOUT; #1;
        check(next_index === 5'd16, "Emergency (16) is sticky on TIMEOUT");

        // Every non-emergency category's LAST entry times out to Default (0).
        cur_index = 5'd17; action = ACT_TIMEOUT; #1;  // DEFAULT's last entry
        check(next_index === 5'd0, "DEFAULT last entry (17) times out to 0");
        cur_index = 5'd7;  action = ACT_TIMEOUT; #1;  // EXERCISE's last entry
        check(next_index === 5'd0, "EXERCISE last entry (7) times out to 0");
        cur_index = 5'd15; action = ACT_TIMEOUT; #1;  // SESSION's last entry
        check(next_index === 5'd0, "SESSION last entry (15) times out to 0");

        // in_default matches {0,1,2,17} exactly, and only those.
        for (i = 0; i < 18; i = i + 1) begin
            cur_index = i[4:0]; action = ACT_TIMEOUT; #1;
            if (i == 0 || i == 1 || i == 2 || i == 17) begin
                check(in_default === 1'b1, "in_default true for DEFAULT member");
            end else begin
                check(in_default === 1'b0, "in_default false for non-DEFAULT member");
            end
        end

        $display("=== RESULTS: %0d PASSED, %0d FAILED out of %0d tests ===",
                 pass_count, fail_count, test_num);
        if (fail_count == 0) $display("*** ALL TESTS PASSED ***");
        else                 $display("*** SOME TESTS FAILED ***");
        $finish;
    end

endmodule
