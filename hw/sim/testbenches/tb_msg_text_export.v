`timescale 1ns / 1ps
// ============================================================================
// tb_msg_text_export - checks the snapshot/seqlock stage.
//
// Proves:
//   * text_out and text_index advance together (one pipeline stage), so the
//     exported text always belongs to the exported index;
//   * seq increments exactly once per index change, and not while the index is
//     held;
//   * an index change that lands mid-read moves seq, so the HPS seqlock can
//     detect a torn read and retry.
//
// text_in models msg_text_rom(index) by replicating the index into every byte,
// so a consistent snapshot has text_out[4:0] == text_index.
// ============================================================================

module tb_msg_text_export;

    localparam CLK_PERIOD = 20;

    reg         clk = 1'b0;
    reg         rst_n;
    reg  [4:0]  drive_index;
    wire [511:0] text_in;

    wire [511:0] text_out;
    wire [4:0]   text_index;
    wire [2:0]   seq;
    wire [7:0]   status_out;

    // Model the combinational text ROM: every byte carries the index.
    assign text_in = {64{ {3'b000, drive_index} }};

    msg_text_export #(.INDEX_W(5)) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .msg_index  (drive_index),
        .text_in    (text_in),
        .text_out   (text_out),
        .text_index (text_index),
        .seq        (seq),
        .status_out (status_out)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num   = 0;

    reg [2:0] seq_before;

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

    // Continuous consistency monitor: whenever the design is out of reset and
    // settled, the exported text must match the exported index.
    reg monitor_on = 1'b0;
    reg consistency_ok = 1'b1;
    always @(posedge clk) begin
        if (monitor_on) begin
            if (text_out[4:0] !== text_index || text_out[7:5] !== 3'b000)
                consistency_ok = 1'b0;
        end
    end

    initial begin
        rst_n = 1'b0;
        drive_index = 5'd0;
        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;

        // After reset: index 0, seq 0.
        @(posedge clk); #1;
        check(text_index === 5'd0, "reset: text_index is 0");
        check(seq === 3'd0,        "reset: seq is 0");
        check(status_out === {seq, text_index}, "status packs seq and index");

        monitor_on = 1'b1;

        // Navigate to 5 -> snapshot latches, seq increments once.
        @(negedge clk) drive_index = 5'd5;
        @(posedge clk); #1;
        check(text_index === 5'd5, "index change latches text_index=5");
        check(text_out[4:0] === 5'd5, "snapshot text matches new index");
        check(seq === 3'd1, "seq increments on change");

        // Hold 5 for several cycles -> seq must not move.
        repeat (4) @(posedge clk);
        #1;
        check(seq === 3'd1, "seq stable while index held");

        // Change to 7 -> seq increments again.
        @(negedge clk) drive_index = 5'd7;
        @(posedge clk); #1;
        check(text_index === 5'd7 && seq === 3'd2, "second change tracked");

        // Tearing signal: capture seq, then let an index change land as if it
        // happened mid-read; the HPS would see a different seq and retry.
        seq_before = seq;
        @(negedge clk) drive_index = 5'd9;
        @(posedge clk); #1;
        check(seq !== seq_before, "mid-read index change moves seq (seqlock)");

        // Walk a range and rely on the continuous monitor for consistency.
        while (drive_index < 5'd17) begin
            @(negedge clk) drive_index = drive_index + 1'b1;
            @(posedge clk);
        end
        #1;
        check(consistency_ok, "text and index stayed consistent throughout");

        $display("=== RESULTS: %0d PASSED, %0d FAILED out of %0d tests ===",
                 pass_count, fail_count, test_num);
        if (fail_count == 0) $display("*** ALL TESTS PASSED ***");
        else                 $display("*** SOME TESTS FAILED ***");
        $finish;
    end

endmodule
