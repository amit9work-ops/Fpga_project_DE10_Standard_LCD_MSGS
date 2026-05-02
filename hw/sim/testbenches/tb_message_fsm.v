`timescale 1ns/1ps

module tb_message_fsm;

    localparam CLK_PERIOD_NS = 10;
    localparam MSG_COUNT = 18;
    localparam INDEX_W = 5;

    localparam [2:0] S_INIT  = 3'd0;
    localparam [2:0] S_IDLE  = 3'd1;
    localparam [2:0] S_HOME  = 3'd2;
    localparam [2:0] S_MSG   = 3'd3;
    localparam [2:0] S_SLEEP = 3'd4;

    reg clk;
    reg rst_n;
    reg [3:0] btn_pulse;
    reg timeout_flag;

    wire [2:0] state;
    wire [INDEX_W-1:0] msg_index;

    integer test_num = 0;
    integer pass_count = 0;
    integer fail_count = 0;
    integer rand_iter;
    integer seed;

    reg [2:0] exp_state;
    reg [INDEX_W-1:0] exp_index;
    reg [2:0] next_state;
    reg [INDEX_W-1:0] next_index;

    message_fsm #(
        .MSG_COUNT(MSG_COUNT),
        .INDEX_W(INDEX_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .btn_pulse(btn_pulse),
        .timeout_flag(timeout_flag),
        .state(state),
        .msg_index(msg_index)
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

    task pulse_btn;
        input integer idx;
        begin
            btn_pulse = 4'b0000;
            btn_pulse[idx] = 1'b1;
            @(posedge clk);
            btn_pulse = 4'b0000;
            @(posedge clk);
        end
    endtask

    task pulse_vec;
        input [3:0] vec;
        begin
            btn_pulse = vec;
            @(posedge clk);
            btn_pulse = 4'b0000;
            @(posedge clk);
        end
    endtask

    task model_step;
        input  [2:0] in_state;
        input  [INDEX_W-1:0] in_index;
        input  [3:0] in_btn;
        input        in_timeout;
        output [2:0] out_state;
        output [INDEX_W-1:0] out_index;
        begin
            out_state = in_state;
            out_index = in_index;

            case (in_state)
                S_INIT: begin
                    out_state = S_IDLE;
                end

                S_IDLE: begin
                    if (|in_btn)
                        out_state = S_HOME;
                end

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
                    if (in_timeout)
                        out_state = S_SLEEP;
                    else if (in_btn[0])
                        out_state = S_HOME;
                    else if (in_btn[1]) begin
                        if (in_index == (MSG_COUNT - 1))
                            out_index = {INDEX_W{1'b0}};
                        else
                            out_index = in_index + 1'b1;
                    end else if (in_btn[2]) begin
                        if (in_index == {INDEX_W{1'b0}})
                            out_index = MSG_COUNT - 1;
                        else
                            out_index = in_index - 1'b1;
                    end
                end

                S_SLEEP: begin
                    if (|in_btn)
                        out_state = S_IDLE;
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
        $display("=== TB: message_fsm ===");
        $dumpfile("tb_message_fsm.vcd");
        $dumpvars(0, tb_message_fsm);

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

        // IDLE -> HOME by any button (KEY3 here)
        pulse_btn(3);
        check_eq(state == S_HOME, "IDLE -> HOME on any button pulse");

        // HOME -> IDLE by KEY0
        pulse_btn(0);
        check_eq(state == S_IDLE, "HOME -> IDLE on KEY0");

        // IDLE -> HOME, then HOME -> MSG via KEY1
        pulse_btn(1);
        check_eq(state == S_HOME, "IDLE -> HOME (second entry)");
        pulse_btn(1);
        check_eq(state == S_MSG, "HOME -> MSG on KEY1");
        check_eq(msg_index == 0, "MSG starts at index 0");

        // Next message increments
        pulse_btn(1);
        check_eq(state == S_MSG, "Stay in MSG on KEY1 next");
        check_eq(msg_index == 1, "Index increments to 1");

        // Advance to wrap point
        repeat (17) pulse_btn(1);
        check_eq(msg_index == 0, "Index wraps from 17 -> 0");

        // Previous from 0 wraps to 17
        pulse_btn(2);
        check_eq(msg_index == 17, "Index wraps from 0 -> 17 on KEY2");

        // MSG -> HOME on KEY0
        pulse_btn(0);
        check_eq(state == S_HOME, "MSG -> HOME on KEY0");

        // HOME timeout -> SLEEP
        timeout_flag = 1'b1;
        @(posedge clk);
        timeout_flag = 1'b0;
        @(posedge clk);
        check_eq(state == S_SLEEP, "HOME -> SLEEP on timeout");

        // SLEEP wake-up -> IDLE on any key
        pulse_btn(2);
        check_eq(state == S_IDLE, "SLEEP -> IDLE on any key");

        // Enter MSG again to test timeout priority over key activity
        pulse_btn(1);
        pulse_btn(1);
        check_eq(state == S_MSG, "Back in MSG for timeout-priority test");

        timeout_flag = 1'b1;
        btn_pulse = 4'b0010; // KEY1 simultaneously
        @(posedge clk);
        timeout_flag = 1'b0;
        btn_pulse = 4'b0000;
        @(posedge clk);
        check_eq(state == S_SLEEP, "Timeout has priority in MSG");

        // Home timeout priority test
        pulse_btn(0); // wake to IDLE
        pulse_btn(1); // IDLE->HOME
        check_eq(state == S_HOME, "Back in HOME for priority test");

        timeout_flag = 1'b1;
        btn_pulse = 4'b0001; // KEY0 simultaneously
        @(posedge clk);
        timeout_flag = 1'b0;
        btn_pulse = 4'b0000;
        @(posedge clk);
        check_eq(state == S_SLEEP, "Timeout has priority in HOME");

        // ============================================================
        // KEY3 no-op behavior in HOME and MSG
        // ============================================================
        pulse_btn(2); // wake to IDLE
        pulse_btn(1); // IDLE->HOME
        check_eq(state == S_HOME, "HOME entered for KEY3 no-op test");
        exp_index = msg_index;
        pulse_vec(4'b1000); // KEY3 only
        check_eq(state == S_HOME, "HOME stays on KEY3 no-op");
        check_eq(msg_index == exp_index, "HOME index unchanged on KEY3");

        pulse_btn(1); // HOME->MSG
        check_eq(state == S_MSG, "MSG entered for KEY3 no-op test");
        pulse_btn(1); // increment to 1
        exp_index = msg_index;
        pulse_vec(4'b1000); // KEY3 only
        check_eq(state == S_MSG, "MSG stays on KEY3 no-op");
        check_eq(msg_index == exp_index, "MSG index unchanged on KEY3");

        // ============================================================
        // SLEEP wake on KEY3
        // ============================================================
        timeout_flag = 1'b1;
        @(posedge clk);
        timeout_flag = 1'b0;
        @(posedge clk);
        check_eq(state == S_SLEEP, "Enter SLEEP for KEY3 wake test");
        pulse_vec(4'b1000);
        check_eq(state == S_IDLE, "SLEEP -> IDLE on KEY3 wake");

        // SLEEP wake on KEY0 and KEY1
        pulse_btn(1); // IDLE->HOME
        timeout_flag = 1'b1;
        @(posedge clk);
        timeout_flag = 1'b0;
        @(posedge clk);
        check_eq(state == S_SLEEP, "Enter SLEEP for KEY0 wake test");
        pulse_vec(4'b0001);
        check_eq(state == S_IDLE, "SLEEP -> IDLE on KEY0 wake");

        pulse_btn(1); // IDLE->HOME
        timeout_flag = 1'b1;
        @(posedge clk);
        timeout_flag = 1'b0;
        @(posedge clk);
        check_eq(state == S_SLEEP, "Enter SLEEP for KEY1 wake test");
        pulse_vec(4'b0010);
        check_eq(state == S_IDLE, "SLEEP -> IDLE on KEY1 wake");

        // ============================================================
        // Multi-key priority in HOME
        // ============================================================
        pulse_btn(1); // IDLE->HOME
        check_eq(state == S_HOME, "HOME entered for multi-key test");
        pulse_vec(4'b0011); // KEY0+KEY1
        check_eq(state == S_IDLE, "HOME: KEY0+KEY1 -> IDLE (KEY0 priority)");

        pulse_btn(1); // IDLE->HOME
        pulse_vec(4'b0110); // KEY1+KEY2
        check_eq(state == S_MSG, "HOME: KEY1+KEY2 -> MSG");
        check_eq(msg_index == 0, "HOME: KEY1+KEY2 resets index");
        pulse_btn(0); // MSG->HOME
        pulse_vec(4'b0101); // KEY0+KEY2
        check_eq(state == S_IDLE, "HOME: KEY0+KEY2 -> IDLE (KEY0 priority)");

        pulse_btn(1); // IDLE->HOME
        pulse_vec(4'b1111); // all keys
        check_eq(state == S_IDLE, "HOME: all keys -> IDLE (KEY0 priority)");

        // ============================================================
        // Multi-key priority in MSG
        // ============================================================
        pulse_btn(1); // IDLE->HOME
        pulse_btn(1); // HOME->MSG
        check_eq(state == S_MSG, "MSG entered for multi-key test");
        check_eq(msg_index == 0, "MSG index reset before multi-key test");
        pulse_vec(4'b0110); // KEY1+KEY2
        check_eq(state == S_MSG, "MSG: KEY1+KEY2 stays in MSG");
        check_eq(msg_index == 1, "MSG: KEY1 priority over KEY2");

        pulse_vec(4'b0011); // KEY0+KEY1
        check_eq(state == S_HOME, "MSG: KEY0+KEY1 -> HOME (KEY0 priority)");

        pulse_btn(1); // HOME->MSG
        pulse_vec(4'b0101); // KEY0+KEY2
        check_eq(state == S_HOME, "MSG: KEY0+KEY2 -> HOME (KEY0 priority)");

        pulse_btn(1); // HOME->MSG
        pulse_vec(4'b1111); // all keys
        check_eq(state == S_HOME, "MSG: all keys -> HOME (KEY0 priority)");

        // ============================================================
        // Reset while in HOME/MSG/SLEEP
        // ============================================================
        pulse_btn(1); // HOME->MSG
        check_eq(state == S_MSG, "MSG entered for reset test");
        rst_n = 1'b0;
        @(posedge clk);
        check_eq(state == S_INIT, "Reset forces INIT from MSG");
        rst_n = 1'b1;
        @(posedge clk);
        check_eq(state == S_IDLE, "INIT -> IDLE after reset (MSG path)");

        pulse_btn(1); // IDLE->HOME
        check_eq(state == S_HOME, "HOME entered for reset test");
        rst_n = 1'b0;
        @(posedge clk);
        check_eq(state == S_INIT, "Reset forces INIT from HOME");
        rst_n = 1'b1;
        @(posedge clk);
        check_eq(state == S_IDLE, "INIT -> IDLE after reset (HOME path)");

        pulse_btn(1); // IDLE->HOME
        timeout_flag = 1'b1;
        @(posedge clk);
        timeout_flag = 1'b0;
        @(posedge clk);
        check_eq(state == S_SLEEP, "Enter SLEEP for reset test");
        rst_n = 1'b0;
        @(posedge clk);
        check_eq(state == S_INIT, "Reset forces INIT from SLEEP");
        rst_n = 1'b1;
        @(posedge clk);
        check_eq(state == S_IDLE, "INIT -> IDLE after reset (SLEEP path)");

        // ============================================================
        // TEST 20+: Randomized model-vs-DUT campaign
        // ============================================================
        exp_state = state;
        exp_index = msg_index;

        for (rand_iter = 0; rand_iter < 500; rand_iter = rand_iter + 1) begin
            case ($random(seed) & 3)
                2'd0: btn_pulse = 4'b0000;
                2'd1: btn_pulse = 4'b0001;
                2'd2: btn_pulse = 4'b0010;
                2'd3: btn_pulse = 4'b0100;
            endcase
            timeout_flag = (($random(seed) & 16'h00FF) == 8'h00);

            model_step(exp_state, exp_index, btn_pulse, timeout_flag, next_state, next_index);

            @(posedge clk);

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
        repeat (2000) @(posedge clk);
        $display("FAIL [TIMEOUT] FSM TB exceeded safety window");
        $finish;
    end

endmodule
