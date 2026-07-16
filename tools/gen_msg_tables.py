#!/usr/bin/env python3
# ============================================================================
# gen_msg_tables.py  -  Single source of truth for the LCD message system.
#
# Reads the 18 x 4 x 16-char message table (from sw/hps_app/messages.h while it
# still exists, otherwise from the committed snapshot tools/msg_text.json) and
# the navigation rules defined below, then emits EVERY downstream artifact so
# the ROM contents, the simulation golden vectors, and the on-board reference
# dump can never drift from one another:
#
#   hw/rtl/msg_text_rom.v              generated text ROM  (index -> 512-bit)
#   hw/rtl/msg_nav_rom.v               generated nav  ROM  ((index,action)->index)
#   hw/sim/testbenches/msg_text_golden.vh    fills golden_text[0:1151] (byte B=line*16+col)
#   hw/sim/testbenches/msg_nav_golden.vh     fills golden_nav[0:71]    (idx*4+action)
#   tools/msg_text.json                snapshot of the text (so this script keeps
#                                      working after messages.h is deleted)
#   tools/msg_golden_dump.txt          human-readable reference for the board diff
#
# The golden vectors are emitted as Verilog `include snippets (not .hex) so they
# resolve at compile time relative to the including testbench, independent of the
# simulator's working directory. Each is a list of blocking assignments meant to
# be `include-d inside an initial block.
#
# Byte / bit ordering contract (mirrored by the HPS decode in main.c):
#   msg byte index  B = line*16 + col      (line 0..3, col 0..15)
#   text_out[511:0] holds byte B at bits [B*8 +: 8]
#   wide PIO word w = text_out[32*w +: 32]  = bytes {4w+3,4w+2,4w+1,4w}
#   => HPS: char[B] = (word[B/4] >> (8*(B%4))) & 0xFF
# ============================================================================

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MESSAGES_H = os.path.join(ROOT, "sw", "hps_app", "messages.h")
SNAPSHOT   = os.path.join(ROOT, "tools", "msg_text.json")

RTL_DIR    = os.path.join(ROOT, "hw", "rtl")
TB_DIR     = os.path.join(ROOT, "hw", "sim", "testbenches")
TOOLS_DIR  = os.path.join(ROOT, "tools")

MSG_COUNT = 18
LINES     = 4
COLS      = 16

# ---------------------------------------------------------------------------
# Navigation model  (see design note; adjust here, regenerate, everything follows)
# ---------------------------------------------------------------------------
# Categories in display order; first element of each is the "category head".
CATEGORIES = [
    ("INTRO",     [0, 1, 2]),
    ("EXERCISE",  [3, 4, 5, 6]),
    ("REST",      [7]),
    ("WAITING",   [8, 9]),
    ("SAFETY",    [10, 11]),
    ("STATUS",    [12, 13]),
    ("DONE",      [14, 15]),
    ("EMERGENCY", [16]),
    ("READY",     [17]),
]

# Action encoding must match message_fsm.v / msg_nav_rom.v.
ACT_KEY1    = 0   # next within category
ACT_KEY2    = 1   # jump to head of next category
ACT_KEY3    = 2   # jump to emergency
ACT_TIMEOUT = 3   # scripted session flow

EMERGENCY_INDEX = 16

# Scripted idle flow (TIMEOUT). On-script messages auto-advance along this
# cycle; messages NOT listed here are "sticky" (timeout -> self, i.e. they stay
# until an operator presses a key). Safety/paused/emergency are intentionally
# sticky and off the idle path so the display never auto-shows an alert.
TIMEOUT_SCRIPT = [17, 0, 1, 2, 13, 3, 4, 5, 6, 7, 14, 15, 8, 9]  # cycles back to 17


# ---------------------------------------------------------------------------
# Load the message text
# ---------------------------------------------------------------------------
def parse_messages_h(path):
    with open(path, "r", encoding="ascii") as f:
        src = f.read()
    # Only look inside the array initializer to avoid catching header comments.
    start = src.index("MSG_LIST")
    body = src[start:]
    literals = re.findall(r'"((?:[^"\\]|\\.)*)"', body)
    if len(literals) != MSG_COUNT * LINES:
        die(f"messages.h: expected {MSG_COUNT*LINES} string literals, found {len(literals)}")
    msgs = []
    for m in range(MSG_COUNT):
        msgs.append([literals[m * LINES + l] for l in range(LINES)])
    return msgs


def load_text():
    if os.path.exists(MESSAGES_H):
        msgs = parse_messages_h(MESSAGES_H)
        # Refresh the snapshot from the authoritative header while it exists.
        with open(SNAPSHOT, "w", encoding="ascii") as f:
            json.dump(msgs, f, indent=2)
        source = "sw/hps_app/messages.h"
    elif os.path.exists(SNAPSHOT):
        with open(SNAPSHOT, "r", encoding="ascii") as f:
            msgs = json.load(f)
        source = "tools/msg_text.json"
    else:
        die("no message source: neither messages.h nor the snapshot exists")
    return msgs, source


