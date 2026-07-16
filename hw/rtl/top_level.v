// ============================================================================
// Module: top_level
// Project: DE10-Standard LCD Message System  
// File: hw/rtl/top_level.v
//
// Description: Standalone FPGA-only top-level wrapper for simulation and
//              board-level FPGA testing (no HPS/Qsys required).
//              Instantiates fpga_msg_controller with all DE10-Standard I/O.
//
//              On the DE10-Standard board (round 2, category nav model):
//                KEY[0]   = active-LOW reset (hold to reset, release to run);
//                           also wired to key_in[0] (controller KEY0/EXERCISE)
//                KEY[1]   = key_in[1] -> controller KEY1: SESSION
//                KEY[2]   = key_in[2] -> controller KEY2: EMERGENCY
//                KEY[3]   = key_in[3] -> controller KEY3: DEFAULT/Home
//                NOTE: KEY[0] is wired to reset here, so controller KEY0
//                (EXERCISE) is not reachable as a real button press on this
//                standalone build -- only the full DE10_Standard_GHRD.v/Qsys
//                build has all 4 KEYs free for navigation. Do not use this
//                module to validate the EXERCISE jump or KEY0 behavior.
//                HEX5:HEX4 = per-message duration countdown (decimal)
//                HEX2      = Last button pressed (0-3, F=none)
//                HEX0/1/3  = Reserved (show 0)
//                LEDR[3:0] = Debounced button levels (active-HIGH)
//                LEDR[4]   = Timeout flag
//                LEDR[9:5] = Unused (off)
//
// NOTE: This module is for STANDALONE SIMULATION and FPGA-only demo.
//       For the full HPS/SoC design, see hw/quartus/DE10_Standard_GHRD.v
//       which integrates fpga_msg_controller into the Qsys SoC system.
// ============================================================================

module top_level (
    // ---- Clock ----
    input  wire        CLOCK_50,      // 50 MHz system clock

    // ---- Pushbuttons (active-LOW) ----
    input  wire [3:0]  KEY,           // KEY[0]=reset, KEY[1-3]=buttons

    // ---- 7-Segment Displays (active-LOW) ----
    output wire [6:0]  HEX0,          // Reserved
    output wire [6:0]  HEX1,          // Reserved
    output wire [6:0]  HEX2,          // Last button pressed
    output wire [6:0]  HEX3,          // Reserved
    output wire [6:0]  HEX4,          // Timer ones digit
    output wire [6:0]  HEX5,          // Timer tens digit

    // ---- LEDs (active-HIGH) ----
    output wire [9:0]  LEDR           // Debounced buttons + timeout indicator
);

    // ----------------------------------------------------------------
    // Internal signals from fpga_msg_controller
    // ----------------------------------------------------------------
    wire [3:0] btn_pulse;             // Single-cycle press events (20ns pulses)
    wire [3:0] btn_debounced;         // Stable active-HIGH debounced button levels
    wire       timeout_flag;          // HIGH when the active countdown expires
    wire [5:0] seconds_remaining;     // Countdown value shown as decimal on HEX5:HEX4

    // ----------------------------------------------------------------
    // fpga_msg_controller: debouncer + edge detect + idle timer + HEX
    // ----------------------------------------------------------------
    fpga_msg_controller #(
        .CLK_FREQ_HZ (50_000_000),    // 50 MHz — match CLOCK_50
        .DEBOUNCE_MS (20),             // 20 ms debounce window
        .TIMEOUT_SEC (60),             // System-idle (sleep) timeout, armed only
                                        // while parked in DEFAULT; the per-message
                                        // timer always uses msg_duration_rom instead
        .NUM_BUTTONS (4)               // All 4 KEY buttons
    ) u_ctrl (
        .clk               (CLOCK_50),
        .rst_n             (KEY[0]),   // KEY[0] is system reset (active-LOW)
        .key_in            (KEY),      // Raw active-LOW button inputs
        .btn_pulse         (btn_pulse),
        .btn_debounced     (btn_debounced),
        .timeout_flag      (timeout_flag),
        .seconds_remaining (seconds_remaining),
        .hex0              (HEX0),
        .hex1              (HEX1),
        .hex2              (HEX2),
        .hex3              (HEX3),
        .hex4              (HEX4),
        .hex5              (HEX5)
    );

    // ----------------------------------------------------------------
    // LED assignments for visual debug on board
    //   LEDR[3:0] — debounced button indicators (green = pressed)
    //   LEDR[4]   — timeout warning (red = idle timeout reached)
    //   LEDR[9:5] — unused, forced off
    // ----------------------------------------------------------------
    assign LEDR[3:0] = btn_debounced;   // Active-HIGH: lit when button pressed
    assign LEDR[4]   = timeout_flag;    // Lit when the active countdown expires
    assign LEDR[9:5] = 5'b00000;

endmodule
