# DE10-Standard LCD Message System

Real-time LCD message board for a physiotherapy room, built on the Terasic DE10-Standard (Cyclone V FPGA + ARM HPS). Also a case study in simulation-gated AI development: **AI tools draft every module, but nothing reaches hardware until it passes a simulation gate.** Result: all requirements met at first power-on, zero hardware bugs.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Board](https://img.shields.io/badge/Board-Terasic%20DE10--Standard-0068B5)](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&No=1046)
[![SoC](https://img.shields.io/badge/SoC-Intel%20Cyclone%20V-0068B5)](https://www.intel.com/content/www/us/en/products/details/fpga/cyclone/v.html)
[![RTL](https://img.shields.io/badge/RTL-Verilog-E67E22)]()
[![HW bugs at power-on](https://img.shields.io/badge/HW%20bugs%20at%20power--on-0-1A7A4A)]()

<p align="center">
  <img src="assets/images/00_ai_workflow_hero.jpg" alt="Prompt input through an AI workspace and verification gate to the final implementation: buttons and a text data file into the FPGA, over the F2H bridge to the microprocessor, out to the 7-segment display and LCD" width="880">
</p>

## At a Glance

**18** messages · **4** buttons · **42 ms** worst-case latency (< 50 ms target) · **7%** FPGA logic used · **0** / 10,000 bridge errors

Buttons wire only to the FPGA, and the LCD wires only to the HPS. That physical fact set the architecture.

## Architecture

<p align="center">
  <img src="assets/images/01_soc_bridge_transaction.png" alt="Intel Cyclone V SoC block diagram: FPGA fabric and HPS communicating over the Lightweight HPS-to-FPGA Bridge" width="620">
  <img src="assets/images/06_fpga_datapath_block_diagram.png" alt="FPGA datapath: debounce, edge detect, Message FSM, Countdown Timer, Msg Duration ROM, HEX display" width="820">
</p>

The FPGA owns the real-time path (debounce → edge detect → FSM → timer) and exposes read-only status registers. The HPS polls them over the Lightweight Bridge (`0xFF200000`) and renders the LCD; it never writes back.

| Module | Role |
|---|---|
| `button_debouncer.v` | 20 ms stability counter (1,000,000 cycles @ 50 MHz) |
| `button_edge_detector.v` | one pulse per press |
| `message_fsm.v` | 5-state Moore FSM |
| `idle_timer.v` | runtime-loadable countdown |
| `msg_duration_rom.v` | per-message duration lookup (0–17) |
| `hex_display.v` | seconds / last button / message number to 7-segment |

## Register Map & FSM

<p align="center">
  <img src="assets/images/03_register_bitfield_layout.png" alt="Bit-field layout of fsm_status_pio and timer_status_pio registers" width="480">
  <img src="assets/images/02_fsm_state_diagram.png" alt="5-state Moore FSM: INIT, IDLE, HOME, MSG, SLEEP" width="620">
</p>

| PIO | Offset | Fields |
|---|---|---|
| `fsm_status_pio` | `0x6000` | [7:5] state · [4:0] message index |
| `timer_status_pio` | `0x7000` | [0] timeout · [6:1] seconds remaining |

INIT → IDLE → HOME → MSG, with HOME/IDLE timing out to SLEEP and MSG auto-advancing (wrap). **On a tie, the button always beats the timer.**

## HPS Software

<p align="center">
  <img src="assets/images/07_hps_software_polling_flow.png" alt="HPS software flowchart: 5ms polling loop, redraw only on state/index change" width="520">
</p>

`main.c` polls the registers every 5 ms and redraws only on change. No message text crosses the bridge: all 18 strings live in `messages.h`, and the FPGA sends only a 5-bit index.

## Simulation-Gated AI Development

<p align="center">
  <img src="assets/images/04_ai_assisted_workflow.png" alt="AI-assisted development workflow: architecture partitioning, then a loop of AI code generation and simulation/verification, then hardware integration" width="620">
  <img src="assets/images/05_verification_funnel.png" alt="Six-gate verification funnel from board wiring review to hardware bring-up" width="560">
</p>

Verilog was drafted with Claude Code, and the HPS C application with Codex. No code reaches the board until its testbench passes: a failing test revises the prompt, and a hardware bug loops back to generation. Six defects were caught this way, all traced to under-specified prompts rather than model limits:

| Defect | Caught by |
|---|---|
| LCD assumed wired to FPGA | Board wiring review |
| Register layout mismatch | Wrong text on LCD |
| Bit-width mismatch | Verilator lint |
| Failed timing closure | Quartus timing report |
| Stale LCD text | Manual screen check |
| Missed press at timeout edge | Edge-case test |

> **Weak:** *"...using a Nios II soft-core processor to drive the display."* No wiring facts were given, so the model defaulted to a generic pattern.
> **Strong:** *"The KEY[0–3] buttons are wired only to FPGA fabric pins, the LCD only to the Processor."* Wiring is stated as fact, leaving no room for assumption.

## The Real Hardware

<p align="center">
  <img src="assets/images/09_hardware_annotated_photo.jpg" alt="Annotated DE10-Standard: yellow = LCD, orange = HEX display, magenta = KEY buttons, red = Cyclone V SoC, blue = GPIO header" width="560">
</p>

## Results

<p align="center">
  <img src="assets/images/13_latency_frames_photo.jpg" alt="240fps camera frames from button press to full LCD text, frame 10 at 42ms" width="560">
  <img src="assets/images/11_scope_1hz_clock.png" alt="Oscilloscope trace confirming the 1Hz clock divider output" width="290">
  <img src="assets/images/12_scope_762hz_7seg.png" alt="Oscilloscope trace confirming the 762.9Hz 7-segment refresh rate" width="290">
</p>

| Metric | Result | Target |
|---|---|---|
| Display latency | 42 ms (camera, 240fps) | < 50 ms |
| FPGA logic | 7% (3,073 / 41,910 ALMs) | < 75% |
| Bridge reliability | 0 errors / 10,000 reads | 0 |
| Button debounce | 0 false triggers | 0 |

Eight testbenches (`tb_button_debouncer`, `tb_button_edge_detector`, `tb_message_fsm`, `tb_idle_timer`, `tb_hex_display`, `tb_soc_register_contract`, `tb_fpga_msg_controller`, `tb_clock_divider`) required zero errors before any module reached hardware.

## Repository Structure

```
├── hw/rtl/           Verilog RTL modules
├── hw/quartus/       Quartus project + pin assignments
├── sw/hps_app/       HPS C application + Makefile
├── sim/testbenches/  8 Verilog simulation testbenches
├── scripts/          Build, deployment, hardware sign-off automation
├── assets/           Diagram sources (TikZ) + rendered images/photos
└── README.md
```

## Build

**FPGA (Windows):**
```
.\hw\quartus\fix_then_build.ps1    # fixes Qsys, compiles DE10_Standard_GHRD.sof
```
Program with Quartus Programmer.

**HPS software (on-board):**
```
cd sw/hps_app && make && ./lcd_msg_app
```

**HPS software (Windows, via WSL cross-compile):**
```
wsl -d Ubuntu -- bash -lc "cd /mnt/c/Fpga_project_DE10_Standard_LCD_MSGS_-V2/sw/hps_app && make CC=arm-linux-gnueabihf-gcc"
```

**Simulate before flashing:**
```
.\sim\run_all_sim.ps1                    # canonical regression
.\sim\run_pre_board_verification.ps1     # full pre-board gate
```

## Future Work

VGA display · Wi-Fi message streaming · audio feedback · touchscreen input · SD-card message library · power management (~30–40% cut) · exhaustive bridge-integrity test · scope-based hardware coverage.

## Credits

Built by **Amit Damari** and **Ido Zylberman**, advised by **Eytan Mann**, Digital Systems Laboratory, Tel Aviv University. Project 3420, EE Final Year, 2025–26.

Released under the [MIT License](LICENSE).
