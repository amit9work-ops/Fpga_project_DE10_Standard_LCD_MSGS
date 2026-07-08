# Demo Dry-Run Checklist

## Purpose

Provide a single execution checklist for final board demo rehearsal and sign-off artifact capture.

## Inputs

1. Bitstream programmed to board.
2. HPS app built and runnable (`./lcd_msg_app`).
3. Simulation and static verification completed.
4. Optional measurement tools: scope/logic analyzer for latency evidence.

## Pre-Demo Gate

1. Run strict verification from project root:

```powershell
$env:STRICT_SIM = "1"
.\verify_all.ps1
```

2. Confirm canonical regression passes:

```powershell
.\sim\run_all_sim.ps1
```

3. Confirm no unresolved blocker in parity matrix (`C-001`..`C-008`).

## Board Demo Sequence

1. Program FPGA and boot HPS application.
2. Observe idle screen on LCD.
3. Press any key and confirm transition from IDLE to HOME.
4. Enter message mode and verify KEY1/KEY2 navigation.
5. Verify KEY0 back navigation.
6. In message mode, do not press any key and confirm each message auto-advances to the next after its own configured duration (`hw/rtl/msg_duration_rom.v`) — the system should keep slideshowing, not sleep.
7. Press KEY0 to return to HOME, then wait for HOME's inactivity timeout (60s default) and confirm SLEEP behavior.
8. Wake from SLEEP with any key and confirm return path.

## Pass/Fail Criteria

1. No stuck states.
2. No contradictory LCD content/state transitions.
3. HOME timeout consistent with FSM state and timer status (SLEEP); MSG timeout auto-advances instead of sleeping.
4. Navigation wrap-around behaves as expected, both for manual next/prev and for timeout-driven auto-advance.
5. Latency evidence collected if required by presentation claim.

## Required Artifacts

1. Verification summary output (strict mode).
2. Demo checklist execution notes.
3. Latency CSV and summary output (if C-006 must be closed).
4. Optional photos/videos/scope captures.

## Artifact Paths

1. `artifacts/hardware/demo_checklist_log.md`
2. `artifacts/hardware/latency_samples.csv`
3. `artifacts/hardware/signoff_report.md`

## Closure

After successful dry-run, update `docs/presentation_parity_matrix.md`:

1. Set `C-008` to `Satisfied`.
2. If latency target is met and evidence is attached, set `C-006` to `Satisfied`.
