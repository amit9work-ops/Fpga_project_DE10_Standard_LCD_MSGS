`timescale 1ns / 1ps
// ============================================================================
// tb_fpga_msg_controller_sleep_collision
//
// Regression test for two bugs found and fixed while auditing
// fpga_msg_controller.v's two-timer sleep logic:
//
//   Bug 1 (dropped sleep pulse): the per-message duration timer and the
//   system-idle (sleep) timer are phase-locked to the same 1-second grid
//   once reloaded together, so their expiries CAN land on the identical
//   clock cycle while parked in DEFAULT. message_fsm's priority ladder
//   deliberately lets msg_timeout win that cycle -- but the original code
//   fed sleep_timeout_flag from a one-shot edge-pulse, which was silently
//   dropped on the losing cycle and never reissued (the sleep timer's
//   reset_timer only re-arms on a button press or on freshly *arriving* at
//   DEFAULT -- neither happens while auto-cycling within DEFAULT).
//   Result: sleep would never fire again for the rest of that dwell.
//
//   Bug 2 (wake bounce-back): the level-based fix for Bug 1 introduced a
//   second bug -- the stale-high level survives 1-2 cycles after waking
//   from S_SLEEP (until the deferred any_btn_pulse_d-driven reload clears
//   it), during which S_MSG's ladder would see it still asserted and
//   bounce straight back into S_SLEEP. Fixed by masking with in_default,
//   which drops the same cycle msg_index leaves DEFAULT.
//
// This testbench forces the exact-tick collision *through the real
// mechanism*, not by forcing internal signals: TIMEOUT_SEC is deliberately
// set to 12, matching msg_duration_rom[0]'s real 12s duration. Both timers
// reload together for free at reset release (msg_index=0 -> msg timer
// loads 12s; in_default=1 from index 0 -> sleep timer, enabled, also loads
// its 12s TIMEOUT_SEC) -- so with no button presses at all, both timers
// are phase-locked from t=0 and their first expiries coincide exactly at
// t=12s, no forcing required.
// ============================================================================

module tb_fpga_msg_controller_sleep_collision;

    localparam CLK_FREQ_HZ = 1000;
    localparam DEBOUNCE_MS = 1;
    localparam TIMEOUT_SEC = 12;   // == msg_duration_rom[0] -- forces the collision
    localparam NUM_BUTTONS = 4;
    localparam CLK_PERIOD  = 1_000_000;  // 1 ms in ns (1 kHz)

    reg                    clk;
    reg                    rst_n;
    reg  [NUM_BUTTONS-1:0] key_in;

    wire [NUM_BUTTONS-1:0] btn_pulse;
    wire [NUM_BUTTONS-1:0] btn_debounced;
    wire                   timeout_flag;
    wire [5:0]             seconds_remaining;
    wire [2:0]             fsm_state;
    wire [4:0]             fsm_msg_index;
    wire [511:0]           msg_text_bus;
    wire [7:0]             msg_text_status;
    wire [6:0]             hex0, hex1, hex2, hex3, hex4, hex5;

    localparam [2:0] S_INIT  = 3'd0;
    localparam [2:0] S_MSG   = 3'd1;
    localparam [2:0] S_SLEEP = 3'd2;

    fpga_msg_controller #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .DEBOUNCE_MS (DEBOUNCE_MS),
        .TIMEOUT_SEC (TIMEOUT_SEC),
        .NUM_BUTTONS (NUM_BUTTONS)
    ) dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .key_in            (key_in),
        .btn_pulse         (btn_pulse),
        .btn_debounced     (btn_debounced),
        .timeout_flag      (timeout_flag),
        .seconds_remaining (seconds_remaining),
        .fsm_state         (fsm_state),
        .fsm_msg_index     (fsm_msg_index),
        .msg_text_bus      (msg_text_bus),
        .msg_text_status   (msg_text_status),
        .hex0              (hex0),
        .hex1              (hex1),
        .hex2              (hex2),
        .hex3              (hex3),
        .hex4              (hex4),
        .hex5              (hex5)
    );

    initial clk = 0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num   = 0;

    task check_bool;
        input actual;
        input expected;
        input [255:0] test_name;
        begin
            test_num = test_num + 1;
            if (actual !== expected) begin
                $display("FAIL Test %0d [%0s]: actual=%b expected=%b at %0t",
                         test_num, test_name, actual, expected, $time);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS Test %0d [%0s] at %0t",
                         test_num, test_name, $time);
                pass_count = pass_count + 1;
            end
        end
    endtask

    initial begin
        $display("=== TB: fpga_msg_controller sleep/msg-timer collision regression ===");
        $display("CLK=%0d Hz, TIMEOUT_SEC=%0d (matches msg_duration_rom[0])",
                 CLK_FREQ_HZ, TIMEOUT_SEC);
        $dumpfile("tb_fpga_msg_controller_sleep_collision.vcd");
        $dumpvars(0, tb_fpga_msg_controller_sleep_collision);

        key_in = 4'b1111;  // all released (active-LOW)
        rst_n  = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Sanity: parked at DEFAULT head (0), msg timer loaded with 12s --
        // both timers are now phase-locked from this exact reset release.
        check_bool(fsm_state == S_MSG, 1'b1, "Post-reset: in MSG");
        check_bool(fsm_msg_index == 5'd0, 1'b1, "Post-reset: at DEFAULT head (0)");
        check_bool(seconds_remaining == 6'd12, 1'b1, "Post-reset: msg timer loaded 12s");

        // ============================================================
        // Run out to just before the collision (12s - 5 ticks), confirm
        // nothing has fired yet, then poll cycle-by-cycle across the
        // collision instead of guessing an exact offset -- idle_timer's
        // internal tick/second-boundary arithmetic makes the precise
        // absolute cycle a fragile thing to hand-compute, and the
        // property under test (the ORDER of events) doesn't need it.
        // ============================================================
        repeat (TIMEOUT_SEC * CLK_FREQ_HZ - 5) @(posedge clk);
        check_bool(fsm_state == S_MSG, 1'b1, "Just before t=12s: still MSG");
        check_bool(fsm_msg_index == 5'd0, 1'b1, "Just before t=12s: still at index 0");

        // Poll forward until the index leaves 0 -- this IS the collision
        // tick (msg_timeout's TIMEOUT action firing), whichever exact
        // cycle it lands on.
        begin : wait_for_collision
            integer guard;
            guard = 0;
            while (fsm_msg_index == 5'd0 && guard < 20) begin
                @(posedge clk);
                guard = guard + 1;
            end
            check_bool(guard < 20, 1'b1, "Collision: index left 0 within the expected window");
        end

        // ============================================================
        // TEST: at the collision, msg_timeout wins -- index advances
        // within DEFAULT (0->1) rather than the FSM ignoring it or
        // jumping straight to SLEEP without advancing first. Checked on
        // the EXACT cycle the index changed (no offset guessing), so a
        // regression that skips this and jumps straight to SLEEP (losing
        // the message advance) is caught, not just a regression that
        // drops sleep entirely.
        // ============================================================
        check_bool(fsm_state == S_MSG, 1'b1,
                   "Collision: msg_timeout wins this tick, stays MSG");
        check_bool(fsm_msg_index == 5'd1, 1'b1,
                   "Collision: msg_timeout advanced DEFAULT 0->1 (not stuck, not skipped)");

        // ============================================================
        // TEST (Bug 1 regression): the sleep expiry must NOT be lost.
        // With the fix, sleep_timeout_flag is a level masked by
        // in_default, so it survives the losing cycle and is consumed
        // on the very next idle cycle. Poll forward with a small bounded
        // window (not "wait forever") -- if this ever regresses to the
        // dropped-pulse bug, the FSM will still be sitting in MSG cycling
        // through DEFAULT messages instead of sleeping, and this will
        // time out and fail rather than hang.
        // ============================================================
        begin : wait_for_sleep
            integer guard;
            guard = 0;
            while (fsm_state != S_SLEEP && guard < 20) begin
                @(posedge clk);
                guard = guard + 1;
            end
            check_bool(guard < 20, 1'b1,
                       "Bug 1 regression: sleep still fires shortly after the collision (not lost)");
        end
        check_bool(fsm_state == S_SLEEP, 1'b1, "Confirmed parked in SLEEP after the collision");

        // ============================================================
        // TEST (Bug 2 regression): waking from SLEEP into a non-DEFAULT
        // category must NOT bounce back into SLEEP. Check immediately
        // after wake and again a few cycles later -- Bug 2 was a
        // transient bounce visible only in the first 1-2 cycles, which
        // a single check long after wake (as the main integration TB
        // does) would not have caught.
        // ============================================================
        key_in[1] = 1'b0;  // KEY1 -> SESSION head (8)
        repeat (1010) @(posedge clk);  // debounce settle
        check_bool(fsm_state == S_MSG, 1'b1, "Wake: KEY1 wakes SLEEP -> MSG directly");
        check_bool(fsm_msg_index == 5'd8, 1'b1, "Wake: jumps straight to SESSION head (8)");

        // Narrow-window checks: the exact cycles Bug 2 lived in.
        repeat (1) @(posedge clk);
        check_bool(fsm_state == S_MSG, 1'b1,
                   "Bug 2 regression: still MSG 1 cycle after wake (no bounce-back)");
        repeat (1) @(posedge clk);
        check_bool(fsm_state == S_MSG, 1'b1,
                   "Bug 2 regression: still MSG 2 cycles after wake (no bounce-back)");
        repeat (5) @(posedge clk);
        check_bool(fsm_state == S_MSG, 1'b1,
                   "Bug 2 regression: still MSG several cycles after wake");
        check_bool(fsm_msg_index == 5'd8, 1'b1,
                   "Bug 2 regression: index held at SESSION head, no spurious re-jump");

        key_in[1] = 1'b1;
        repeat (10) @(posedge clk);

        $display("");
        $display("=== RESULTS: %0d PASSED, %0d FAILED out of %0d tests ===",
                 pass_count, fail_count, test_num);
        if (fail_count == 0)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** SOME TESTS FAILED ***");

        $finish;
    end

    // Safety window: the collision wait alone is ~12,000 cycles; give
    // generous headroom above the ~13,100 cycles the scripted stimulus
    // above actually needs.
    initial begin
        repeat (30000) @(posedge clk);
        $display("FAIL [TIMEOUT] sleep-collision TB exceeded safety window");
        $finish;
    end

endmodule
