// ============================================================================
// Module: idle_timer
// Project: DE10-Standard LCD Message System
// Description: Countdown timer with 1-second granularity.
//              Counts down from a runtime 'load_value' to 0.
//              Asserts 'timeout' flag when countdown reaches zero.
//              'reset_timer' input restarts the countdown (e.g., on button
//              press or a message context change) and reloads 'load_value'.
//              'seconds_remaining' output drives HEX display.
//              Caller selects load_value per use case (e.g. a fixed
//              Home/idle inactivity duration, or a per-message duration
//              from msg_duration_rom).
// ============================================================================

module idle_timer #(
    parameter CLK_FREQ_HZ  = 50_000_000,  // System clock frequency
    parameter SEC_CNT_W    = 6             // Width of seconds counter/output (0-63)
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 reset_timer,         // Pulse HIGH to reload+restart countdown
    input  wire                 enable,              // Timer counts only when enabled
    input  wire [SEC_CNT_W-1:0] load_value,          // Countdown starting value
    output reg                  timeout,             // HIGH when countdown expired
    output reg  [SEC_CNT_W-1:0] seconds_remaining    // Countdown value for HEX display
);

    // ----------------------------------------------------------------
    // Derived parameters
    // ----------------------------------------------------------------
    localparam ONE_SEC_TICKS = CLK_FREQ_HZ;                   // 50,000,000
    localparam TICK_CNT_W    = $clog2(ONE_SEC_TICKS + 1);     // 26 bits

    // ----------------------------------------------------------------
    // Internal registers
    // ----------------------------------------------------------------
    reg [TICK_CNT_W-1:0] tick_counter;   // Sub-second tick counter
    reg [SEC_CNT_W-1:0]  sec_counter;    // Seconds remaining (internal, full width)

    // ----------------------------------------------------------------
    // Main countdown logic
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Hardware reset — initialize all to starting values
            tick_counter      <= {TICK_CNT_W{1'b0}};
            sec_counter       <= load_value;
            timeout           <= 1'b0;
            seconds_remaining <= load_value;
        end else if (reset_timer) begin
            // Button press / context change — reload and restart countdown
            tick_counter      <= {TICK_CNT_W{1'b0}};
            sec_counter       <= load_value;
            timeout           <= 1'b0;
            seconds_remaining <= load_value;
        end else if (enable && !timeout) begin
            // Active countdown
            if (tick_counter == ONE_SEC_TICKS - 1) begin
                tick_counter <= {TICK_CNT_W{1'b0}};
                if (sec_counter == 0) begin
                    // Safety guard: already at 0, ensure timeout stays asserted.
                    // (Outer !timeout condition means we rarely enter here.)
                    timeout           <= 1'b1;
                    seconds_remaining <= {SEC_CNT_W{1'b0}};
                end else if (sec_counter == 1) begin
                    // Last second: decrement to 0 AND assert timeout simultaneously.
                    // This means timeout fires after exactly load_value seconds.
                    timeout           <= 1'b1;
                    sec_counter       <= {SEC_CNT_W{1'b0}};
                    seconds_remaining <= {SEC_CNT_W{1'b0}};
                end else begin
                    // Normal countdown: decrement sec_counter and update display.
                    sec_counter       <= sec_counter - 1'b1;
                    seconds_remaining <= sec_counter - 1'b1;
                end
            end else begin
                tick_counter <= tick_counter + 1'b1;
            end
        end
        // If !enable or timeout already asserted: hold state (do nothing)
    end

endmodule
