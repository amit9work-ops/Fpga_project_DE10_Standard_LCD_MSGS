`timescale 1ns/1ps
// ============================================================================
// tb_message_fsm - FSM navigation is now TABLE-DRIVEN (msg_nav_rom).
//
// The DUT emits nav_action and consumes nav_next_index; this TB wires a real
// msg_nav_rom between them (exactly as fpga_msg_controller does) and mirrors
// the nav table in the reference model using the generated golden vectors, so
// the 500-iteration model-vs-DUT campaign checks the FSM's action selection and
// index application against the same table the ROM is built from.
// ============================================================================

module tb_message_fsm;

    localparam CLK_PERIOD_NS = 10;
    localparam MSG_COUNT = 18;
    localparam INDEX_W = 5;

    localparam [2:0] S_INIT  = 3'd0;
    localparam [2:0] S_IDLE  = 3'd1;
    localparam [2:0] S_HOME  = 3'd2;
    localparam [2:0] S_MSG   = 3'd3;
    localparam [2:0] S_SLEEP = 3'd4;

    localparam [1:0] ACT_KEY1    = 2'd0;
    localparam [1:0] ACT_KEY2    = 2'd1;
    localparam [1:0] ACT_KEY3    = 2'd2;
    localparam [1:0] ACT_TIMEOUT = 2'd3;

    reg clk;
    reg rst_n;
    reg [3:0] btn_pulse;
    reg timeout_flag;

    wire [2:0] state;
    wire [INDEX_W-1:0] msg_index;
    wire [1:0] nav_action;
    wire [INDEX_W-1:0] nav_next_index;

    integer test_num = 0;
    integer pass_count = 0;
    integer fail_count = 0;
    integer rand_iter;
    integer seed;

    reg [2:0] exp_state;
    reg [INDEX_W-1:0] exp_index;
    reg [2:0] next_state;
    reg [INDEX_W-1:0] next_index;

    // Golden nav table (same source as the ROM), for the reference model.
    reg [4:0] golden_nav [0:71];

    message_fsm #(
        .MSG_COUNT(MSG_COUNT),
        .INDEX_W(INDEX_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .btn_pulse(btn_pulse),
        .timeout_flag(timeout_flag),
        .nav_next_index(nav_next_index),
        .state(state),
        .msg_index(msg_index),
        .nav_action(nav_action)
    );

    // Real nav ROM in the loop, wired as in fpga_msg_controller.
    msg_nav_rom u_nav (
        .cur_index  (msg_index),
        .action     (nav_action),
        .next_index (nav_next_index)
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

    // Stimulus is driven on the negedge so it is stable well before the
    // sampling posedge (avoids a TB-vs-DUT same-edge race). btn is held high
    // for exactly one posedge.
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

    // Assert timeout_flag for exactly one posedge.
    task pulse_timeout;
        begin
            @(negedge clk); timeout_flag = 1'b1;
            @(negedge clk); timeout_flag = 1'b0;
        end
    endtask

    // Assert a button and timeout simultaneously for one posedge.
    task pulse_combo;
        input [3:0] btn;
        begin
            @(negedge clk); btn_pulse = btn; timeout_flag = 1'b1;
            @(negedge clk); btn_pulse = 4'b0000; timeout_flag = 1'b0;
        end
    endtask

    // Reference model mirroring message_fsm + msg_nav_rom.
    function [1:0] model_action;
        input [3:0] in_btn;
        begin
            if (in_btn[1])      model_action = ACT_KEY1;
            else if (in_btn[2]) model_action = ACT_KEY2;
            else if (in_btn[3]) model_action = ACT_KEY3;
            else                model_action = ACT_TIMEOUT;
        end
    endfunction

    task model_step;
        input  [2:0] in_state;
        input  [INDEX_W-1:0] in_index;
        input  [3:0] in_btn;
        input        in_timeout;
        output [2:0] out_state;
        output [INDEX_W-1:0] out_index;
        reg [1:0] act;
        begin
            out_state = in_state;
            out_index = in_index;
            case (in_state)
                S_INIT: out_state = S_IDLE;

                S_IDLE: if (|in_btn) out_state = S_HOME;

                S_HOME: begin
                    if (in_timeout)
                        out_state = S_SLEEP;
                    else if (in_btn[0])
                        out_state = S_IDLE;
                    else if (in_btn[1] || in_btn[2]) begin
                        out_state = S_MSG;
                        out_index = {INDEX_W{1'b0}};
                    end
                end

                S_MSG: begin
                    if (in_btn[0])
                        out_state = S_HOME;
                    else if (in_btn[1] || in_btn[2] || in_btn[3]) begin
                        act = model_action(in_btn);
                        out_index = golden_nav[in_index*4 + act];
                    end else if (in_timeout) begin
                        out_index = golden_nav[in_index*4 + ACT_TIMEOUT];
                    end
                end

                S_SLEEP: if (|in_btn) out_state = S_IDLE;

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
        $display("=== TB: message_fsm (table-driven nav) ===");
        $dumpfile("tb_message_fsm.vcd");
        $dumpvars(0, tb_message_fsm);
        `include "msg_nav_golden.vh"

        rst_n = 1'b0;
        btn_pulse = 4'b0000;
        timeout_flag = 1'b0;
        seed = 32'h51A2B3C4;

        repeat (3) @(posedge clk);
        check_eq(state == S_INIT, "Reset state is INIT");
        check_eq(msg_index == 0, "Reset msg_index is 0");

        rst_n = 1'b1;
        @(posedge clk);
        check_eq(state == S_IDLE, "INIT auto-transitions to IDLE");

        pulse_btn(3);
        check_eq(state == S_HOME, "IDLE -> HOME on any button pulse");

        pulse_btn(0);
        check_eq(state == S_IDLE, "HOME -> IDLE on KEY0");

        pulse_btn(1);
        check_eq(state == S_HOME, "IDLE -> HOME (second entry)");
        pulse_btn(1);
        check_eq(state == S_MSG, "HOME -> MSG on KEY1");
        check_eq(msg_index == 0, "MSG starts at index 0");

        // Directed nav spot-checks against the known table.
        pulse_btn(1);  // KEY1: INTRO next 0->1
        check_eq(msg_index == 1, "KEY1 next within category 0->1");
        pulse_btn(1);  // KEY1: 1->2
        check_eq(msg_index == 2, "KEY1 next within category 1->2");
        pulse_btn(1);  // KEY1: INTRO wraps 2->0
        check_eq(msg_index == 0, "KEY1 wraps within category 2->0");
        pulse_btn(2);  // KEY2: head of next category 0->3
        check_eq(msg_index == 3, "KEY2 jumps to next category 0->3");
        pulse_btn(3);  // KEY3: emergency from anywhere 3->16
        check_eq(msg_index == 16, "KEY3 jumps to emergency 3->16");

        // MSG -> HOME on KEY0
        pulse_btn(0);
        check_eq(state == S_HOME, "MSG -> HOME on KEY0");

        // HOME timeout -> SLEEP
        pulse_timeout();
        check_eq(state == S_SLEEP, "HOME -> SLEEP on timeout");

        pulse_btn(2);
        check_eq(state == S_IDLE, "SLEEP -> IDLE on any key");

        // Enter MSG again; single-cycle timeout auto-advances along the script.
        pulse_btn(1);
        pulse_btn(1);
        check_eq(state == S_MSG, "Back in MSG");
        check_eq(msg_index == 0, "MSG re-entry starts at index 0");
        pulse_timeout();
        check_eq(state == S_MSG, "MSG stays on timeout, no sleep");
        check_eq(msg_index == golden_nav[0*4 + ACT_TIMEOUT], "timeout follows script from 0");

        // Button beats a simultaneous timeout in MSG (KEY0 -> HOME).
        pulse_btn(1);            // ensure in MSG at some index
        pulse_combo(4'b0001);    // KEY0 + timeout
        check_eq(state == S_HOME, "Button beats timeout in MSG");

        // Home timeout priority.
        pulse_btn(0);
        pulse_btn(1);
        check_eq(state == S_HOME, "Back in HOME for priority test");
        pulse_combo(4'b0001);    // KEY0 + timeout in HOME
        check_eq(state == S_SLEEP, "Timeout has priority in HOME");

        // ============================================================
        // Randomized model-vs-DUT campaign (now includes KEY3).
        // ============================================================
        exp_state = state;
        exp_index = msg_index;

        for (rand_iter = 0; rand_iter < 500; rand_iter = rand_iter + 1) begin
            // Drive stimulus on the negedge so it is stable before the posedge.
            @(negedge clk);
            case ($unsigned($random(seed)) % 5)
                0: btn_pulse = 4'b0000;
                1: btn_pulse = 4'b0001;  // KEY0
                2: btn_pulse = 4'b0010;  // KEY1
                3: btn_pulse = 4'b0100;  // KEY2
                4: btn_pulse = 4'b1000;  // KEY3
            endcase
            timeout_flag = (($random(seed) & 16'h00FF) == 8'h00);

            model_step(exp_state, exp_index, btn_pulse, timeout_flag, next_state, next_index);
            @(posedge clk);   // DUT samples
            #1;

            check_eq(state == next_state, "Randomized: state matches model");
            check_eq(msg_index == next_index, "Randomized: index matches model");
            check_eq(msg_index < MSG_COUNT, "Randomized: index always in range");

            exp_state = next_state;
            exp_index = next_index;
        end

        btn_pulse = 4'b0000;
        timeout_flag = 1'b0;

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
