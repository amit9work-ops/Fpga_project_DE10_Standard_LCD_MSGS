# HPS Renderer Test Report
Date: 2026-05-04

## Phase Results
| Phase | Result | Evidence |
| --- | --- | --- |
| Phase 1 | PASS | ARM build succeeded; lcd_msg_app is ELF 32-bit ARM EABI5 |
| Phase 2 | PASS | lcd_msg_test.exe builds and prints "=== Result: 0 / 0 ===" |
| Phase 3 | PASS | lcd_msg_test.exe prints "=== Result: 12 / 12 ===" |
| Phase 4 | PASS | ARM build EABI5, sims 8/8, HPS test 12/12, RBF timestamp preserved |

## Test Results (T01..T12)
| Test | Result |
| --- | --- |
| T01_INIT_splash | PASS |
| T02_IDLE_splash | PASS |
| T03_HOME_menu | PASS |
| T04_MSG_index_0 | PASS |
| T05_MSG_index_17 | PASS |
| T06_SLEEP_backlight_off | PASS |
| T07_invalid_state_5 | PASS |
| T08_invalid_state_0xFF | PASS |
| T09_msg_index_18_clamp | PASS |
| T10_msg_index_99_clamp | PASS |
| T11_register_decode | PASS |
| T12_backlight_transition | PASS |

## File Diff Summary
Added files (lines):
- sw/hps_app/render_screen.h (26)
- sw/hps_app/render_screen.c (74)
- sw/hps_app/test/mock_lcd.h (29)
- sw/hps_app/test/mock_lcd.c (78)
- sw/hps_app/test/test_lcd_render.c (133)
- artifacts/audit/HPS_RENDER_TEST_REPORT.md (46)

Modified files (delta lines):
- sw/hps_app/Makefile (+27/-2)
- sw/hps_app/main.c (+18/-46)
- sw/hps_app/messages.h (+2/-1)

## Final Verdict
HPS_RENDER_GO

## Remaining Risks
None noted.
