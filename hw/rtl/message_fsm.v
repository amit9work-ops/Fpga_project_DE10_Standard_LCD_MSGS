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
//   MSG   -> MSG   (KEY1/KEY2/KEY3/timeout: next index from msg_nav_rom)
//   SLEEP -> IDLE  (any button pulse)
//
// Navigation is TABLE-DRIVEN, not a linear +1/-1 walk. In S_MSG the FSM emits
// a 2-bit action to msg_nav_rom and loads the returned next index. The next
// index therefore depends on WHICH key was pressed:
//   KEY1 = next within category, KEY2 = head of next category,
//   KEY3 = jump to emergency, timeout = scripted idle flow.
// Buttons take priority over a same-cycle timeout (KEY0 highest).
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
    input  wire [INDEX_W-1:0] nav_next_index,     // from msg_nav_rom(msg_index, nav_action)

    output reg  [2:0]        state,
    output reg  [INDEX_W-1:0] msg_index,
    output reg  [1:0]        nav_action           // to msg_nav_rom (valid in S_MSG)
);

    localparam [2:0] S_INIT  = 3'd0;
    localparam [2:0] S_IDLE  = 3'd1;
    localparam [2:0] S_HOME  = 3'd2;
    localparam [2:0] S_MSG   = 3'd3;
    localparam [2:0] S_SLEEP = 3'd4;

    // Action encoding — must match msg_nav_rom.v / gen_msg_tables.py.
    localparam [1:0] ACT_KEY1    = 2'd0;  // next within category
    localparam [1:0] ACT_KEY2    = 2'd1;  // head of next category
    localparam [1:0] ACT_KEY3    = 2'd2;  // jump to emergency
    localparam [1:0] ACT_TIMEOUT = 2'd3;  // scripted idle flow

    wire any_btn;
    assign any_btn = |btn_pulse;

    // Combinational action select. Priority KEY1 > KEY2 > KEY3 > timeout; this
    // drives msg_nav_rom so nav_next_index is valid before the clock edge.
    // (KEY0 is handled separately as MSG->HOME and does not use the nav ROM.)
    always @(*) begin
        if (btn_pulse[1])
            nav_action = ACT_KEY1;
        else if (btn_pulse[2])
            nav_action = ACT_KEY2;
        else if (btn_pulse[3])
            nav_action = ACT_KEY3;
        else
            nav_action = ACT_TIMEOUT;
    end

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
                    // KEY0 (back) has top priority. Any of KEY1/KEY2/KEY3, or a
                    // same-cycle timeout, load the next index from the nav ROM;
                    // nav_action (above) selects which mapping applies, so a
                    // single assignment covers all four cases. Buttons beat the
                    // timeout because when any of them is high nav_action is not
                    // ACT_TIMEOUT.
                    if (btn_pulse[0]) begin
                        state <= S_HOME;
                    end else if (btn_pulse[1] || btn_pulse[2] || btn_pulse[3]) begin
                        msg_index <= nav_next_index;
                    end else if (timeout_flag) begin
                        msg_index <= nav_next_index;
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
