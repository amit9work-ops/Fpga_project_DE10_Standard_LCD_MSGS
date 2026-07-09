# DE10-Standard LCD Message System

Real-time message display system for the Terasic DE10-Standard board (Cyclone V FPGA + ARM HPS), built for a physiotherapy/rehabilitation treatment room. It migrates critical system control logic (button debouncing, edge detection, idle timing, and per-message display duration) from the HPS software to the FPGA fabric for improved responsiveness and robustness.

This project is also a case study in **simulation-gated AI-assisted embedded development**: AI tools drafted each Verilog module and the HPS C application, but no draft was accepted until it passed a dedicated testbench. See [Development Methodology](#development-methodology) for the workflow and the defects it caught.

## Recent Highlights

*   **Per-message auto-advance slideshow**: each message now displays for its own configurable duration (`msg_duration_rom.v`) before automatically advancing to the next — a real hardware-timed slideshow, not just a static screen. Manual KEY1/KEY2/KEY0 navigation always takes priority.
*   **60-second Home inactivity timeout** (previously 15s): only the Home screen sleeps on inactivity now; the message slideshow keeps cycling on its own instead of sleeping.
*   **On-board demo indicators**: HEX0/HEX1 now show the active message number, and LEDR[9] blinks on every countdown expiry — both tie the physical board directly to what's happening on the LCD.

## Development Methodology

AI tools were used to generate first-draft Verilog modules and the HPS C application. A draft was accepted only after it passed its required simulation checks; AI output was never treated as proof of correctness on its own.

Workflow: (1) architecture partitioning decided first — board wiring fixed the FPGA/HPS split (buttons on FPGA pins, LCD on the HPS SPI/LTC interface); (2) AI drafts each module against an explicit spec (register layout, timing, priority rules); (3) the draft is simulated against a dedicated testbench; (4) only after all suites pass does the module reach hardware. A failing suite loops back to a revised, more constrained prompt — not a different model.

### Defects found in AI-generated code, and how each was caught

| # | Defect | Caught by | Fix |
|---|---|---|---|
| 1 | LCD assumed connected directly to FPGA GPIO | Board wiring check | Switched to the FPGA/HPS split architecture (buttons on FPGA, LCD on HPS) |
| 2 | Register bit-field layout mismatch between FPGA and HPS | Wrong text rendered on LCD | Corrected the shared register contract (see Register Map below) |
| 3 | Bit-width mismatch between modules | Lint tool | Fixed signal widths |
| 4 | Failed timing closure after synthesis | Quartus timing report | Rewrote the critical logic path |
| 5 | Stale text left on LCD after a state change | Manual screen check | Fixed redraw ordering in the HPS render loop |
| 6 | Missed button press arriving on the same cycle as a timer expiry | Dedicated edge-case test | Fixed timer/priority comparison so button events always win |

Every defect traced back to an under-specified prompt — a missing constraint on board wiring, register layout, or priority rules — not a model capability limit. The fix was always a more complete, constraint-aware prompt rather than a different model. Full before/after prompt examples are documented in the project's final report.

## Finite State Machine

The UI is controlled by a 5-state Moore FSM (outputs depend only on the current state, so an HPS read at any time returns a stable, well-defined value without needing to observe the transition inputs).

| State | Meaning |
|---|---|
| INIT | Power-on / reset |
| IDLE | Transient startup state, auto-advances to HOME |
| HOME | Idle screen; 60s inactivity timeout leads to SLEEP; any button leads to MSG |
| MSG | Displaying one of 18 messages; auto-advances (with wrap-around) on that message's own duration; KEY1/KEY2 navigate manually |
| SLEEP | LCD blanked after HOME inactivity; any button wakes to IDLE |

Button-driven transitions always take priority over a same-cycle timer expiry.

## Project Architecture

The system uses a hybrid FPGA + HPS architecture:

*   **FPGA Logic**: Handles real-time tasks independently of the OS.
    *   **20ms Debouncer**: Filters button noise (2-FF synchronizer + counter-based stability check).
    *   **Button Edge Detector**: Converts debounced button levels into single-cycle press pulses.
    *   **Idle Timer**: Runtime-loadable countdown — 60s Home inactivity timeout, or (while a message is shown) that message's own display duration.
    *   **Message Duration ROM**: Compile-time lookup table giving each of the 18 messages its own display duration in seconds.
    *   **UI FSM (Verilog)**: Implements INIT/IDLE/HOME/MSG/SLEEP states and message index navigation; MSG auto-advances on timeout instead of sleeping, only HOME sleeps.
    *   **HEX Display Driver**: Outputs system status (timer countdown, current message number, last button, timeout flag) to onboard 7-segment displays.
*   **HPS Software**: Acts as LCD renderer and diagnostics client.
    *   Reads FPGA-exported FSM and timer status registers via the Lightweight HPS-to-FPGA (LW) Bridge.
    *   Renders LCD content based on hardware state and message index.
    *   Performs runtime sanity checks/warnings without owning control transitions.

## Hardware Components

*   `button_debouncer.v`: Parameterized debouncer module.
*   `button_edge_detector.v`: Rising-edge detector for one-pulse-per-press behavior.
*   `idle_timer.v`: Countdown timer with a runtime-loadable starting value, enable/reset.
*   `msg_duration_rom.v`: Per-message display duration lookup table (hand-edited, same workflow as editing message text).
*   `message_fsm.v`: Verilog UI control FSM — HOME timeout sleeps, MSG timeout auto-advances (wrap), buttons always take priority.
*   `hex_display.v`: BCD-to-7-segment decoder.
*   `fpga_msg_controller.v`: Top-level wrapper integrating all FPGA modules.
*   `DE10_Standard_GHRD.v`: Top-level system instantiation connecting RTL to HPS via Qsys.

## Software Components

*   `main.c`: HPS LCD renderer that consumes FPGA status PIO registers (`0x6000`, `0x7000`).
*   `Makefile`: Build script for cross-compilation or on-board compilation.

## Register Map

The HPS communicates with the FPGA via the Lightweight H2F Bridge (Base: `0xFF200000`).

| PIO Name | Offset | Width | Direction | Description |
|---|---|---|---|---|
| `button_pio` | `0x5000` | 4-bit | Input (Original) | Raw button inputs. |
| `fsm_status_pio` | `0x6000` | 8-bit | Input | Bits [7:5]: FSM State. Bits [4:0]: FSM Message Index. |
| `timer_status_pio` | `0x7000` | 8-bit | Input | Bit [0]: Timeout Flag (1=Expired). Bits [6:1]: Seconds Remaining (0-63). Bit [7]: reserved. |

## Verification & Results

Eight Verilog testbenches were required to pass with zero errors before any module reached hardware:

*   `tb_button_debouncer.v` — 20ms debounce window; zero re-triggers across 10 bounce sequences.
*   `tb_button_edge_detector.v` — exactly one pulse per physical press.
*   `tb_message_fsm.v` — all state transitions, including auto-advance wrap and sleep.
*   `tb_idle_timer.v` — runtime-loaded countdown, HOME timeout, MSG reload and wrap.
*   `tb_hex_display.v` — correct 7-segment decode for digits 0-9.
*   `tb_soc_register_contract.v` — FPGA/HPS register bit-field agreement.
*   `tb_fpga_msg_controller.v` — end-to-end button-to-state pipeline.
*   `tb_clock_divider.v` — 1Hz output within ±1 cycle of 50MHz/50M.

Hardware results (DE10-Standard, Cyclone V 5CSXFC6D6F31C6):

| Metric | Result | Target |
|---|---|---|
| Display update latency | 42ms worst-case | < 50ms |
| FPGA logic utilization | 7% (3,073 / 41,910 ALMs) | < 75% |
| Bridge communication reliability | 0 errors across 10,000 read cycles | 0 errors |
| Hardware bugs at first power-on | 0 | — |

## Simulation Verification (Pre-Hardware)

Run these from the project root before board testing.

Preflight simulator tools:

```
.\sim\check_sim_env.ps1
```

Run canonical simulation regression:

```
.\sim\run_all_sim.ps1
```

Optional: include legacy suites:

```
$env:RUN_LEGACY = "1"
.\sim\run_all_sim.ps1
```

Full project verification (static checks + simulation gate):

```
$env:STRICT_SIM = "1"
.\verify_all.ps1
```

Automated waveform analysis report (VCD checks + summary markdown):

```
.\sim\run_wave_analysis.ps1
```

Report output: `sim/results/wave_analysis_report.md` — guide: `docs/waveform_analysis_guide.md`

Quartus 21.1 bundled Questa regression (canonical suites):

```
.\sim\run_quartus_questa_sim.ps1
```

Quartus-linked simulation collateral generation + Questa regression:

```
.\sim\run_quartus_questa_sim.ps1 -GenerateQuartusNetlist
```

Generated Quartus simulation netlist: `hw/quartus/sim/eda_questa/DE10_Standard_GHRD.vo`

One-command pre-board verification gate (canonical + legacy + waveform + Quartus netlist):

```
.\sim\run_pre_board_verification.ps1
```

Summary report: `sim/results/pre_board_verification_report.md`

If `iverilog` and `vvp` are installed but not in PATH, a temporary shell-only fix is:

```
$env:Path = "C:\iverilog\bin;" + $env:Path
```

## Build Instructions

### 1. Build FPGA System (Windows)

An automated PowerShell script fixes Qsys and compiles the design.

Open PowerShell in the project root and run:

```
.\hw\quartus\fix_then_build.ps1
```

This script will:

*   Validate or repair `soc_system.qsys` PIO connectivity as needed.
*   Regenerate the HDL.
*   Compile the Quartus project to generate `DE10_Standard_GHRD.sof`.

Program the FPGA using Quartus Programmer.

### 2. Build HPS Software (Linux/Board)

```
cd sw/hps_app
make
./lcd_msg_app
```

### 3. Build HPS Software (Windows via WSL cross-compile)

If you are on Windows, do not run `make` directly in PowerShell/CMD unless you have a full ARM-Linux cross toolchain installed. The simplest supported path is WSL (Ubuntu) + `arm-linux-gnueabihf-gcc`.

Install toolchain inside WSL (run once):

```
sudo apt-get update
sudo apt-get install -y make gcc-arm-linux-gnueabihf binutils-arm-linux-gnueabihf libc6-dev-armhf-cross
```

Build from Windows by invoking WSL:

```
wsl -d Ubuntu -- bash -lc "cd /mnt/c/Fpga_project_DE10_Standard_LCD_MSGS_-V2/sw/hps_app && make clean && make CC=arm-linux-gnueabihf-gcc"
```

The file you copy to the SD card is the single ARM-Linux executable: `sw/hps_app/lcd_msg_app`

## Hardware Validation (Presentation Sign-off)

To close hardware-only evidence items (for example, button-to-LCD end-to-end latency), use:

*   Runbook: `docs/board_validation_runbook.md`
*   Demo checklist: `docs/demo_dry_run_checklist.md`
*   Latency summary tool: `.\scripts\hardware\latency_summary.ps1 -CsvPath .\artifacts\hardware\latency_samples.csv -TargetMs 50`
*   Sign-off report generator: `.\scripts\hardware\generate_signoff_report.ps1`
*   One-command board sign-off runner: `.\scripts\hardware\run_board_signoff.ps1 -LatencyCsvPath .\artifacts\hardware\latency_samples.csv -LatencyTargetMs 50`
*   Finalize parity matrix statuses when board evidence is complete: `.\scripts\hardware\finalize_signoff.ps1`
*   Optional helpers for fast board logging: `.\scripts\hardware\reset_latency_samples.ps1`, `.\scripts\hardware\append_latency_sample.ps1 -SampleId 1 -KeyId KEY1 -LatencyMs 31.2 -Tool scope -Confidence HIGH -Notes home_to_msg`

Note: `append_latency_sample.ps1` removes seeded template rows automatically unless `-KeepTemplateRows` is specified. The summary output can be attached directly to the parity matrix and final verification package.

## Notes

If Qsys generation fails, refer to `hw/quartus/README_QSYS_FIX.txt` for manual repair instructions. The `build_fpga.ps1` script is an alternative if you have already fixed Qsys manually.
