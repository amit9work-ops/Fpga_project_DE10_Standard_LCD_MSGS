// ============================================================================
// Module: msg_duration_rom
// Project: DE10-Standard LCD Message System
// Description: Compile-time lookup table giving each message (indexed the
//              same way as sw/hps_app/messages.h MSG_LIST) its own display
//              duration in seconds. Consumed by fpga_msg_controller as the
//              idle_timer reload value while in S_MSG state, enabling the
//              auto-advance slideshow behavior.
//
//              Tune by hand-editing the case table below and re-synthesizing
//              (same workflow as editing message text in messages.h).
//              Keep entries in the same index order as MSG_LIST.
// ============================================================================

module msg_duration_rom #(
    parameter integer MSG_COUNT = 18,
    parameter integer INDEX_W   = 5,
    parameter integer DUR_W     = 6
)(
    input  wire [INDEX_W-1:0] msg_index,
    output reg  [DUR_W-1:0]   duration_sec
);

    always @(*) begin
        case (msg_index)
            5'd0:  duration_sec = 6'd12; // Amit Damari / Ido Zylberman (welcome)
            5'd1:  duration_sec = 6'd10; // Eytan Mann / Project 3420
            5'd2:  duration_sec = 6'd8;  // TAU / Tel Aviv / University
            5'd3:  duration_sec = 6'd8;  // Exercise 1 of 4 - Breathe In Deep, Hold 8 Seconds
            5'd4:  duration_sec = 6'd10; // Exercise 2 of 4 - Breathe Out Now, Slow and Steady
            5'd5:  duration_sec = 6'd10; // Exercise 3 of 4 - Raise Both Arms, Hold 10 Seconds
            5'd6:  duration_sec = 6'd10; // Exercise 4 of 4 - Lower Arms Down, Relax and Rest
            5'd7:  duration_sec = 6'd15; // REST TIME - Take a Break, Drink Water
            5'd8:  duration_sec = 6'd10; // Please Wait - Therapist Is On the Way
            5'd9:  duration_sec = 6'd10; // Your Turn Soon - Stay Seated, We Will Call
            5'd10: duration_sec = 6'd12; // IMPORTANT - Need Help Now, Press Any Key
            5'd11: duration_sec = 6'd12; // Do Not Leave - Stay In Room Until Called
            5'd12: duration_sec = 6'd10; // Session Paused - Please Wait, Will Resume
            5'd13: duration_sec = 6'd10; // Session Active - In Progress, Do Not Disturb
            5'd14: duration_sec = 6'd8;  // Well Done - Exercise Set Completed
            5'd15: duration_sec = 6'd10; // Session Done - Please Wait For Discharge
            5'd16: duration_sec = 6'd6;  // ATTENTION - Staff Called, Help Coming
            5'd17: duration_sec = 6'd12; // System Ready - Press Any Key To Begin
            default: duration_sec = 6'd10;
        endcase
    end

endmodule
