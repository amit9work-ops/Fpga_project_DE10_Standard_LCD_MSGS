// ============================================================================
// Module: message_fsm
// Project: DE10-Standard LCD Message System
// Description: Verilog FSM for UI/navigation control.
//
// States:
//   INIT  -> IDLE (automatic after reset release)
//   IDLE  -> HOME  (any button pulse)
//   HOME  -> IDLE  (KEY0)
//   HOME  -> MSG   (KEY1/KEY2)
//   HOME  -> SLEEP (timeout — Home/idle inactivity timer)
//   MSG   -> HOME  (KEY0)
//   MSG   -> MSG   (KEY1 next / KEY2 prev with wrap)
//   MSG   -> MSG   (timeout: auto-advance to next message, wrap — per-message
//                   duration slideshow. Buttons take priority over timeout.)
//   SLEEP -> IDLE  (any button pulse)
// ============================================================================

module message_fsm #(
    parameter integer MSG_COUNT = 18,
    parameter integer INDEX_W   = 5
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire [3:0]        btn_pulse,
    input  wire              timeout_flag,        // NOTE: must be a single-cycle
                                                    // pulse, not a level, or MSG
                                                    // auto-advance will repeat.

    output reg  [2:0]        state,
    output reg  [INDEX_W-1:0] msg_index
);

    localparam [2:0] S_INIT  = 3'd0;
    localparam [2:0] S_IDLE  = 3'd1;
    localparam [2:0] S_HOME  = 3'd2;
    localparam [2:0] S_MSG   = 3'd3;
    localparam [2:0] S_SLEEP = 3'd4;

    wire any_btn;
    assign any_btn = |btn_pulse;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_INIT;
            msg_index <= {INDEX_W{1'b0}};
        end else begin
            case (state)
                S_INIT: begin
                    state <= S_IDLE;
                end

                S_IDLE: begin
                    if (any_btn)
                        state <= S_HOME;
                end

                S_HOME: begin
                    if (timeout_flag)
                        state <= S_SLEEP;
                    else if (btn_pulse[0])
                        state <= S_IDLE;
                    else if (btn_pulse[1] || btn_pulse[2]) begin
                        state <= S_MSG;
                        msg_index <= {INDEX_W{1'b0}};
                    end
                end

                S_MSG: begin
                    // Buttons take priority over an auto-advance timeout
                    // that happens to fire on the same cycle.
                    if (btn_pulse[0]) begin
                        state <= S_HOME;
                    end else if (btn_pulse[1]) begin
                        if (msg_index == (MSG_COUNT - 1))
                            msg_index <= {INDEX_W{1'b0}};
                        else
                            msg_index <= msg_index + 1'b1;
                    end else if (btn_pulse[2]) begin
                        if (msg_index == {INDEX_W{1'b0}})
                            msg_index <= MSG_COUNT - 1;
                        else
                            msg_index <= msg_index - 1'b1;
                    end else if (timeout_flag) begin
                        // Per-message duration elapsed: auto-advance to the
                        // next message (wrap), stay in S_MSG (slideshow).
                        if (msg_index == (MSG_COUNT - 1))
                            msg_index <= {INDEX_W{1'b0}};
                        else
                            msg_index <= msg_index + 1'b1;
                    end
                end

                S_SLEEP: begin
                    if (any_btn)
                        state <= S_IDLE;
                end

                default: begin
                    state <= S_INIT;
                    msg_index <= {INDEX_W{1'b0}};
                end
            endcase
        end
    end

endmodule
