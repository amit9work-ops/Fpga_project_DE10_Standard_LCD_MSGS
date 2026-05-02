// ============================================================================
// Testbench: tb_fpga_msg_controller
// Project: DE10-Standard LCD Message System
// Description: Full integration testbench for fpga_msg_controller.
//              Stimulates KEY inputs and verifies:
//              - btn_debounced outputs after debounce settling
//              - btn_pulse single-cycle events
//              - idle_timer countdown and timeout
//              - HEX display outputs
//
// Simulation shortcut: CLK_FREQ_HZ=1000, DEBOUNCE_MS=1, TIMEOUT_SEC=3
// ============================================================================

`timescale 1ns / 1ps

module tb_fpga_msg_controller;

    // ----------------------------------------------------------------
    // Parameters — fast simulation
    // ----------------------------------------------------------------
    localparam CLK_FREQ_HZ = 1000;
    localparam DEBOUNCE_MS = 1;
    localparam TIMEOUT_SEC = 3;
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
    wire [3:0]             seconds_remaining;
    wire [2:0]             fsm_state;
    wire [4:0]             fsm_msg_index;
    wire [6:0]             hex0, hex1, hex2, hex3, hex4, hex5;

    localparam [2:0] S_INIT  = 3'd0;
    localparam [2:0] S_IDLE  = 3'd1;
    localparam [2:0] S_HOME  = 3'd2;
    localparam [2:0] S_MSG   = 3'd3;
    localparam [2:0] S_SLEEP = 3'd4;

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
        $display("=== TB: fpga_msg_controller (Integration) ===");
        $display("CLK=%0d Hz, Debounce=%0d ms, Timeout=%0d s",
                 CLK_FREQ_HZ, DEBOUNCE_MS, TIMEOUT_SEC);

        key_in = 4'b1111;  // All released (active-LOW)
        rst_n  = 1'b0;
        btn_pulse_prev = {NUM_BUTTONS{1'b0}};

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // ============================================================
        // TEST 1: Initial state — no debounced, no pulse
        // ============================================================
        check_bool(|btn_debounced, 1'b0, "Init debounced=0");
        check_bool(|btn_pulse,     1'b0, "Init pulse=0");
        check_bool(timeout_flag,   1'b0, "Init no timeout");
        check_bool(hex0 == seven_seg(4'd3), 1'b1, "Init HEX0 exact");
        check_bool(hex1 == seven_seg(4'hF), 1'b1, "Init HEX1 exact");
        check_bool(hex2 == seven_seg(4'd0), 1'b1, "Init HEX2 exact");
        check_bool(fsm_state == S_IDLE, 1'b1, "Init FSM in IDLE");

        // ============================================================
        // TEST 2: Press KEY0 — debounce + edge detect
        // ============================================================
        key_in[0] = 1'b0;  // Press KEY0 (active-LOW)

        // Wait for debounce (2 sync + 1000 debounce ticks + margin)
        repeat (1010) @(posedge clk);

        check_bool(btn_debounced[0], 1'b1, "KEY0 debounced");
        check_bool(hex1 == seven_seg(4'd0), 1'b1, "HEX1 shows last key=0");
        check_bool(fsm_state == S_HOME, 1'b1, "FSM IDLE->HOME on first press");

        // The pulse should have appeared about 1002 cycles after press
        // By now it's gone — check that pulse is not stuck HIGH
        check_bool(btn_pulse[0], 1'b0, "Pulse auto-cleared");

        // ============================================================
        // TEST 3: Release KEY0
        // ============================================================
        key_in[0] = 1'b1;  // Release
        repeat (1010) @(posedge clk);
        check_bool(btn_debounced[0], 1'b0, "KEY0 released");
        check_bool(fsm_state == S_HOME, 1'b1, "FSM remains HOME after release");

        // ============================================================
        // TEST 4: Timer countdown
        //   At 1000 Hz, 1 second = 1000 ticks
        //   Timer should start from 3 (TIMEOUT_SEC)
        // ============================================================
        $display("  Waiting for timer countdown...");

        // Timer was reset by the KEY0 press. Count 3 seconds + timeout second.
        repeat (CLK_FREQ_HZ) @(posedge clk);
        $display("  seconds_remaining=%0d (expect 2)", seconds_remaining);

        repeat (CLK_FREQ_HZ) @(posedge clk);
        $display("  seconds_remaining=%0d (expect 1)", seconds_remaining);

        repeat (CLK_FREQ_HZ) @(posedge clk);
        $display("  seconds_remaining=%0d (expect 0)", seconds_remaining);
        check_bool(timeout_flag, 1'b1, "Timeout after countdown");
        check_bool(hex2 == seven_seg(4'd1), 1'b1, "HEX2 timeout exact");
        check_bool(hex0 == seven_seg(4'd0), 1'b1, "HEX0 zero exact on timeout");
        check_bool(fsm_state == S_SLEEP, 1'b1, "FSM HOME->SLEEP on timeout");

        // ============================================================
        // TEST 5: Press KEY1 — resets timer
        // ============================================================
        key_in[1] = 1'b0;  // Press KEY1
        repeat (1010) @(posedge clk);

        check_bool(timeout_flag, 1'b0, "Timer reset by KEY1");
        $display("  seconds_remaining=%0d (expect 2)", seconds_remaining);
        check_bool(hex1 == seven_seg(4'd1), 1'b1, "HEX1 shows last key=1");
        check_bool(hex2 == seven_seg(4'd0), 1'b1, "HEX2 running exact");
        check_bool(fsm_state == S_IDLE, 1'b1, "FSM SLEEP->IDLE on wake press");

        key_in[1] = 1'b1;  // Release KEY1
        repeat (1010) @(posedge clk);

        // ============================================================
        // TEST 6: HEX display exact values while running
        // ============================================================
        check_bool(hex0 == seven_seg(4'd1), 1'b1, "HEX0 exact one second after KEY1 reset");
        check_bool(hex3 == seven_seg(4'd0), 1'b1, "HEX3 reserved exact");
        check_bool(hex4 == seven_seg(4'd0), 1'b1, "HEX4 reserved exact");
        check_bool(hex5 == seven_seg(4'd0), 1'b1, "HEX5 reserved exact");

        check_bool(pulse_width_errors == 0, 1'b1, "All pulses are single-cycle width");

        // ============================================================
        // TEST 7: Integrated FSM path (IDLE->HOME->MSG + index + timeout)
        // ============================================================
        key_in[2] = 1'b0;  // Press KEY2: IDLE -> HOME
        repeat (1010) @(posedge clk);
        check_bool(fsm_state == S_HOME, 1'b1, "FSM IDLE->HOME via KEY2");
        key_in[2] = 1'b1;
        repeat (1010) @(posedge clk);

        key_in[2] = 1'b0;  // Press KEY2: HOME -> MSG
        repeat (1010) @(posedge clk);
        check_bool(fsm_state == S_MSG, 1'b1, "FSM HOME->MSG via KEY2");
        check_bool(fsm_msg_index == 5'd0, 1'b1, "FSM index reset to 0 on MSG entry");
        key_in[2] = 1'b1;
        repeat (1010) @(posedge clk);

        key_in[1] = 1'b0;  // Press KEY1: MSG index ++
        repeat (1010) @(posedge clk);
        check_bool(fsm_state == S_MSG, 1'b1, "FSM stays in MSG on KEY1 next");
        check_bool(fsm_msg_index == 5'd1, 1'b1, "FSM index increments in MSG");
        key_in[1] = 1'b1;
        repeat (1010) @(posedge clk);

        // Timer should reset on any button pulse, even during MSG
        repeat (CLK_FREQ_HZ/4) @(posedge clk); // keep well under timeout
        key_in[1] = 1'b0;  // Press KEY1 again to reset timer in MSG
        repeat (1010) @(posedge clk);
        check_bool(timeout_flag == 1'b0, 1'b1, "Timer cleared by KEY1 in MSG");
        check_bool(seconds_remaining >= 4'd2, 1'b1, "Timer reloaded by KEY1 in MSG");
        key_in[1] = 1'b1;
        repeat (1010) @(posedge clk);

        repeat (3*CLK_FREQ_HZ + 20) @(posedge clk); // timeout in MSG -> SLEEP
        check_bool(fsm_state == S_SLEEP, 1'b1, "FSM MSG->SLEEP on timeout");

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
