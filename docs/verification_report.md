# DE10-Standard LCD Message System V2 - Verification Report

## Purpose
This report maps requirements to simulations and records expected evidence for sign-off before hardware testing.

## Traceability Matrix

| Requirement | Verification Artifact | Pass Evidence |
|---|---|---|
| R1 Debounce behavior | hw/sim/testbenches/tb_button_debouncer.v | Clean press/release acceptance and bounce rejection pass |
| R2 Single pulse per press | hw/sim/testbenches/tb_button_edge_detector.v | Rising-edge pulse only, no re-trigger while held |
| R3 Idle timeout behavior | hw/sim/testbenches/tb_idle_timer.v | Exact countdown and timeout/reset behavior pass |
| R4 HEX exact encoding | hw/sim/testbenches/tb_hex_display.v | Exhaustive 0-F exact segment mapping pass |
| R3+R4 Integrated behavior | hw/sim/testbenches/tb_fpga_msg_controller.v | Exact pulse-width and exact HEX checks pass |
| R7 Verilog UI FSM behavior | hw/sim/testbenches/tb_message_fsm.v | INIT/IDLE/HOME/MSG/SLEEP transitions, timeout priority, and message index wrap-around pass |
| R6 SoC register contract (FSM export) | hw/sim/testbenches/tb_soc_register_contract.v | fsm_status[7:5]=state and fsm_status[4:0]=msg_index mapping pass |
| R5 Top-level wiring | sim/testbenches/tb_top_level.v | LED/HEX wiring and timeout behavior pass |
| V3 Clock utility quality | sim/testbenches/tb_clock_divider.v | 1s tick observed; strict count and pulse-width checks pass |
| V4 Regression execution | sim/run_all_sim.ps1 | Single summary reports all suites passed |
| Waveform structural checks | sim/run_wave_analysis.ps1 | Auto-generated report verifies pulse width, timeout edge, and FSM state coverage from VCD |
| Quartus 21.1 Questa regression | sim/run_quartus_questa_sim.ps1 | Canonical suites run under Quartus-bundled Questa with transcript log |
| Pre-board full verification gate | sim/run_pre_board_verification.ps1 | One command executes regression, waveform checks, event extraction, and Quartus netlist compatibility |

## Test Execution Checklist

1. Run simulator preflight:
	powershell -ExecutionPolicy Bypass -File .\\sim\\check_sim_env.ps1

2. Run simulation regression:
	powershell -ExecutionPolicy Bypass -File .\\sim\\run_all_sim.ps1

3. Confirm no failures in any suite output.

4. Confirm VCD files were generated in sim/results for debug evidence.

## Sign-off Criteria

- All suites listed in the traceability matrix pass.
- No timeout-triggered termination in any suite.
- No pulse-width violation reports.
- No unresolved requirement in docs/requirements.md.

## Notes

- This report is simulation-focused and intended for pre-hardware clearance.
- Hardware bring-up should start only after all sign-off criteria are satisfied.

## Performance Evidence Tracking

| Item | Source Artifact | Status | Notes |
|---|---|---|---|
| Debounce window correctness | hw/rtl/button_debouncer.v + hw/sim/testbenches/tb_button_debouncer.v | Closed (simulation) | Parameterized 20 ms behavior validated in unit simulation. |
| Timer countdown correctness | hw/rtl/idle_timer.v + hw/sim/testbenches/tb_idle_timer.v | Closed (simulation) | Deterministic clock-driven countdown behavior validated. |
| FSM transition correctness | hw/rtl/message_fsm.v + hw/sim/testbenches/tb_message_fsm.v | Closed (simulation) | Directed and deep transition coverage present. |
| Register contract stability | hw/sim/testbenches/tb_soc_register_contract.v | Closed (simulation) | Packing for FSM/timer status verified. |
| FPGA utilization budget | hw/quartus/output_files/DE10_Standard_GHRD.fit.rpt | Closed (report) | Utilization evidence available in fitter report artifact (7% ALMs). |
| End-to-end button-to-LCD latency target | Board measurement artifact (scope/logic analyzer) | Open | Expected latency ~35 ms with 20 ms debounce + 5 ms polling; requires hardware capture. |
