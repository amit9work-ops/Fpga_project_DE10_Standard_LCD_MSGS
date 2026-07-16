// ============================================================================
// Module: message_fsm
// Project: DE10-Standard LCD Message System
// Description: Verilog FSM for UI/navigation control - ROUND 2 (category
//              model, per advisor design): 3 states, not 5. Each of the 4
//              keys jumps to a FIXED category head via msg_nav_rom, and the
//              per-message duration timer advances sequentially within the
//              current category on expiry.
//
// States:
//   INIT  -> MSG   (automatic after reset release; msg_index starts at 0,
//                    the DEFAULT category head)
//   MSG   -> MSG   (any of KEY0-3: jump to that key's category head;
//                    msg_timeout_flag with no button: advance within the
//                    category per msg_nav_rom's TIMEOUT action)
//   MSG   -> SLEEP (sleep_timeout_flag, with no button and no msg_timeout
//                    on the same cycle -- the caller only pulses this while
//                    parked in the DEFAULT category, see fpga_msg_controller)
//   SLEEP -> MSG   (any key: wake directly to that key's category head,
//                    one hop, not through an intermediate IDLE/HOME state)
//
// Priority on a same-cycle collision: KEY0 > KEY1 > KEY2 > KEY3 >
// msg_timeout_flag > sleep_timeout_flag. Buttons always win over either
// timer; the per-message timer wins over the sleep timer (advancing within
// an active category takes priority over going to sleep).
//
// msg_index is looked up externally: nav_action (comb, this module) feeds
// msg_nav_rom.v together with the CURRENT msg_index, and the combinational
// result (nav_next_index) is what gets loaded on the next clock edge. This
// keeps message_fsm.v free of any category-membership knowledge -- that
// lives entirely in the generated msg_nav_rom.v.
// ============================================================================

module message_fsm #(
    parameter integer INDEX_W = 5
)(
    input  wire               clk,
    input  wire                rst_n,
    input  wire [3:0]          btn_pulse,
    input  wire                msg_timeout_flag,    // per-message duration expired
                                                      // (single-cycle pulse)
    input  wire                sleep_timeout_flag,   // system-idle timer expired
                                                      // (single-cycle pulse; caller
                                                      // arms this only in DEFAULT)
    input  wire [INDEX_W-1:0]  nav_next_index,       // from msg_nav_rom(msg_index, nav_action)

    output reg  [2:0]          state,
    output reg  [INDEX_W-1:0]  msg_index,
    output reg  [2:0]          nav_action            // to msg_nav_rom (valid every cycle)
);

    localparam [2:0] S_INIT  = 3'd0;
    localparam [2:0] S_MSG   = 3'd1;
    localparam [2:0] S_SLEEP = 3'd2;

    // Action encoding -- must match msg_nav_rom.v / gen_msg_tables.py.
    localparam [2:0] ACT_KEY0    = 3'd0;  // -> EXERCISE head
    localparam [2:0] ACT_KEY1    = 3'd1;  // -> SESSION head
    localparam [2:0] ACT_KEY2    = 3'd2;  // -> EMERGENCY head
    localparam [2:0] ACT_KEY3    = 3'd3;  // -> DEFAULT head
    localparam [2:0] ACT_TIMEOUT = 3'd4;  // sequential advance within category

    wire any_btn;
    assign any_btn = |btn_pulse;

    // Combinational action select, valid every cycle so nav_next_index is
    // ready before the clock edge that consumes it (whether that edge is a
    // key-driven jump or a timeout-driven advance).
    always @(*) begin
        if (btn_pulse[0])      nav_action = ACT_KEY0;
        else if (btn_pulse[1]) nav_action = ACT_KEY1;
        else if (btn_pulse[2]) nav_action = ACT_KEY2;
        else if (btn_pulse[3]) nav_action = ACT_KEY3;
        else                   nav_action = ACT_TIMEOUT;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_INIT;
            msg_index <= {INDEX_W{1'b0}};
        end else begin
            case (state)
                S_INIT: begin
                    state <= S_MSG;
                    // msg_index already 0 from reset; explicit for clarity.
                    msg_index <= {INDEX_W{1'b0}};
                end

                S_MSG: begin
                    if (any_btn) begin
                        // KEY0-3: jump to that key's fixed category head.
                        msg_index <= nav_next_index;
                    end else if (msg_timeout_flag) begin
                        // Per-message duration elapsed: advance within the
                        // current category (or fall back to DEFAULT / stick
                        // in EMERGENCY, per msg_nav_rom's TIMEOUT mapping).
                        msg_index <= nav_next_index;
                    end else if (sleep_timeout_flag) begin
                        state <= S_SLEEP;
                    end
                end

                S_SLEEP: begin
                    if (any_btn) begin
                        state     <= S_MSG;
                        msg_index <= nav_next_index;
                    end
                end

                default: begin
                    state     <= S_INIT;
                    msg_index <= {INDEX_W{1'b0}};
                end
            endcase
        end
    end

endmodule
