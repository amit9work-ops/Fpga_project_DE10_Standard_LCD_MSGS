# DE10-Standard LCD Message System V2 - Requirements

## Scope
This document defines simulation-first requirements that must pass before FPGA board testing.

## Functional Requirements

R1. Buttons shall be debounced in FPGA fabric.
- Input polarity: KEY signals are active-LOW.
- Output polarity: debounced outputs are active-HIGH.
- Default debounce window: 20 ms at 50 MHz (1,000,000 cycles).

R2. A button press shall generate exactly one pulse event per rising edge of debounced state.
- Holding a button shall not generate repeated pulses.

R3. Idle timer shall count down from TIMEOUT_SEC to zero.
- Default timeout: 15 seconds.
- Timer shall assert timeout when countdown reaches zero.
- Any button pulse shall reset timer and clear timeout.

R4. HEX display outputs shall encode values in active-LOW 7-segment format.
- HEX0: seconds remaining.
- HEX1: last button pressed (F means none after reset).
- HEX2: timeout status (0 running, 1 expired).
- HEX3-HEX5: fixed zero.

R5. Standalone top-level wiring shall be consistent.
- LEDR[3:0] mirrors debounced button levels.
- LEDR[4] mirrors timeout flag.
- LEDR[9:5] fixed off.

R6. HPS-visible register packing in SoC integration shall be stable.
- FSM status export: bits[7:5] shall expose FSM state and bits[4:0] shall expose FSM message index.
- Timer status export: bit0 timeout flag, bits[4:1] seconds remaining.

R7. Core UI control FSM shall be implemented in Verilog.
- Required states: INIT, IDLE, HOME, MSG, SLEEP.
- Required transitions: button-driven navigation and timeout-driven sleep path.
- Message index navigation in MSG state shall support wrap-around for next/previous actions.

## Verification Requirements

V1. Unit-level simulations must pass:
- button_debouncer
- button_edge_detector
- idle_timer
- hex_display

V2. Integration simulations must pass:
- fpga_msg_controller
- top_level

V2b. FSM simulations must pass:
- message_fsm with deep transition coverage (state entry, timeout priority, wrap-around).

V3. Clock utility simulation must pass:
- clock_divider with strict pulse-width and long-run tick-count checks.

V4. Regression requirement:
- One command shall run all required suites and return a clear pass/fail summary.

## Acceptance Criteria

A1. No testbench shall report FAIL, assertion failure, or timeout.

A2. Pulse width checks must confirm all event ticks/pulses are single-cycle where specified.

A3. All HEX checks must compare exact segment patterns, not only non-blank checks.

A4. Requirements-to-tests traceability shall be documented in verification_report.md.

## Performance Notes (Pre-Board)

- HPS polling interval target: 5 ms.
- Expected end-to-end button-to-LCD latency: approximately 35 ms.
- Current FPGA resource usage target: 7% ALMs.
