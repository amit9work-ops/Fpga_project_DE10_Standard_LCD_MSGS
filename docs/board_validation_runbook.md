# Board Validation Runbook

## Purpose

Provide a repeatable process to close hardware-only sign-off items before final presentation.

Primary open item: end-to-end button-to-LCD latency evidence (C-006).

## Prerequisites

1. FPGA programmed with current `.sof` build.
2. HPS app running (`./lcd_msg_app`).
3. At least one capture tool:
- Preferred: oscilloscope or logic analyzer.
- Fallback: high-frame-rate phone video (lower confidence; use only if no scope available).

## Measurement Definition

Latency is measured from:

- Start event (`t0`): physical key press edge on board button line (or probe proxy edge).
- End event (`t1`): first LCD-visible state change tied to that key press.

Compute per-sample latency:

$$
L_{ms} = (t1 - t0)\times 1000
$$

## Capture Procedure (Scope/Logic Analyzer)

1. Probe one key signal and one LCD activity signal (SPI clock/data or display update marker).
2. Trigger on key press edge.
3. Capture until first LCD update edge appears.
4. Record sample in `artifacts/hardware/latency_samples.csv`.
5. Repeat for at least 20 samples across multiple keys (KEY0, KEY1, KEY2 recommended).

## Capture Procedure (Fallback Video)

1. Record at highest available frame rate.
2. Ensure both button action and LCD region are visible.
3. Step frame-by-frame to estimate `t0` and `t1`.
4. Convert frame delta to milliseconds.
5. Mark confidence as `LOW` in notes.

## Artifact Format

Use CSV header:

```
sample_id,key_id,latency_ms,tool,confidence,notes
```

Example row:

```
1,KEY1,32.4,scope,HIGH,home_to_msg
```

## Summary/Pass Criteria

Run:

```powershell
.\scripts\hardware\latency_summary.ps1 -CsvPath .\artifacts\hardware\latency_samples.csv -TargetMs 50
```

Recommended acceptance:

1. Maximum measured latency <= target threshold.
2. Mean latency <= target threshold.
3. No unexplained outliers without root-cause notes.

## Required Deliverables

1. Raw capture set (scope screenshots or analyzer export, or fallback video references).
2. `latency_samples.csv` with >=20 samples.
3. Script output summary (mean, min, max, pass/fail).
4. Update `artifacts/presentation_parity_matrix.md` C-006 from `Open` to `Satisfied` with artifact references.

## Troubleshooting

1. If latency spikes occur, verify HPS app is running with minimal background load.
2. If no LCD transition is visible, confirm FPGA FSM state changes are visible at `0x6000`.
3. If timer behavior is inconsistent, verify `0x7000` updates and timeout logic.