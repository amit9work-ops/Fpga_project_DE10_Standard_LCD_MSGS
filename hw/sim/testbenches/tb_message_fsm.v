`timescale 1ns/1ps
// ============================================================================
// tb_message_fsm - round 2 (3-state, category-based navigation).
//
// Wires message_fsm + msg_nav_rom together exactly as fpga_msg_controller
// does, drives btn_pulse / msg_timeout_flag / sleep_timeout_flag directly
// (category-arming of the sleep timer is fpga_msg_controller's job, not
// this module's -- tested separately in tb_fpga_msg_controller), and checks
// both directed scenarios and a randomized model-vs-DUT campaign against the
// generated golden nav table.
// ============================================================================

module tb_message_fsm;

    localparam CLK_PERIOD_NS = 10;
    localparam INDEX_W = 5;

    localparam [2:0] S_INIT  = 3'd0;
    localparam [2:0] S_MSG   = 3'd1;
    localparam [2:0] S_SLEEP = 3'd2;

    localparam ACT_KEY0    = 3'd0;
    localparam ACT_KEY1    = 3'd1;
    localparam ACT_KEY2    = 3'd2;
    localparam ACT_KEY3    = 3'd3;
    localparam ACT_TIMEOUT = 3'd4;

    reg clk;
    reg rst_n;
    reg [3:0] btn_pulse;
    reg msg_timeout_flag;
    reg sleep_timeout_flag;

    wire [2:0] state;
    wire [INDEX_W-1:0] msg_index;
    wire [2:0] nav_action;
    wire [INDEX_W-1:0] nav_next_index;
    wire in_default_unused;

    integer test_num = 0;
    integer pass_count = 0;
    integer fail_count = 0;
    integer rand_iter;
    integer seed;

    reg [2:0] exp_state;
    reg [INDEX_W-1:0] exp_index;
    reg [2:0] next_state;
    reg [INDEX_W-1:0] next_index;

    reg [4:0] golden_nav [0:89];

    message_fsm #(
        .INDEX_W(INDEX_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .btn_pulse(btn_pulse),
        .msg_timeout_flag(msg_timeout_flag),
        .sleep_timeout_flag(sleep_timeout_flag),
        .nav_next_index(nav_next_index),
        .state(state),
        .msg_index(msg_index),
        .nav_action(nav_action)
    );

    msg_nav_rom u_nav (
        .cur_index  (msg_index),
        .action     (nav_action),
        .next_index (nav_next_index),
        .in_default (in_default_unused)
    );

    task check_eq;
        input condition;
        input [255:0] name;
        begin
            test_num = test_num + 1;
            if (condition) begin
                pass_count = pass_count + 1;
                $display("PASS Test %0d [%0s] @ %0t", test_num, name, $time);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL Test %0d [%0s] @ %0t", test_num, name, $time);
            end
        end
    endtask

    // Stimulus is driven on the negedge so it is stable before the sampling
    // posedge (avoids a TB-vs-DUT same-edge race).
    task pulse_btn;
        input integer idx;
        begin
            @(negedge clk);
            btn_pulse = 4'b0000;
            btn_pulse[idx] = 1'b1;
            @(negedge clk);
            btn_pulse = 4'b0000;
        end
    endtask

    task pulse_msg_timeout;
        begin
            @(negedge clk); msg_timeout_flag = 1'b1;
            @(negedge clk); msg_timeout_flag = 1'b0;
        end
    endtask

    task pulse_sleep_timeout;
        begin
            @(negedge clk); sleep_timeout_flag = 1'b1;
            @(negedge clk); sleep_timeout_flag = 1'b0;
        end
    endtask

    // Reference model mirroring message_fsm.v + msg_nav_rom.v.
    function [2:0] model_action;
        input [3:0] in_btn;
        begin
            if (in_btn[0])      model_action = ACT_KEY0;
            else if (in_btn[1]) model_action = ACT_KEY1;
            else if (in_btn[2]) model_action = ACT_KEY2;
            else if (in_btn[3]) model_action = ACT_KEY3;
            else                model_action = ACT_TIMEOUT;
        end
    endfunction

    task model_step;
        input  [2:0] in_state;
        input  [INDEX_W-1:0] in_index;
        input  [3:0] in_btn;
        input        in_msg_timeout;
        input        in_sleep_timeout;
        output [2:0] out_state;
        output [INDEX_W-1:0] out_index;
        reg [2:0] act;
        begin
            out_state = in_state;
            out_index = in_index;
            case (in_state)
                S_INIT: begin
                    out_state = S_MSG;
                    out_index = {INDEX_W{1'b0}};
                end

                S_MSG: begin
                    if (|in_btn) begin
                        act = model_action(in_btn);
                        out_index = golden_nav[in_index * 5 + act];
                    end else if (in_msg_timeout) begin
                        out_index = golden_nav[in_index * 5 + ACT_TIMEOUT];
                    end else if (in_sleep_timeout) begin
                        out_state = S_SLEEP;
                    end
                end

                S_SLEEP: begin
                    if (|in_btn) begin
                        act = model_action(in_btn);
                        out_state = S_MSG;
                        out_index = golden_nav[in_index * 5 + act];
                    end
                end

                default: begin
                    out_state = S_INIT;
                    out_index = {INDEX_W{1'b0}};
                end
            endcase
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS/2) clk = ~clk;
    end

    initial begin
        $display("=== TB: message_fsm (round 2, category nav) ===");
        $dumpfile("tb_message_fsm.vcd");
        $dumpvars(0, tb_message_fsm);
        `include "msg_nav_golden.vh"

        rst_n = 1'b0;
        btn_pulse = 4'b0000;
        msg_timeout_flag = 1'b0;
        sleep_timeout_flag = 1'b0;
        seed = 32'h51A2B3C4;

        repeat (3) @(posedge clk);
        check_eq(state == S_INIT, "Reset state is INIT");
        check_eq(msg_index == 0, "Reset msg_index is 0");

        rst_n = 1'b1;
        @(posedge clk);
        check_eq(state == S_MSG, "INIT auto-transitions to MSG");
        check_eq(msg_index == 0, "MSG starts at index 0 (DEFAULT head)");

        // Directed key-jump checks.
        pulse_btn(0);  // KEY0 -> EXERCISE head (3)
        check_eq(msg_index == 3, "KEY0 jumps to EXERCISE head (3)");
        pulse_btn(1);  // KEY1 -> SESSION head (8)
        check_eq(msg_index == 8, "KEY1 jumps to SESSION head (8)");
        pulse_btn(2);  // KEY2 -> EMERGENCY head (16)
        check_eq(msg_index == 16, "KEY2 jumps to EMERGENCY head (16)");
        pulse_btn(3);  // KEY3 -> DEFAULT head (0)
        check_eq(msg_index == 0, "KEY3 jumps to DEFAULT head (0)");

        // Sequential timeout advance within a category (EXERCISE: 3->4->5->6->7).
        pulse_btn(0);
        check_eq(msg_index == 3, "Re-enter EXERCISE at head (3)");
        pulse_msg_timeout();
        check_eq(msg_index == 4, "Timeout advances 3->4");
        pulse_msg_timeout();
        check_eq(msg_index == 5, "Timeout advances 4->5");
        pulse_msg_timeout();
        check_eq(msg_index == 6, "Timeout advances 5->6");
        pulse_msg_timeout();
        check_eq(msg_index == 7, "Timeout advances 6->7 (EXERCISE last)");
        pulse_msg_timeout();
        check_eq(msg_index == 0, "EXERCISE last entry times out to DEFAULT (0)");

        // Emergency sticky on timeout.
        pulse_btn(2);
        check_eq(msg_index == 16, "Jump to EMERGENCY (16)");
        pulse_msg_timeout();
        check_eq(msg_index == 16, "EMERGENCY sticks to itself on timeout");
        pulse_msg_timeout();
        check_eq(msg_index == 16, "EMERGENCY still sticky after a second timeout");

        // KEY3 escapes a stuck Emergency.
        pulse_btn(3);
        check_eq(msg_index == 0, "KEY3 escapes Emergency back to DEFAULT (0)");
        check_eq(state == S_MSG, "Still in MSG after escaping Emergency");

        // Button beats a simultaneous msg_timeout (KEY1 wins).
        pulse_btn(0);
        check_eq(msg_index == 3, "Back in EXERCISE (3) for priority test");
        @(negedge clk); btn_pulse = 4'b0010; msg_timeout_flag = 1'b1;  // KEY1 + msg timeout together
        @(negedge clk); btn_pulse = 4'b0000; msg_timeout_flag = 1'b0;
        check_eq(msg_index == 8, "Button (KEY1) beats a simultaneous msg_timeout");

        // msg_timeout beats a simultaneous sleep_timeout.
        pulse_btn(3);
        check_eq(msg_index == 0, "Back at DEFAULT (0)");
        @(negedge clk); msg_timeout_flag = 1'b1; sleep_timeout_flag = 1'b1;
        @(negedge clk); msg_timeout_flag = 1'b0; sleep_timeout_flag = 1'b0;
        check_eq(state == S_MSG, "msg_timeout beats a simultaneous sleep_timeout (stays MSG)");
        check_eq(msg_index == 1, "msg_timeout advanced DEFAULT 0->1 despite simultaneous sleep_timeout");

        // Sleep: no button, no msg_timeout, only sleep_timeout -> SLEEP.
        pulse_sleep_timeout();
        check_eq(state == S_SLEEP, "sleep_timeout with nothing else pending -> SLEEP");
        check_eq(msg_index == 1, "msg_index frozen while entering SLEEP");

        // Wake from SLEEP: one hop directly to the pressed key's category head.
        pulse_btn(0);
        check_eq(state == S_MSG, "KEY0 wakes SLEEP -> MSG directly");
        check_eq(msg_index == 3, "Wake jumps straight to EXERCISE head (3), not DEFAULT first");

        // ============================================================
        // Randomized model-vs-DUT campaign.
        // ============================================================
        exp_state = state;
        exp_index = msg_index;

        for (rand_iter = 0; rand_iter < 500; rand_iter = rand_iter + 1) begin
            @(negedge clk);
            case ($unsigned($random(seed)) % 6)
                0: btn_pulse = 4'b0000;
                1: btn_pulse = 4'b0001;  // KEY0
                2: btn_pulse = 4'b0010;  // KEY1
                3: btn_pulse = 4'b0100;  // KEY2
                4: btn_pulse = 4'b1000;  // KEY3
                5: btn_pulse = 4'b0000;  // extra weight on "no button" so timers get exercised
            endcase
            // Only pulse the timers when no button is pressed this cycle, to
            // avoid an ambiguous "which fired first" stimulus (the RTL's
            // priority is well-defined for simultaneous signals, but a
            // simultaneous button+timer case is already covered directively
            // above; the random campaign focuses on breadth of state/index
            // coverage under realistic single-cause stimulus).
            if (btn_pulse == 4'b0000) begin
                msg_timeout_flag   = (($random(seed) & 16'h00FF) < 8'h60);
                sleep_timeout_flag = !msg_timeout_flag && (($random(seed) & 16'h00FF) < 8'h30);
            end else begin
                msg_timeout_flag   = 1'b0;
                sleep_timeout_flag = 1'b0;
            end

            model_step(exp_state, exp_index, btn_pulse, msg_timeout_flag, sleep_timeout_flag,
                       next_state, next_index);
            @(posedge clk);
            #1;

            check_eq(state == next_state, "Randomized: state matches model");
            check_eq(msg_index == next_index, "Randomized: index matches model");
            check_eq(msg_index < 5'd18, "Randomized: index always in range");

            exp_state = next_state;
            exp_index = next_index;
        end

        btn_pulse = 4'b0000;
        msg_timeout_flag = 1'b0;
        sleep_timeout_flag = 1'b0;

        $display("");
        $display("=== RESULTS: %0d PASSED, %0d FAILED out of %0d tests ===", pass_count, fail_count, test_num);
        if (fail_count == 0)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** SOME TESTS FAILED ***");

        $finish;
    end

    initial begin
        repeat (4000) @(posedge clk);
        $display("FAIL [TIMEOUT] FSM TB exceeded safety window");
        $finish;
    end

endmodule
