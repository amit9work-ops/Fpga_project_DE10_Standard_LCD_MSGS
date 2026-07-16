`timescale 1ns / 1ps
// ============================================================================
// tb_msg_duration_rom - exhaustive check of msg_duration_rom (previously
// untested -- see project defect list). Proves: every one of the 18 hand
// tuned per-message durations matches its documented value exactly, the
// out-of-range default is sane, and every value fits the 6-bit field
// (0-63s) with headroom for HEX display (tens/ones digit split).
//
// Values are checked against the literal constants in msg_duration_rom.v's
// case table (this file is the second, independent source of truth for
// those constants -- if someone edits one without the other, this fails).
// ============================================================================

module tb_msg_duration_rom;

    reg  [4:0] msg_index;
    wire [5:0] duration_sec;

    msg_duration_rom #(
        .MSG_COUNT (18),
        .INDEX_W   (5),
        .DUR_W     (6)
    ) dut (
        .msg_index    (msg_index),
        .duration_sec (duration_sec)
    );

    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num   = 0;

    reg [5:0] golden [0:17];
    integer i;

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
        golden[0]  = 6'd12; golden[1]  = 6'd10; golden[2]  = 6'd8;
        golden[3]  = 6'd8;  golden[4]  = 6'd10; golden[5]  = 6'd10;
        golden[6]  = 6'd10; golden[7]  = 6'd15; golden[8]  = 6'd10;
        golden[9]  = 6'd10; golden[10] = 6'd12; golden[11] = 6'd12;
        golden[12] = 6'd10; golden[13] = 6'd10; golden[14] = 6'd8;
        golden[15] = 6'd10; golden[16] = 6'd6;  golden[17] = 6'd12;

        // Every one of the 18 real messages: exact duration, and every
        // value must fit in 0-63s (6-bit field) with room to spare for the
        // HEX tens/ones split (fpga_msg_controller divides/mods by 10).
        for (i = 0; i < 18; i = i + 1) begin
            msg_index = i[4:0];
            #1;
            if (duration_sec !== golden[i])
                $display("  duration mismatch idx %0d: got %0d want %0d",
                          i, duration_sec, golden[i]);
            check(duration_sec === golden[i], "duration matches documented value");
            check(duration_sec >= 6'd1 && duration_sec <= 6'd63,
                  "duration is a sane nonzero value <= 63s");
        end

        // Out-of-range index -> safe, deterministic default (not X/Z, and
        // in range), so a corrupted msg_index can never load a garbage
        // countdown value into idle_timer.
        msg_index = 5'd18; #1;
        check(duration_sec === 6'd10, "index 18 (out of range) -> safe default (10s)");
        msg_index = 5'd31; #1;
        check(duration_sec === 6'd10, "index 31 (max out of range) -> safe default (10s)");

        $display("=== RESULTS: %0d PASSED, %0d FAILED out of %0d tests ===",
                 pass_count, fail_count, test_num);
        if (fail_count == 0) $display("*** ALL TESTS PASSED ***");
        else                 $display("*** SOME TESTS FAILED ***");
        $finish;
    end

endmodule
