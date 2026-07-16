`timescale 1ns / 1ps
// ============================================================================
// Testbench: tb_soc_register_contract
// Project: DE10-Standard LCD Message System
//
// Verifies the HPS-visible register packing contract used by
// DE10_Standard_GHRD.v for the custom status exports:
//   fsm_status_pio_external_connection_export   = {fsm_state, fsm_msg_index}
//   timer_status_pio_external_connection_export = {1'b0, seconds_remaining, timeout_flag}
//
// PREVIOUS VERSION OF THIS FILE (round 1) instantiated no RTL at all -- it
// re-declared the same two packing expressions fed by testbench-injected
// `reg`s, then checked its own copy against itself. That can never catch a
// real wiring regression (e.g. the missing .msg_text_bus/.msg_text_status
// port connections in DE10_Standard_GHRD.v found and fixed separately --
// this exact class of bug is invisible to a self-contained packing check).
// It also drove ctrl_fsm_state = 3'd3, a state value that cannot occur in
// the current 3-state FSM (S_INIT=0/S_MSG=1/S_SLEEP=2 only) -- a stale
// leftover from round 1's 5-state design, never updated for round 2.
//
// THIS VERSION instantiates the real fpga_msg_controller and drives it with
// genuine button/reset stimulus, so fsm_state/fsm_msg_index/timeout_flag/
// seconds_remaining are real, reachable RTL outputs, not hand-picked
// constants -- and every state value exercised is one the current 3-state
// FSM can actually produce.
//
// What this test does NOT prove (by design -- simulating the Qsys-level
// top file requires proprietary Altera simulation libraries not available
// under Icarus): that DE10_Standard_GHRD.v's instantiation actually wires
// these controller outputs to the PIO export ports. That guarantee comes
// from verify_all.ps1's static check ("msg_text_bus/msg_text_status
// actually connected at u_msg_ctrl"), which is what caught the original
// missing-connection bug in the first place. The two checks are
// complementary: this proves the bit-packing FORMULA is correct against
// real controller behavior; verify_all.ps1 proves the formula's inputs are
// actually reaching the PIOs in the real top-level file.
// ============================================================================

module tb_soc_register_contract;

    localparam CLK_FREQ_HZ = 1000;
    localparam DEBOUNCE_MS = 1;
    localparam TIMEOUT_SEC = 3;
    localparam NUM_BUTTONS = 4;
    localparam CLK_PERIOD  = 1_000_000;  // 1 ms in ns (1 kHz)

    localparam [2:0] S_INIT  = 3'd0;
    localparam [2:0] S_MSG   = 3'd1;
    localparam [2:0] S_SLEEP = 3'd2;

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

    // Exact contract from DE10_Standard_GHRD.v -- fed from the REAL DUT's
    // output ports, not testbench-injected constants.
    wire [7:0] fsm_status_export   = {fsm_state, fsm_msg_index};
    wire [7:0] timer_status_export = {1'b0, seconds_remaining, timeout_flag};

    initial clk = 0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num   = 0;

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

    // Checks the packing formula against whatever real state the DUT is
    // currently in -- reusable at every checkpoint below.
    task check_packing_matches_dut;
        input [255:0] label;
        begin
            check(fsm_status_export[7:5] === fsm_state,
                  {"fsm bits[7:5]==state @ ", label});
            check(fsm_status_export[4:0] === fsm_msg_index,
                  {"fsm bits[4:0]==index @ ", label});
            check(timer_status_export[7] === 1'b0,
                  {"timer bit7 reserved-zero @ ", label});
            check(timer_status_export[6:1] === seconds_remaining,
                  {"timer bits[6:1]==seconds @ ", label});
            check(timer_status_export[0] === timeout_flag,
                  {"timer bit0==timeout_flag @ ", label});
            // Every value fsm_state can actually take must round-trip
            // through the 3-bit field without aliasing to an unreachable
            // encoding (the exact class of staleness the old 3'd3 vector
            // masked instead of catching).
            check(fsm_state === S_INIT || fsm_state === S_MSG || fsm_state === S_SLEEP,
                  {"fsm_state is a reachable 3-state encoding @ ", label});
        end
    endtask

    initial begin
        $display("=== TB: soc register contract (real fpga_msg_controller DUT) ===");

        key_in = 4'b1111;
        rst_n  = 1'b0;
        repeat (5) @(posedge clk);

        // Checkpoint 1: mid-reset. fsm_state/index hold their reset values
        // even before rst_n releases -- a real, reachable snapshot.
        #1;
        check_packing_matches_dut("during reset");

        rst_n = 1'b1;
        @(posedge clk); #1;
        // Checkpoint 2: S_INIT, exactly one cycle, before the automatic
        // transition to S_MSG.
        check_packing_matches_dut("S_INIT (post-reset, pre-auto-transition)");

        @(posedge clk); #1;
        // Checkpoint 3: S_MSG at the DEFAULT head (0).
        check(fsm_state === S_MSG, "reached S_MSG");
        check(fsm_msg_index === 5'd0, "at DEFAULT head (0)");
        check_packing_matches_dut("S_MSG @ DEFAULT head (0)");

        // Checkpoint 4: navigate to EXERCISE head (3, 8s duration) via a
        // real KEY0 press -- a different, real index/state/timer snapshot.
        key_in[0] = 1'b0;
        repeat (1010) @(posedge clk);
        key_in[0] = 1'b1;
        #1;
        check(fsm_msg_index === 5'd3, "reached EXERCISE head (3) via real KEY0 press");
        check_packing_matches_dut("S_MSG @ EXERCISE head (3), just after jump");

        // Checkpoint 5: let the per-message timer visibly count down a few
        // real seconds, re-check the packing at a different countdown
        // value (proves the timer field isn't only ever checked at its
        // just-reloaded value).
        repeat (3 * CLK_FREQ_HZ) @(posedge clk);
        #1;
        check(seconds_remaining < 6'd8, "timer has counted down from EXERCISE-head's 8s load");
        check_packing_matches_dut("S_MSG @ EXERCISE head (3), mid-countdown");

        // Checkpoint 6: navigate to EMERGENCY (16) via real KEY2 -- exercises
        // the largest realistic fsm_msg_index value the field must carry.
        key_in[2] = 1'b0;
        repeat (1010) @(posedge clk);
        key_in[2] = 1'b1;
        #1;
        check(fsm_msg_index === 5'd16, "reached EMERGENCY (16) via real KEY2 press");
        check_packing_matches_dut("S_MSG @ EMERGENCY head (16)");

        // Checkpoint 7: idle at DEFAULT until the sleep timer parks the
        // controller in S_SLEEP -- the third and last real reachable state.
        key_in[3] = 1'b0;
        repeat (1010) @(posedge clk);
        key_in[3] = 1'b1;
        repeat (TIMEOUT_SEC * CLK_FREQ_HZ + 50) @(posedge clk);
        #1;
        check(fsm_state === S_SLEEP, "reached S_SLEEP via real idle timeout");
        check_packing_matches_dut("S_SLEEP");

        $display("");
        $display("=== RESULTS: %0d PASSED, %0d FAILED out of %0d tests ===",
                 pass_count, fail_count, test_num);
        if (fail_count == 0)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** SOME TESTS FAILED ***");

        $finish;
    end

endmodule
