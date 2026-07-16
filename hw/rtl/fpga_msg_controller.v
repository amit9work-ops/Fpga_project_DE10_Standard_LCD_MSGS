// ============================================================================
// Module: fpga_msg_controller
// Project: DE10-Standard LCD Message System
// Description: Top-level FPGA wrapper - ROUND 2 (category model). Integrates:
//              - button_debouncer (20ms, 4-channel)
//              - button_edge_detector (rising-edge pulse)
//              - message_fsm (3-state: INIT/MSG/SLEEP, table-driven nav)
//              - msg_nav_rom (category jump table + in_default flag)
//              - msg_duration_rom (per-message duration lookup)
//              - msg_text_rom + msg_text_export (wide bridge text interface)
//              - TWO idle_timer instances:
//                  1. per-message duration timer (always enabled; reloaded
//                     from msg_duration_rom; drives auto-advance within a
//                     category)
//                  2. system-idle "sleep" timer (enabled only while
//                     msg_nav_rom reports in_default; drives MSG->SLEEP)
//              - hex_display (7-seg decoder for HEX0-5)
//
//              Outputs are exposed as conduit signals for connection to
//              Avalon PIOs in Platform Designer (Qsys), readable by HPS
//              via the Lightweight H2F bridge.
// ============================================================================

