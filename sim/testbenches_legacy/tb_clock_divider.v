`timescale 1ns/1ps

module tb_clock_divider;
    localparam CLK_PERIOD_NS = 20;            // 50MHz
    localparam ONE_MS_CYCLES = 50_000;
    localparam ONE_S_CYCLES  = 50_000_000;

    reg  clk_50m;
    reg  reset_n;
    wire tick_1ms;
    wire tick_10ms;
    wire tick_100ms;
    wire tick_1s;

    integer tick_1ms_count   = 0;
    integer tick_10ms_count  = 0;
    integer tick_100ms_count = 0;
    integer tick_1s_count    = 0;

    integer test_num         = 0;
    integer pass_count       = 0;
    integer fail_count       = 0;
    integer width_errors     = 0;

    reg tick_1ms_prev;
    reg tick_10ms_prev;
    reg tick_100ms_prev;
    reg tick_1s_prev;

    clock_divider dut (
        .clk_50m    (clk_50m),
        .reset_n    (reset_n),
        .tick_1ms   (tick_1ms),
        .tick_10ms  (tick_10ms),
        .tick_100ms (tick_100ms),
        .tick_1s    (tick_1s)
    );

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

    initial begin
        clk_50m = 1'b0;
        forever #(CLK_PERIOD_NS/2) clk_50m = ~clk_50m;
    end

    always @(posedge tick_1ms)   tick_1ms_count   = tick_1ms_count + 1;
    always @(posedge tick_10ms)  tick_10ms_count  = tick_10ms_count + 1;
    always @(posedge tick_100ms) tick_100ms_count = tick_100ms_count + 1;
    always @(posedge tick_1s)    tick_1s_count    = tick_1s_count + 1;

    always @(posedge clk_50m) begin
        if (reset_n) begin
            if (tick_1ms_prev && tick_1ms)     width_errors = width_errors + 1;
            if (tick_10ms_prev && tick_10ms)   width_errors = width_errors + 1;
            if (tick_100ms_prev && tick_100ms) width_errors = width_errors + 1;
            if (tick_1s_prev && tick_1s)       width_errors = width_errors + 1;
        end

        tick_1ms_prev   <= tick_1ms;
        tick_10ms_prev  <= tick_10ms;
        tick_100ms_prev <= tick_100ms;
        tick_1s_prev    <= tick_1s;
    end

    initial begin
        $dumpfile("tb_clock_divider.vcd");
        $dumpvars(0, tb_clock_divider);

        reset_n = 1'b0;
        tick_1ms_prev = 1'b0;
        tick_10ms_prev = 1'b0;
        tick_100ms_prev = 1'b0;
        tick_1s_prev = 1'b0;

        #100;
        check((tick_1ms | tick_10ms | tick_100ms | tick_1s) == 1'b0, "All ticks low during reset");

        reset_n = 1'b1;
        $display("Waiting for first 1-second pulse...");

        // Wait for exactly first tick_1s (about 1 second of simulated time)
        wait (tick_1s_count == 1);

        // Allow same-cycle monitor updates to settle.
        @(posedge clk_50m);

        check(tick_1ms_count == 1000, "1ms tick count at first 1s pulse");
        check(tick_10ms_count == 100, "10ms tick count at first 1s pulse");
        check(tick_100ms_count == 10, "100ms tick count at first 1s pulse");
        check(tick_1s_count == 1, "1s tick count at first 1s pulse");

        // Run 100ms more and re-check strict counts.
        repeat (ONE_MS_CYCLES * 100) @(posedge clk_50m);
        check(tick_1ms_count == 1100, "1ms tick count after extra 100ms");
        check(tick_10ms_count == 110, "10ms tick count after extra 100ms");
        check(tick_100ms_count == 11, "100ms tick count after extra 100ms");
        check(tick_1s_count == 1, "1s tick count after extra 100ms");

        check(width_errors == 0, "All tick pulses are single-cycle");

        $display("");
        $display("=== RESULTS: %0d PASSED, %0d FAILED out of %0d tests ===",
                 pass_count, fail_count, test_num);
        if (fail_count == 0)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** SOME TESTS FAILED ***");

        $finish;
    end

    // Safety timeout: ~1.3 seconds simulation wall-clock in design time.
    initial begin
        repeat (ONE_S_CYCLES + (ONE_MS_CYCLES * 300)) @(posedge clk_50m);
        $display("FAIL [TIMEOUT] Simulation exceeded safety window");
        $finish;
    end

endmodule