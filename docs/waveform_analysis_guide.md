# Waveform Analysis Guide

## Purpose
This guide defines how to validate waveform-level behavior for the DE10 LCD message controller project.

## Fast Path (Automated)
Run:

```powershell
.\sim\run_wave_analysis.ps1
```

For full pre-board verification (canonical + legacy + waveform + Quartus netlist):

```powershell
.\sim\run_pre_board_verification.ps1
```

Generated summary report:
- `sim/results/pre_board_verification_report.md`

Outputs:
- `sim/results/wave_analysis_report.md`
- Existing VCD files in `sim/results/*.vcd`

PASS criteria used by the script:
- Required VCD artifacts exist.
- `tb_fpga_msg_controller.vcd` has a measurable clock period.
- `timeout_flag` rises at least once.
- `btn_pulse` intervals are exactly one clock period wide.
- FSM visits IDLE/HOME/MSG/SLEEP states.

## Quartus 21.1 + Questa Flow
Run canonical RTL suites with Quartus-bundled simulator:

```powershell
.\sim\run_quartus_questa_sim.ps1
```

Generate Quartus simulation collateral first, then run suites:

```powershell
.\sim\run_quartus_questa_sim.ps1 -GenerateQuartusNetlist
```

Artifacts:
- Transcript: `sim/results/questa_regression.log`
- Quartus generated netlist (if enabled): `hw/quartus/sim/eda_questa/DE10_Standard_GHRD.vo`

## GTKWave Critical View
Reusable GTKWave savefile:
- `sim/gtkw/tb_fpga_msg_controller_critical.gtkw`

Launch GTKWave through the pre-board runner:

```powershell
.\sim\run_pre_board_verification.ps1 -LaunchGtkWave
```

If `gtkwave` is not in PATH, provide the executable path:

```powershell
.\sim\run_pre_board_verification.ps1 -LaunchGtkWave -GtkWaveExe "C:\path\to\gtkwave.exe"
```

Critical scenarios to inspect in GTKWave:
- Wake path: `btn_pulse` while `fsm_state=SLEEP` causes `fsm_state -> IDLE` and timeout clear.
- Navigation path: `IDLE -> HOME -> MSG` via KEY pulses, with `fsm_msg_index` behavior in MSG.
- Home timeout path: `seconds_remaining` counts down from TIMEOUT_SEC (60s default) to 0 in HOME, `timeout_flag` asserts, FSM transitions to SLEEP.
- MSG auto-advance path: `seconds_remaining` counts down from the current message's duration (`msg_duration_rom.v`, indexed by `fsm_msg_index`) to 0, `timeout_flag` pulses, `fsm_msg_index` auto-advances (wrap), FSM stays in MSG (does NOT sleep). Confirm a freshly-entered message reloads with its OWN duration, not the previous message's.

## Manual Visual Inspection (Optional)
For focused debugging, inspect these signals in `tb_fpga_msg_controller.vcd`:
- `clk`
- `key_in[3:0]`
- `btn_debounced[3:0]`
- `btn_pulse[3:0]`
- `seconds_remaining[5:0]`
- `timeout_flag`
- `fsm_state[2:0]`
- `fsm_msg_index[4:0]`

Expected timing behavior:
- Debounced button transitions occur only after debounce window is satisfied.
- `btn_pulse` is exactly one cycle per accepted press.
- Timeout in HOME drives SLEEP; timeout in MSG auto-advances to the next message (wrap) instead and stays in MSG.
- Any valid button pulse while sleeping returns FSM to IDLE.