module fpga_msg_controller #(
    parameter CLK_FREQ_HZ  = 50_000_000,
    parameter DEBOUNCE_MS  = 20,
    parameter TIMEOUT_SEC  = 60,        // System-idle (sleep) timeout, armed
                                         // only while parked in DEFAULT
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
    output wire                    timeout_flag,       // Per-message timer expired
    output wire [SEC_CNT_W-1:0]    seconds_remaining,  // Per-message countdown for display
    output wire [2:0]              fsm_state,          // Verilog UI FSM state (0=INIT,1=MSG,2=SLEEP)
    output wire [4:0]              fsm_msg_index,      // Verilog UI FSM message index

    // ---- Wide message-text bridge interface (readable by HPS) ----
    output wire [511:0]            msg_text_bus,       // registered snapshot of current
                                                        // message: byte B=line*16+col at
                                                        // [B*8 +: 8]. Top level slices this
                                                        // into 16 x 32-bit text PIOs.
    output wire [7:0]              msg_text_status,    // {seq[2:0], text_index[4:0]}

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
    //   3 states: INIT/MSG/SLEEP. msg_timeout_flag and sleep_timeout_flag
    //   into the FSM must each be single-cycle pulses (see the two
    //   button_edge_detector(NUM_BUTTONS=1) instances below), not the raw
    //   idle_timer levels, or the FSM would re-act every cycle the level
    //   stays high.
    // ================================================================
    localparam [2:0] FSM_S_MSG = 3'd1;  // must match message_fsm.v S_MSG

    wire msg_timeout_pulse;
    wire sleep_timeout_pulse;
    wire [2:0] nav_action;        // FSM -> nav ROM
    wire [4:0] nav_next_index;    // nav ROM -> FSM
    wire       in_default;        // nav ROM -> sleep-timer arming

    message_fsm #(
        .INDEX_W (5)
    ) u_message_fsm (
        .clk                (clk),
        .rst_n              (rst_n),
        .btn_pulse          (btn_pulse),
        .msg_timeout_flag   (msg_timeout_pulse),
        .sleep_timeout_flag (sleep_timeout_pulse),
        .nav_next_index     (nav_next_index),
        .state              (fsm_state),
        .msg_index          (fsm_msg_index),
        .nav_action         (nav_action)
    );

    // Table-driven navigation: (current index, action) -> next index, plus
    // in_default (true while fsm_msg_index is a DEFAULT-category message).
    // Combinational, so nav_next_index/in_default are valid before the FSM's
    // clock edge.
    msg_nav_rom u_msg_nav_rom (
        .cur_index  (fsm_msg_index),
        .action     (nav_action),
        .next_index (nav_next_index),
        .in_default (in_default)
    );

    // ================================================================
    // Message text ROM + snapshot export for the wide bridge interface
    //   The text ROM is combinational on the FSM index; msg_text_export
    //   registers the text and the index together so the exported pair
    //   is always consistent, and provides the seqlock sequence counter.
    // ================================================================
    wire [511:0] msg_text_rom_bus;
    msg_text_rom u_msg_text_rom (
        .msg_index (fsm_msg_index),
        .text_out  (msg_text_rom_bus)
    );

    msg_text_export #(
        .INDEX_W (5)
    ) u_msg_text_export (
        .clk        (clk),
        .rst_n      (rst_n),
        .msg_index  (fsm_msg_index),
        .text_in    (msg_text_rom_bus),
        .text_out   (msg_text_bus),
        .text_index (),                 // index echoed inside status_out
        .seq        (),
        .status_out (msg_text_status)
    );

    // ================================================================
    // Stage 4a: Per-message duration timer
    //   Always enabled; reloaded from msg_duration_rom for the current
    //   message. Drives the FSM's TIMEOUT nav action (advance within the
    //   current category, or fall back to DEFAULT / stick in EMERGENCY).
    //
    //   reset_timer (msg_timer_reload_strobe): fires on any button press
    //   (one cycle after the FSM updates, since both are clocked off the
    //   same edge, so fsm_msg_index already reflects the NEW value by the
    //   time this reload lands), OR when msg_index auto-advances while
    //   REMAINING in S_MSG (the one transition with no button pulse to key
    //   off of). Deliberately narrow: a plain state change into SLEEP must
    //   NOT reload the timer, or the just-asserted timeout would
    //   immediately clear itself again.
    // ================================================================
    wire any_btn_pulse;
    assign any_btn_pulse = |btn_pulse;

    wire msg_timer_timeout_level;

    button_edge_detector #(
        .NUM_BUTTONS (1)
    ) u_msg_timeout_edge (
        .clk           (clk),
        .rst_n         (rst_n),
        .btn_debounced (msg_timer_timeout_level),
        .btn_pulse     (msg_timeout_pulse)
    );

    reg [2:0]           fsm_state_d;
    reg [4:0]           fsm_msg_index_d;
    reg                 any_btn_pulse_d;
    reg                 in_default_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm_state_d     <= 3'd0;
            fsm_msg_index_d <= 5'd0;
            any_btn_pulse_d <= 1'b0;
            in_default_d    <= 1'b1;  // msg_index resets to 0, which is DEFAULT
        end else begin
            fsm_state_d     <= fsm_state;
            fsm_msg_index_d <= fsm_msg_index;
            any_btn_pulse_d <= any_btn_pulse;
            in_default_d    <= in_default;
        end
    end

    wire msg_auto_advance_reload = (fsm_state   == FSM_S_MSG) &&
                                    (fsm_state_d == FSM_S_MSG) &&
                                    (fsm_msg_index != fsm_msg_index_d);
    wire msg_timer_reload_strobe = any_btn_pulse_d || msg_auto_advance_reload;

    wire [SEC_CNT_W-1:0] msg_duration_value;
    msg_duration_rom #(
        .MSG_COUNT (18),
        .INDEX_W   (5),
        .DUR_W     (SEC_CNT_W)
    ) u_msg_duration_rom (
        .msg_index    (fsm_msg_index),
        .duration_sec (msg_duration_value)
    );

    idle_timer #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .SEC_CNT_W   (SEC_CNT_W)
    ) u_msg_timer (
        .clk               (clk),
        .rst_n             (rst_n),
        .reset_timer       (msg_timer_reload_strobe),
        .enable            (1'b1),
        .load_value        (msg_duration_value),
        .timeout           (msg_timer_timeout_level),
        .seconds_remaining (seconds_remaining)
    );

    assign timeout_flag = msg_timer_timeout_level;  // exported level, per-message timer

    // ================================================================
    // Stage 4b: System-idle ("sleep") timer
    //   Enabled only while in_default is true, so an active Exercise/
    //   Session/Emergency slideshow can never be interrupted by sleep.
    //   Reloaded fresh (a) on any button press (activity resets idle), or
    //   (b) the instant msg_index transitions INTO the DEFAULT category
    //   (a rising edge on in_default) -- covers both an explicit KEY3 press
    //   and arriving at DEFAULT via a category-end timeout fallback, so the
    //   idle window always starts counting from the moment DEFAULT is
    //   actually reached rather than resuming a stale paused count.
    // ================================================================
    wire in_default_rising = in_default && !in_default_d;
    wire sleep_timer_reload_strobe = any_btn_pulse_d || in_default_rising;

    wire sleep_timer_timeout_level;
    wire [SEC_CNT_W-1:0] sleep_seconds_remaining_unused;

    idle_timer #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .SEC_CNT_W   (SEC_CNT_W)
    ) u_sleep_timer (
        .clk               (clk),
        .rst_n             (rst_n),
        .reset_timer       (sleep_timer_reload_strobe),
        .enable            (in_default),
        .load_value        (TIMEOUT_SEC[SEC_CNT_W-1:0]),
        .timeout           (sleep_timer_timeout_level),
        .seconds_remaining (sleep_seconds_remaining_unused)
    );

    button_edge_detector #(
        .NUM_BUTTONS (1)
    ) u_sleep_timeout_edge (
        .clk           (clk),
        .rst_n         (rst_n),
        .btn_debounced (sleep_timer_timeout_level),
        .btn_pulse     (sleep_timeout_pulse)
    );

    // ================================================================
    // Stage 5: HEX Display
    //   HEX5: Timer tens digit
    //   HEX4: Timer ones digit
    //   HEX2: Last button pressed (0-3, F=none)
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

    // Current message number (0-17), shown only while a message is
    // actually displayed; reads 00 in INIT/SLEEP.
    wire [3:0] msg_tens_digit = (fsm_state == FSM_S_MSG) ? (fsm_msg_index / 10) : 4'h0;
    wire [3:0] msg_ones_digit = (fsm_state == FSM_S_MSG) ? (fsm_msg_index % 10) : 4'h0;

    hex_display u_hex (
        .digit0 (msg_ones_digit),           // HEX0: message number, ones digit
        .digit1 (msg_tens_digit),           // HEX1: message number, tens digit
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
