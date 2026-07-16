// ============================================================================
// Module: msg_text_export
// Project: DE10-Standard LCD Message System
// Description: Snapshot stage between msg_text_rom and the wide bridge PIOs.
//
//   The current message text (512-bit, from msg_text_rom, combinational on the
//   FSM message index) and the index itself are registered TOGETHER on the same
//   clock edge, so the exported text and the exported index can never disagree.
//
//   A 3-bit sequence counter increments on every index change. The HPS uses it
//   as a seqlock: read status -> read the 16 text words -> re-read status; if
//   the sequence changed, an update landed mid-read and the HPS retries. This
//   makes a torn read (half of one message, half of the next) detectable.
//
//   status_out = { seq[2:0], text_index[4:0] }  (the index the exported text
//   actually belongs to -- this, not fsm_status_pio, is the authority for what
//   is on screen).
// ============================================================================

module msg_text_export #(
    parameter integer INDEX_W = 5
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire [INDEX_W-1:0]   msg_index,   // current FSM index (comb)
    input  wire [511:0]         text_in,     // msg_text_rom[msg_index] (comb)

    output reg  [511:0]         text_out,    // registered snapshot
    output reg  [INDEX_W-1:0]   text_index,  // index the snapshot belongs to
    output reg  [2:0]           seq,         // increments on each index change
    output wire [7:0]           status_out   // {seq[2:0], text_index[4:0]}
);

    assign status_out = {seq, text_index};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            text_out   <= 512'b0;
            text_index <= {INDEX_W{1'b0}};
            seq        <= 3'd0;
        end else begin
            // text_out and text_index advance as one pipeline stage, so they
            // are always mutually consistent.
            text_out   <= text_in;
            text_index <= msg_index;
            // seq bumps whenever the incoming index differs from the one we
            // are currently presenting (i.e. a real navigation event).
            if (msg_index != text_index)
                seq <= seq + 1'b1;
        end
    end

endmodule