# ---------------------------------------------------------------------------
# Build the navigation table
# ---------------------------------------------------------------------------
def build_nav():
    index_to_cat = {}
    cat_heads = []
    for ci, (_, members) in enumerate(CATEGORIES):
        cat_heads.append(members[0])
        for idx in members:
            index_to_cat[idx] = (ci, members)

    # timeout: on-script -> next in cycle; off-script -> self (sticky)
    timeout_next = {i: i for i in range(MSG_COUNT)}
    n = len(TIMEOUT_SCRIPT)
    for k, idx in enumerate(TIMEOUT_SCRIPT):
        timeout_next[idx] = TIMEOUT_SCRIPT[(k + 1) % n]

    nav = {}  # (index, action) -> next
    for idx in range(MSG_COUNT):
        ci, members = index_to_cat[idx]
        pos = members.index(idx)
        # KEY1: next within category (wrap inside category)
        nav[(idx, ACT_KEY1)] = members[(pos + 1) % len(members)]
        # KEY2: head of next category (wrap across categories)
        nav[(idx, ACT_KEY2)] = cat_heads[(ci + 1) % len(CATEGORIES)]
        # KEY3: straight to emergency
        nav[(idx, ACT_KEY3)] = EMERGENCY_INDEX
        # TIMEOUT: scripted flow / sticky
        nav[(idx, ACT_TIMEOUT)] = timeout_next[idx]
    return nav, index_to_cat


# ---------------------------------------------------------------------------
# Self-checks  (L1 gate: fail loudly before any RTL is trusted)
# ---------------------------------------------------------------------------
def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def self_check(msgs, nav):
    if len(msgs) != MSG_COUNT:
        die(f"expected {MSG_COUNT} messages, got {len(msgs)}")
    for i, m in enumerate(msgs):
        if len(m) != LINES:
            die(f"message {i}: expected {LINES} lines, got {len(m)}")
        for l, line in enumerate(m):
            if len(line) != COLS:
                die(f"message {i} line {l}: length {len(line)} != {COLS}: {line!r}")
            for ch in line:
                if not (0x20 <= ord(ch) <= 0x7E):
                    die(f"message {i} line {l}: non-printable char {ch!r}")
    for (idx, act), nxt in nav.items():
        if not (0 <= nxt < MSG_COUNT):
            die(f"nav({idx},{act}) -> {nxt} out of range")
    # KEY3 from anywhere reaches emergency
    for idx in range(MSG_COUNT):
        if nav[(idx, ACT_KEY3)] != EMERGENCY_INDEX:
            die(f"KEY3 from {idx} does not reach emergency")
    # timeout on-script forms a closed cycle covering the script
    seen = set()
    cur = TIMEOUT_SCRIPT[0]
    for _ in range(len(TIMEOUT_SCRIPT)):
        seen.add(cur)
        cur = nav[(cur, ACT_TIMEOUT)]
    if cur != TIMEOUT_SCRIPT[0] or seen != set(TIMEOUT_SCRIPT):
        die("timeout script is not a closed cycle over its members")
    # every message reachable from 17 by some key sequence (BFS)
    reach = {17}
    frontier = [17]
    while frontier:
        cur = frontier.pop()
        for act in (ACT_KEY1, ACT_KEY2, ACT_KEY3, ACT_TIMEOUT):
            nxt = nav[(cur, act)]
            if nxt not in reach:
                reach.add(nxt)
                frontier.append(nxt)
    missing = set(range(MSG_COUNT)) - reach
    if missing:
        die(f"messages unreachable from 17: {sorted(missing)}")
    print("L1 self-checks passed: %d messages, %d nav entries." % (MSG_COUNT, len(nav)))


# ---------------------------------------------------------------------------
# Emit
# ---------------------------------------------------------------------------
GEN_BANNER = (
    "// ============================================================\n"
    "// GENERATED by tools/gen_msg_tables.py - DO NOT EDIT BY HAND.\n"
    "// Edit the message table / nav rules and regenerate.\n"
    "// ============================================================\n"
)


def msg_to_512(msg):
    """Return the 512-bit integer: byte B=line*16+col at bits [B*8 +: 8]."""
    val = 0
    for l in range(LINES):
        for c in range(COLS):
            b = l * COLS + c
            val |= ord(msg[l][c]) << (b * 8)
    return val


