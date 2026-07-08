# Presentation Parity Matrix

## Purpose

This document is the execution control sheet for aligning implementation with presentation claims.

Each claim is mapped to:
- Current implementation evidence.
- Verification evidence.
- Gap decision (none/code/doc/test/hardware-measurement).
- Closure owner and completion criteria.

## Claim Matrix

| Claim ID | Presentation Claim | Current Status | Evidence (Code/Doc/Test) | Gap Type | Required Action | Owner | Exit Criteria |
|---|---|---|---|---|---|---|---|
| C-001 | FPGA owns real-time button processing | Satisfied | hw/rtl/button_debouncer.v, hw/rtl/button_edge_detector.v, hw/sim/testbenches/tb_button_debouncer.v | None | Keep under regression gate | FPGA | Canonical regression remains green |
| C-002 | FPGA owns UI FSM transitions | Satisfied | hw/rtl/message_fsm.v, hw/rtl/fpga_msg_controller.v, hw/sim/testbenches/tb_message_fsm.v | None | Keep under regression gate | FPGA | FSM and integration suites pass |
| C-003 | HPS renders LCD based on FPGA status | Satisfied | sw/hps_app/main.c, hw/sim/testbenches/tb_soc_register_contract.v | None | Maintain register contract | HPS+FPGA | Contract test remains green |
| C-004 | SoC register export for FSM/timer is stable | Satisfied | hw/quartus/soc_system.qsys, hw/quartus/DE10_Standard_GHRD.v, hw/sim/testbenches/tb_soc_register_contract.v | None | Keep address/packing frozen | FPGA | No contract regressions |
| C-005 | Debounce and timer behavior are verified pre-board | Satisfied | hw/sim/testbenches/tb_button_debouncer.v, hw/sim/testbenches/tb_idle_timer.v, docs/verification_report.md | None | Keep tests mandatory | Verification | Canonical regression pass |
| C-006 | End-to-end button-to-LCD latency meets presentation target | In Progress | docs/board_validation_runbook.md, scripts/hardware/latency_summary.ps1 | Hardware-measurement | Capture board latency CSV artifacts and compute summary against target | Verification | Measured latency <= target |
| C-007 | Resource usage is within presentation budget | Satisfied | hw/quartus/output_files/DE10_Standard_GHRD.fit.rpt | None | Preserve utilization margin | FPGA | Utilization remains below claim threshold |
| C-008 | Final demo flow is reproducible | In Progress | README.md, docs/board_validation_runbook.md, docs/demo_dry_run_checklist.md, scripts/hardware/generate_signoff_report.ps1, verify_all.ps1, sim/run_all_sim.ps1, artifacts/hardware/demo_checklist_log.md, artifacts/hardware/signoff_report.md | Doc/Test | Execute board runbook once and record pass/fail checklist artifacts | Project | Dry-run completed end-to-end |

## User-Provided Claims To Add

Add externally provided presentation claims here before changing implementation. New claims should be inserted as C-009+ with objective acceptance criteria.

## Decision Log

- Conflict policy: when implementation and presentation differ, implementation will be changed to match presentation.
- Source of truth for unresolved claims: user-provided presentation statements (external to repository).
- 2026-03-30: strict pre-demo verification passed (8/8 canonical simulation suites). Remaining open items are hardware evidence and board dry-run execution.

## Execution Checklist

1. Add all missing presentation claims to matrix.
2. Mark each claim with one gap type only.
3. Implement code changes first for code gaps.
4. Add or adjust tests for every changed behavior.
5. Regenerate evidence artifacts (sim/timing/fitter/hardware measurements).
6. Mark claim closed only with objective artifact reference.
