// ============================================================================
// Module: fpga_msg_controller
// Project: DE10-Standard LCD Message System
// Description: Top-level FPGA wrapper that integrates all custom modules:
//              - button_debouncer (20ms, 4-channel)
//              - button_edge_detector (rising-edge pulse)
//              - idle_timer (runtime-loaded countdown)
//              - msg_duration_rom (per-message duration lookup)
//              - message_fsm (navigation + MSG-state auto-advance slideshow)
//              - hex_display (7-seg decoder for HEX0-5)
//
//              idle_timer's load_value is muxed by FSM state: HOME/IDLE use
//              the fixed TIMEOUT_SEC (default 60s) inactivity timeout;
//              MSG uses the current message's duration from msg_duration_rom,
//              driving message_fsm's auto-advance slideshow behavior.
//
//              Outputs are exposed as conduit signals for connection to
//              Avalon PIOs in Platform Designer (Qsys), readable by HPS
//              via the Lightweight H2F bridge.
// ============================================================================

module fpga_msg_controller #(
    parameter CLK_FREQ_HZ  = 50_000_000,
    parameter DEBOUNCE_MS  = 20,
    parameter TIMEOUT_SEC  = 60,        // Home/idle inactivity timeout (S_MSG
                                         // uses per-message duration instead)
    parameter NUM_BUTTONS  = 4,
    parameter SEC_CNT_W    = 6          // Width of seconds_remaining (0-63)
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // ---- Button inputs (active-LOW from KEY pins) ----
    input  wire [NUM_BUTTONS-1:0]  key_in,

    // ---- Outputs to PIO conduit exports (readable by HPS) ----
    output wire [NUM_BUTTONS-1:0]  btn_pulse,         // Single-cycle press events
    output wire [NUM_BUTTONS-1:0]  btn_debounced,     // Current debounced levels
    output wire                    timeout_flag,       // Idle timer expired
    output wire [SEC_CNT_W-1:0]    seconds_remaining,  // Countdown for display
    output wire [2:0]              fsm_state,          // Verilog UI FSM state
    output wire [4:0]              fsm_msg_index,      // Verilog UI FSM message index

    // ---- HEX display outputs (active-LOW 7-segment) ----
    output wire [6:0]              hex0,
    output wire [6:0]              hex1,
    output wire [6:0]              hex2,
    output wire [6:0]              hex3,
    output wire [6:0]              hex4,
    output wire [6:0]              hex5
);

    // ================================================================
    // Stage 1: Button Debouncing
    // ================================================================
    button_debouncer #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .DEBOUNCE_MS (DEBOUNCE_MS),
        .NUM_BUTTONS (NUM_BUTTONS)
    ) u_debouncer (
        .clk     (clk),
        .rst_n   (rst_n),
        .btn_in  (key_in),
        .btn_out (btn_debounced)
    );

    // ================================================================
    // Stage 2: Edge Detection (single-cycle pulse per press)
    // ================================================================
    button_edge_detector #(
        .NUM_BUTTONS (NUM_BUTTONS)
    ) u_edge_det (
        .clk           (clk),
        .rst_n         (rst_n),
        .btn_debounced (btn_debounced),
        .btn_pulse     (btn_pulse)
    );

    // ================================================================
    // Stage 3: Verilog UI FSM (project-critical control logic)
    //   Instantiated before the timer so its outputs (fsm_state,
    //   fsm_msg_index) are available combinationally to drive the
    //   duration mux below. timeout_flag into the FSM must be a
    //   single-cycle pulse (see msg_fsm_timeout_pulse), not the raw
    //   idle_timer level, or MSG would auto-advance every cycle the
    //   level stays high.
    // ================================================================
    localparam [2:0] FSM_S_MSG = 3'd3;  // must match message_fsm.v S_MSG

    wire msg_fsm_timeout_pulse;

    message_fsm #(
        .MSG_COUNT (18),
        .INDEX_W   (5)
    ) u_message_fsm (
        .clk         (clk),
        .rst_n       (rst_n),
        .btn_pulse   (btn_pulse),
        .timeout_flag(msg_fsm_timeout_pulse),
        .state       (fsm_state),
        .msg_index   (fsm_msg_index)
    );

    // ================================================================
    // Stage 4: Per-message duration lookup + Idle Timer
    //   load_value: HOME/IDLE use the fixed TIMEOUT_SEC inactivity
    //   timeout; MSG uses the current message's duration so the timer
    //   drives an auto-advance slideshow instead of sleeping.
    //
    //   reset_timer (timer_reload_strobe): fires on any button press
    //   (one cycle after the FSM updates, since both are clocked off
    //   the same edge, so fsm_state/fsm_msg_index already reflect the
    //   NEW value by the time this reload lands — covers every
    //   button-driven transition, including Home<->MSG and in-MSG
    //   next/prev), OR when msg_index auto-advances while REMAINING in
    //   S_MSG (the one transition with no button pulse to key off of).
    //   Deliberately narrow: a plain state change into SLEEP (or any
    //   other non-button transition) must NOT reload the timer, or the
    //   just-asserted timeout would immediately clear itself again.
    // ================================================================
    wire any_btn_pulse;
    assign any_btn_pulse = |btn_pulse;

    wire timer_timeout_level;

    button_edge_detector #(
        .NUM_BUTTONS (1)
    ) u_timeout_edge (
        .clk           (clk),
        .rst_n         (rst_n),
        .btn_debounced (timer_timeout_level),
        .btn_pulse     (msg_fsm_timeout_pulse)
    );

    reg [2:0]           fsm_state_d;
    reg [4:0]           fsm_msg_index_d;
    reg                 any_btn_pulse_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm_state_d     <= 3'd0;
            fsm_msg_index_d <= 5'd0;
            any_btn_pulse_d <= 1'b0;
        end else begin
            fsm_state_d     <= fsm_state;
            fsm_msg_index_d <= fsm_msg_index;
            any_btn_pulse_d <= any_btn_pulse;
        end
    end

    wire msg_auto_advance_reload = (fsm_state   == FSM_S_MSG) &&
                                    (fsm_state_d == FSM_S_MSG) &&
                                    (fsm_msg_index != fsm_msg_index_d);
    wire timer_reload_strobe = any_btn_pulse_d || msg_auto_advance_reload;

    wire [SEC_CNT_W-1:0] msg_duration_value;
    msg_duration_rom #(
        .MSG_COUNT (18),
        .INDEX_W   (5),
        .DUR_W     (SEC_CNT_W)
    ) u_msg_duration_rom (
        .msg_index    (fsm_msg_index),
        .duration_sec (msg_duration_value)
    );

    wire [SEC_CNT_W-1:0] timer_load_value =
        (fsm_state == FSM_S_MSG) ? msg_duration_value : TIMEOUT_SEC[SEC_CNT_W-1:0];

    idle_timer #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .SEC_CNT_W   (SEC_CNT_W)
    ) u_timer (
        .clk               (clk),
        .rst_n             (rst_n),
        .reset_timer       (timer_reload_strobe),
        .enable            (1'b1),
        .load_value        (timer_load_value),
        .timeout           (timer_timeout_level),
        .seconds_remaining (seconds_remaining)
    );

    assign timeout_flag = timer_timeout_level;  // exported level, unchanged contract

    // ================================================================
    // Stage 5: HEX Display
    //   HEX5: Timer tens digit
    //   HEX4: Timer ones digit
    //   HEX2: Last button pressed (0–3, F=none)
    //   HEX0/1/3: Reserved (show 0)
    // ================================================================
    // Encode which button was last pressed (priority: KEY0 > KEY1 > KEY2 > KEY3)
    reg [3:0] last_btn_display;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            last_btn_display <= 4'hF;
        else if (btn_pulse[0])
            last_btn_display <= 4'd0;
        else if (btn_pulse[1])
            last_btn_display <= 4'd1;
        else if (btn_pulse[2])
            last_btn_display <= 4'd2;
        else if (btn_pulse[3])
            last_btn_display <= 4'd3;
        // else: hold last value
    end

    wire [3:0] timer_tens_digit;
    wire [3:0] timer_ones_digit;
    assign timer_tens_digit = seconds_remaining / 10;
    assign timer_ones_digit = seconds_remaining % 10;

    hex_display u_hex (
        .digit0 (4'h0),                     // HEX0: reserved
        .digit1 (4'h0),                     // HEX1: reserved
        .digit2 (last_btn_display),         // HEX2: last button (F=none)
        .digit3 (4'h0),                     // HEX3: reserved
        .digit4 (timer_ones_digit),         // HEX4: timer ones digit
        .digit5 (timer_tens_digit),         // HEX5: timer tens digit
        .hex0   (hex0),
        .hex1   (hex1),
        .hex2   (hex2),
        .hex3   (hex3),
        .hex4   (hex4),
        .hex5   (hex5)
    );

endmodule
