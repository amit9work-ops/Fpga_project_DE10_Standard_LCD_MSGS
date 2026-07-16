// ============================================================================
// Testbench: tb_fpga_msg_controller (round 2, category-based navigation)
// Project: DE10-Standard LCD Message System
// Description: Full integration testbench for fpga_msg_controller.
//              Stimulates KEY inputs and verifies:
//              - btn_debounced outputs after debounce settling
//              - btn_pulse single-cycle events
//              - each key jumps to its fixed category head
//              - per-message timer reloads with THAT message's own duration
//              - auto-advance within a category on per-message timeout
//              - the system-idle (sleep) timer only fires while parked in
//                DEFAULT, and never interrupts an active category slideshow
//              - waking from SLEEP jumps directly to the pressed key's
//                category head (one hop)
//              - HEX display outputs
//
// Simulation shortcut: CLK_FREQ_HZ=1000, DEBOUNCE_MS=1, TIMEOUT_SEC=3
// (TIMEOUT_SEC is now the SLEEP/system-idle timer; the per-message timer
// always uses msg_duration_rom.v's real, unscaled per-message values).
// ============================================================================

`timescale 1ns / 1ps

module tb_fpga_msg_controller;

    // ----------------------------------------------------------------
    // Parameters — fast simulation
    // ----------------------------------------------------------------
    localparam CLK_FREQ_HZ = 1000;
    localparam DEBOUNCE_MS = 1;
    localparam TIMEOUT_SEC = 3;    // sleep timer only
    localparam NUM_BUTTONS = 4;
    localparam CLK_PERIOD  = 1_000_000;  // 1 ms in ns (1 kHz)

    // ----------------------------------------------------------------
    // Signals
    // ----------------------------------------------------------------
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

    // ----------------------------------------------------------------
    // DUT
    // ----------------------------------------------------------------
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

    // ----------------------------------------------------------------
    // Clock
    // ----------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ----------------------------------------------------------------
    // Test tracking
    // ----------------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num   = 0;
    reg [NUM_BUTTONS-1:0] btn_pulse_prev;
    integer pulse_width_errors = 0;

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

    // ----------------------------------------------------------------
    // Stimulus
    // ----------------------------------------------------------------
    initial begin
        $display("=== TB: fpga_msg_controller (round 2, category nav) ===");
        $display("CLK=%0d Hz, Debounce=%0d ms, Sleep timeout=%0d s",
                 CLK_FREQ_HZ, DEBOUNCE_MS, TIMEOUT_SEC);

        key_in = 4'b1111;  // All released (active-LOW)
        rst_n  = 1'b0;
        btn_pulse_prev = {NUM_BUTTONS{1'b0}};

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // ============================================================
        // TEST 1: Initial state — auto INIT->MSG at index 0 (DEFAULT head)
        // ============================================================
        check_bool(|btn_debounced, 1'b0, "Init debounced=0");
        check_bool(|btn_pulse,     1'b0, "Init pulse=0");
        check_bool(fsm_state == S_MSG, 1'b1, "Init: auto INIT->MSG");
        check_bool(fsm_msg_index == 5'd0, 1'b1, "Init: msg_index is DEFAULT head (0)");
        check_bool(hex2 == seven_seg(4'hF), 1'b1, "Init HEX2 last key exact (none)");
        // msg_duration_rom[0] = 12s; timer loads it immediately (combinational
        // load_value even through reset), before any ticks have elapsed.
        check_bool(seconds_remaining == 6'd12, 1'b1, "Init: per-message timer loaded msg0 duration (12s)");

        // ============================================================
        // TEST 2: KEY0 — jump to EXERCISE head (3)
        // ============================================================
        key_in[0] = 1'b0;  // Press KEY0 (active-LOW)
        repeat (1010) @(posedge clk);  // debounce settle (~1 tick past 1s)

        check_bool(btn_debounced[0], 1'b1, "KEY0 debounced");
        check_bool(fsm_msg_index == 5'd3, 1'b1, "KEY0 jumps to EXERCISE head (3)");
        check_bool(fsm_state == S_MSG, 1'b1, "Still in MSG after key jump");
        check_bool(hex2 == seven_seg(4'd0), 1'b1, "HEX2 shows last key=0");
        check_bool(btn_pulse[0], 1'b0, "Pulse auto-cleared");

        // msg_duration_rom[3] = 8s; ~1 tick has already elapsed by now.
        repeat (3) @(posedge clk);
        check_bool(seconds_remaining == 6'd7, 1'b1, "Timer reloaded EXERCISE-head (msg3) duration (8s)");

        key_in[0] = 1'b1;  // Release
        repeat (1010) @(posedge clk);

        // ============================================================
        // TEST 3: KEY1 — jump to SESSION head (8)
        // ============================================================
        key_in[1] = 1'b0;
        repeat (1010) @(posedge clk);
        check_bool(fsm_msg_index == 5'd8, 1'b1, "KEY1 jumps to SESSION head (8)");
        check_bool(hex2 == seven_seg(4'd1), 1'b1, "HEX2 shows last key=1");

        repeat (3) @(posedge clk);
        check_bool(seconds_remaining == 6'd9, 1'b1, "Timer reloaded SESSION-head (msg8) duration (10s)");

        key_in[1] = 1'b1;
        repeat (1010) @(posedge clk);

        // ============================================================
        // TEST 4: KEY2 — jump to EMERGENCY head (16)
        // ============================================================
        key_in[2] = 1'b0;
        repeat (1010) @(posedge clk);
        check_bool(fsm_msg_index == 5'd16, 1'b1, "KEY2 jumps to EMERGENCY head (16)");
        check_bool(hex2 == seven_seg(4'd2), 1'b1, "HEX2 shows last key=2");

        repeat (3) @(posedge clk);
        check_bool(seconds_remaining == 6'd5, 1'b1, "Timer reloaded EMERGENCY (msg16) duration (6s)");

        key_in[2] = 1'b1;
        repeat (1010) @(posedge clk);

        // ============================================================
        // TEST 5: KEY3 — escape Emergency / jump to DEFAULT head (0)
        // ============================================================
        key_in[3] = 1'b0;
        repeat (1010) @(posedge clk);
        check_bool(fsm_msg_index == 5'd0, 1'b1, "KEY3 jumps to DEFAULT head (0), escaping Emergency");
        check_bool(hex2 == seven_seg(4'd3), 1'b1, "HEX2 shows last key=3");
        check_bool(hex0 == seven_seg(4'd0), 1'b1, "HEX0 message-number ones exact (index 0)");
        check_bool(hex1 == seven_seg(4'd0), 1'b1, "HEX1 message-number tens exact (index 0)");

        key_in[3] = 1'b1;
        repeat (1010) @(posedge clk);

        check_bool(pulse_width_errors == 0, 1'b1, "All pulses are single-cycle width (so far)");

        // ============================================================
        // TEST 6: Auto-advance within a category on per-message timeout
        //   EXERCISE head (3) has an 8s duration; waiting it out with no
        //   button must advance to 4 and stay in S_MSG.
        // ============================================================
        key_in[0] = 1'b0;  // KEY0 -> EXERCISE head (3)
        repeat (1010) @(posedge clk);
        check_bool(fsm_msg_index == 5'd3, 1'b1, "Re-entered EXERCISE at head (3)");
        key_in[0] = 1'b1;
        repeat (1010) @(posedge clk);

        // Wait out msg_duration_rom[3]=8s (a little over 1s has already
        // elapsed since the reload; wait the remainder plus margin).
        repeat (8*CLK_FREQ_HZ) @(posedge clk);
        check_bool(fsm_state == S_MSG, 1'b1, "Still in MSG after category auto-advance");
        check_bool(fsm_msg_index == 5'd4, 1'b1, "Auto-advanced 3->4 within EXERCISE");

        // ============================================================
        // TEST 7: Sleep timer must NOT fire mid-category, even past
        //   TIMEOUT_SEC (3s), because msg4's own duration (10s) is longer
        //   and in_default is false the whole time.
        // ============================================================
        repeat (TIMEOUT_SEC*CLK_FREQ_HZ + 50) @(posedge clk);
        check_bool(fsm_state == S_MSG, 1'b1, "No sleep mid-category despite exceeding TIMEOUT_SEC");
        check_bool(fsm_msg_index == 5'd4, 1'b1, "Index unchanged (msg4's 10s duration not yet elapsed)");

        // ============================================================
        // TEST 8: Sleep timer DOES fire once parked at DEFAULT and idle.
        // ============================================================
        key_in[3] = 1'b0;  // KEY3 -> DEFAULT head (0), also reloads sleep timer
        repeat (1010) @(posedge clk);
        check_bool(fsm_msg_index == 5'd0, 1'b1, "Back at DEFAULT (0) for sleep test");
        key_in[3] = 1'b1;
        repeat (1010) @(posedge clk);

        repeat (TIMEOUT_SEC*CLK_FREQ_HZ + 50) @(posedge clk);
        check_bool(fsm_state == S_SLEEP, 1'b1, "Idle at DEFAULT -> SLEEP after TIMEOUT_SEC");

        // ============================================================
        // TEST 9: Waking from SLEEP jumps directly to the pressed key's
        //   category head (one hop, not back through DEFAULT first).
        // ============================================================
        key_in[1] = 1'b0;  // KEY1 -> SESSION head (8)
        repeat (1010) @(posedge clk);
        check_bool(fsm_state == S_MSG, 1'b1, "KEY1 wakes SLEEP -> MSG directly");
        check_bool(fsm_msg_index == 5'd8, 1'b1, "Wake jumps straight to SESSION head (8)");
        key_in[1] = 1'b1;
        repeat (1010) @(posedge clk);

        check_bool(pulse_width_errors == 0, 1'b1, "All pulses remained single-cycle width");

        // ============================================================
        // Summary
        // ============================================================
        $display("");
        $display("=== RESULTS: %0d PASSED, %0d FAILED out of %0d tests ===",
                 pass_count, fail_count, test_num);
        if (fail_count == 0)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** SOME TESTS FAILED ***");

        $finish;
    end

    // ----------------------------------------------------------------
    // Monitor key signals
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            if ((btn_pulse_prev & btn_pulse) != {NUM_BUTTONS{1'b0}}) begin
                pulse_width_errors = pulse_width_errors + 1;
                $display("  [PULSE WIDTH ERROR] btn_pulse held >1 cycle: prev=%b curr=%b @ %0t",
                         btn_pulse_prev, btn_pulse, $time);
            end
        end
        btn_pulse_prev <= btn_pulse;

        if (|btn_pulse)
            $display("  [%0t] btn_pulse=%b", $time, btn_pulse);
    end

    // ----------------------------------------------------------------
    // VCD dump
    // ----------------------------------------------------------------
    initial begin
        $dumpfile("tb_fpga_msg_controller.vcd");
        $dumpvars(0, tb_fpga_msg_controller);
    end

endmodule
