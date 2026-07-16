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
#   hw/rtl/msg_nav_rom.v               generated nav  ROM  ((index,action)->index),
#                                      5 actions (KEY0/1/2/3, TIMEOUT), category-based
#   hw/sim/testbenches/msg_text_golden.vh    fills golden_text[0:1151] (byte B=line*16+col)
#   hw/sim/testbenches/msg_nav_golden.vh     fills golden_nav[0:89]    (idx*5+action)
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
# Navigation model - round 2 (category-based, per advisor Eytan Mann's design):
# each of the 4 keys jumps to a FIXED category head regardless of current
# position; TIMEOUT advances sequentially within the current category; a
# non-emergency category's last entry times out back to Default; Emergency's
# entry times out to itself (sticky - only a key press escapes it).
#
# Category order below is (name, key_action, members). `members` lists the
# display sequence for that category; members[0] is the head (KEY jump
# target). Every one of the 18 messages must appear in exactly one category.
# ---------------------------------------------------------------------------
CATEGORIES = [
    ("DEFAULT",  3, [0, 1, 2, 17]),                   # KEY3: welcome/credits, ending on "System Ready"
    ("EXERCISE", 0, [3, 4, 5, 6, 7]),                  # KEY0: 4 exercises + rest
    ("SESSION",  1, [8, 9, 10, 11, 12, 13, 14, 15]),   # KEY1: waiting/help/paused/active/done
    ("EMERGENCY",2, [16]),                             # KEY2: attention/staff-called (sticky)
]

# Action encoding must match message_fsm.v / msg_nav_rom.v.
ACT_KEY0    = 0   # jump to EXERCISE head
ACT_KEY1    = 1   # jump to SESSION head
ACT_KEY2    = 2   # jump to EMERGENCY head
ACT_KEY3    = 3   # jump to DEFAULT head (also the Emergency escape)
ACT_TIMEOUT = 4   # sequential advance within the current category

DEFAULT_INDEX = 0  # DEFAULT category head; non-emergency category-end timeout target

# name -> key action, for building the fixed jump table below.
_CATEGORY_ACTION = {name: key_act for name, key_act, _ in CATEGORIES}
_KEY_ACTIONS = (ACT_KEY0, ACT_KEY1, ACT_KEY2, ACT_KEY3)


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
    index_to_cat = {}          # idx -> (category_name, members list)
    cat_head = {}               # category_name -> head index
    for name, _key_act, members in CATEGORIES:
        cat_head[name] = members[0]
        for idx in members:
            index_to_cat[idx] = (name, members)

    nav = {}  # (index, action) -> next
    for idx in range(MSG_COUNT):
        cat_name, members = index_to_cat[idx]
        pos = members.index(idx)
        is_last = (pos == len(members) - 1)

        # The 4 key actions are FIXED jumps: identical target for every idx.
        for name, key_act, members2 in CATEGORIES:
            nav[(idx, key_act)] = members2[0]

        # TIMEOUT: sequential within the category; at the last entry,
        # Emergency sticks to itself, every other category falls back to
        # DEFAULT's head.
        if not is_last:
            nav[(idx, ACT_TIMEOUT)] = members[pos + 1]
        elif cat_name == "EMERGENCY":
            nav[(idx, ACT_TIMEOUT)] = idx  # sticky, no auto exit
        else:
            nav[(idx, ACT_TIMEOUT)] = DEFAULT_INDEX

    return nav, index_to_cat


# ---------------------------------------------------------------------------
# Self-checks  (L1 gate: fail loudly before any RTL is trusted)
# ---------------------------------------------------------------------------
def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def self_check(msgs, nav, index_to_cat):
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

    # Every message assigned to exactly one category, all 18 covered.
    all_members = []
    for name, _key_act, members in CATEGORIES:
        all_members.extend(members)
    if sorted(all_members) != list(range(MSG_COUNT)):
        die(f"category membership does not partition 0..{MSG_COUNT-1} exactly: {sorted(all_members)}")

    # Exactly one DEFAULT and one EMERGENCY category (both are referenced by
    # name elsewhere: DEFAULT for in_default/sleep-arming and the category-end
    # fallback target, EMERGENCY for the sticky-timeout special case).
    for required in ("DEFAULT", "EMERGENCY"):
        n = sum(1 for name, _k, _m in CATEGORIES if name == required)
        if n != 1:
            die(f"expected exactly one {required} category, found {n}")
    # Every key action (0-3) must be used by exactly one category.
    key_acts = [key_act for _n, key_act, _m in CATEGORIES]
    if sorted(key_acts) != [0, 1, 2, 3]:
        die(f"category key actions must be exactly {{0,1,2,3}}, got {sorted(key_acts)}")

    for (idx, act), nxt in nav.items():
        if not (0 <= nxt < MSG_COUNT):
            die(f"nav({idx},{act}) -> {nxt} out of range")

    # Fixed jump target: for each of the 4 key actions, next_index must be
    # identical across every cur_index (this is the "jump to category head
    # regardless of where you are" property the round-2 model depends on).
    for name, key_act, members in CATEGORIES:
        targets = {nav[(idx, key_act)] for idx in range(MSG_COUNT)}
        if targets != {members[0]}:
            die(f"key action {key_act} ({name}) is not a fixed jump to {members[0]}: got {targets}")

    # Emergency's entry times out to itself (sticky).
    for name, _key_act, members in CATEGORIES:
        if name != "EMERGENCY":
            continue
        for idx in members:
            if idx == members[-1] and nav[(idx, ACT_TIMEOUT)] != idx:
                die(f"Emergency entry {idx} does not stick to itself on timeout")

    # Every other category's last entry times out to DEFAULT_INDEX.
    for name, _key_act, members in CATEGORIES:
        if name == "EMERGENCY":
            continue
        last = members[-1]
        if nav[(last, ACT_TIMEOUT)] != DEFAULT_INDEX:
            die(f"category {name}'s last entry {last} does not time out to Default ({DEFAULT_INDEX})")

    # Every message reachable from Default's head by some key sequence (BFS) -
    # trivially true here since every category head is one keypress away, but
    # kept as a regression guard against a future hand-edit breaking it.
    reach = {DEFAULT_INDEX}
    frontier = [DEFAULT_INDEX]
    while frontier:
        cur = frontier.pop()
        for act in _KEY_ACTIONS + (ACT_TIMEOUT,):
            nxt = nav[(cur, act)]
            if nxt not in reach:
                reach.add(nxt)
                frontier.append(nxt)
    missing = set(range(MSG_COUNT)) - reach
    if missing:
        die(f"messages unreachable from Default ({DEFAULT_INDEX}): {sorted(missing)}")

    print("L1 self-checks passed: %d messages, %d categories, %d nav entries." %
          (MSG_COUNT, len(CATEGORIES), len(nav)))


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