def emit_text_rom(msgs):
    lines = [GEN_BANNER]
    lines.append("module msg_text_rom (")
    lines.append("    input  wire [4:0]   msg_index,")
    lines.append("    output reg  [511:0] text_out   // byte B=line*16+col at [B*8 +: 8]")
    lines.append(");")
    lines.append("    always @(*) begin")
    lines.append("        case (msg_index)")
    for i, m in enumerate(msgs):
        v = msg_to_512(m)
        joined = "".join(m).replace("\\", "\\\\")
        lines.append(f"            5'd{i}: text_out = 512'h{v:0128X}; // {joined!r}")
    # safe default: 'INDEX ERROR' left-justified on line 0, spaces elsewhere
    err = ["INDEX ERROR     ", " " * 16, " " * 16, " " * 16]
    lines.append(f"            default: text_out = 512'h{msg_to_512(err):0128X}; // out-of-range guard")
    lines.append("        endcase")
    lines.append("    end")
    lines.append("endmodule")
    write(os.path.join(RTL_DIR, "msg_text_rom.v"), "\n".join(lines) + "\n")


def emit_nav_rom(nav):
    lines = [GEN_BANNER]
    lines.append("// action: 0=KEY1(next in cat) 1=KEY2(next cat) 2=KEY3(emergency) 3=TIMEOUT(script)")
    lines.append("module msg_nav_rom (")
    lines.append("    input  wire [4:0] cur_index,")
    lines.append("    input  wire [1:0] action,")
    lines.append("    output reg  [4:0] next_index")
    lines.append(");")
    lines.append("    always @(*) begin")
    lines.append("        case ({cur_index, action})")
    for idx in range(MSG_COUNT):
        for act in range(4):
            key = (idx << 2) | act
            nxt = nav[(idx, act)]
            lines.append(f"            7'd{key}: next_index = 5'd{nxt};")
    lines.append("            default: next_index = 5'd0;")
    lines.append("        endcase")
    lines.append("    end")
    lines.append("endmodule")
    write(os.path.join(RTL_DIR, "msg_nav_rom.v"), "\n".join(lines) + "\n")


def emit_text_golden(msgs):
    # Fills golden_text[0:1151], msg-major, byte order B=line*16+col.
    # Include this inside an initial block in the testbench.
    out = ["// GENERATED by tools/gen_msg_tables.py - DO NOT EDIT.",
           "// `include inside an initial block; fills reg [7:0] golden_text[0:1151]."]
    for m_i, m in enumerate(msgs):
        for l in range(LINES):
            for c in range(COLS):
                b = m_i * (LINES * COLS) + l * COLS + c
                out.append("golden_text[%d] = 8'h%02X;" % (b, ord(m[l][c])))
    write(os.path.join(TB_DIR, "msg_text_golden.vh"), "\n".join(out) + "\n")


def emit_nav_golden(nav):
    # Fills golden_nav[0:71], entry idx*4+action.
    out = ["// GENERATED by tools/gen_msg_tables.py - DO NOT EDIT.",
           "// `include inside an initial block; fills reg [4:0] golden_nav[0:71]."]
    for idx in range(MSG_COUNT):
        for act in range(4):
            out.append("golden_nav[%d] = 5'd%d;" % (idx * 4 + act, nav[(idx, act)]))
    write(os.path.join(TB_DIR, "msg_nav_golden.vh"), "\n".join(out) + "\n")


def emit_dump(msgs, nav, index_to_cat, source):
    lines = []
    lines.append("LCD message reference dump (generated from %s)" % source)
    lines.append("Byte order per message: line*16+col, lines 0..3.")
    lines.append("")
    act_name = {0: "KEY1", 1: "KEY2", 2: "KEY3", 3: "TMO "}
    for i, m in enumerate(msgs):
        cat = index_to_cat[i][0]
        catname = CATEGORIES[cat][0]
        lines.append("MSG %2d  [%s]" % (i, catname))
        for l in range(LINES):
            lines.append("   |%s|" % m[l])
        nav_str = "  ".join(
            "%s->%d" % (act_name[a], nav[(i, a)]) for a in range(4)
        )
        lines.append("   nav: %s" % nav_str)
        lines.append("")
    write(os.path.join(TOOLS_DIR, "msg_golden_dump.txt"), "\n".join(lines) + "\n")


def write(path, content):
    with open(path, "w", encoding="ascii", newline="\n") as f:
        f.write(content)
    print("  wrote", os.path.relpath(path, ROOT).replace("\\", "/"))


def main():
    msgs, source = load_text()
    nav, index_to_cat = build_nav()
    self_check(msgs, nav)
    print("Emitting artifacts (source: %s):" % source)
    emit_text_rom(msgs)
    emit_nav_rom(nav)
    emit_text_golden(msgs)
    emit_nav_golden(nav)
    emit_dump(msgs, nav, index_to_cat, source)
    print("Done.")


if __name__ == "__main__":
    main()