NUM_ACTIONS = 5  # KEY0, KEY1, KEY2, KEY3, TIMEOUT -> 3-bit action field


def emit_nav_rom(nav, index_to_cat):
    default_members = next(members for name, _k, members in CATEGORIES if name == "DEFAULT")
    lines = [GEN_BANNER]
    lines.append("// action: 0=KEY0(->EXERCISE) 1=KEY1(->SESSION) 2=KEY2(->EMERGENCY)")
    lines.append("//         3=KEY3(->DEFAULT, also the Emergency escape) 4=TIMEOUT(sequential)")
    lines.append("// KEY0-3 are FIXED jumps: next_index is the same for every cur_index.")
    lines.append("// TIMEOUT advances within the current category; Emergency's entry")
    lines.append("// sticks to itself; every other category's last entry falls to Default (0).")
    lines.append("// in_default: combinational, true while cur_index is a DEFAULT-category")
    lines.append("// message. The system-idle/sleep timer is armed only while this is set,")
    lines.append("// so an active Cat/Emergency slideshow can never be interrupted by sleep.")
    lines.append("module msg_nav_rom (")
    lines.append("    input  wire [4:0] cur_index,")
    lines.append("    input  wire [2:0] action,")
    lines.append("    output reg  [4:0] next_index,")
    lines.append("    output reg        in_default")
    lines.append(");")
    lines.append("    always @(*) begin")
    lines.append("        case ({cur_index, action})")
    for idx in range(MSG_COUNT):
        for act in range(NUM_ACTIONS):
            key = (idx << 3) | act
            nxt = nav[(idx, act)]
            lines.append(f"            8'd{key}: next_index = 5'd{nxt};")
    lines.append("            default: next_index = 5'd0;")
    lines.append("        endcase")
    lines.append("    end")
    lines.append("")
    lines.append("    always @(*) begin")
    lines.append("        case (cur_index)")
    for idx in range(MSG_COUNT):
        val = "1'b1" if idx in default_members else "1'b0"
        lines.append(f"            5'd{idx}: in_default = {val};")
    lines.append("            default: in_default = 1'b0;")
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
    # Fills golden_nav[0:89], entry idx*NUM_ACTIONS+action.
    out = ["// GENERATED by tools/gen_msg_tables.py - DO NOT EDIT.",
           "// `include inside an initial block; fills reg [4:0] golden_nav[0:%d]." %
           (MSG_COUNT * NUM_ACTIONS - 1)]
    for idx in range(MSG_COUNT):
        for act in range(NUM_ACTIONS):
            out.append("golden_nav[%d] = 5'd%d;" % (idx * NUM_ACTIONS + act, nav[(idx, act)]))
    write(os.path.join(TB_DIR, "msg_nav_golden.vh"), "\n".join(out) + "\n")


def emit_dump(msgs, nav, index_to_cat, source):
    lines = []
    lines.append("LCD message reference dump (generated from %s)" % source)
    lines.append("Byte order per message: line*16+col, lines 0..3.")
    lines.append("Categories: " + ", ".join(
        "%s (KEY%d -> head %d)" % (name, key_act, members[0]) if key_act < 4
        else "%s" % name
        for name, key_act, members in CATEGORIES
    ))
    lines.append("")
    act_name = {0: "KEY0", 1: "KEY1", 2: "KEY2", 3: "KEY3", 4: "TMO "}
    for i, m in enumerate(msgs):
        catname = index_to_cat[i][0]
        lines.append("MSG %2d  [%s]" % (i, catname))
        for l in range(LINES):
            lines.append("   |%s|" % m[l])
        nav_str = "  ".join(
            "%s->%d" % (act_name[a], nav[(i, a)]) for a in range(NUM_ACTIONS)
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
    self_check(msgs, nav, index_to_cat)
    print("Emitting artifacts (source: %s):" % source)
    emit_text_rom(msgs)
    emit_nav_rom(nav, index_to_cat)
    emit_text_golden(msgs)
    emit_nav_golden(nav)
    emit_dump(msgs, nav, index_to_cat, source)
    print("Done.")


if __name__ == "__main__":
    main()
