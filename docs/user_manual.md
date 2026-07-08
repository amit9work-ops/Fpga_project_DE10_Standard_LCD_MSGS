# User Manual

How to operate the DE10-Standard LCD Message System as an end user (e.g. running it in a treatment room). For build/deployment instructions, see [README_RUN_DE10_STANDARD.md](../README_RUN_DE10_STANDARD.md). For the technical design, see [architecture.md](architecture.md).

## Buttons

| Button | Function |
|---|---|
| `KEY0` | Back / dismiss — returns to the Home screen from a message, or wakes the display from sleep |
| `KEY1` | Next message (in message mode); also wakes the display and enters Home from idle |
| `KEY2` | Previous message (in message mode); also wakes the display and enters Home from idle |
| `KEY3` | Wakes the display / registers as activity; not used for navigation |

## Screens

- **Idle**: display is asleep/blank. Press any button to wake it.
- **Home**: the welcome/menu screen. Press `KEY1` or `KEY2` to open the message list. If left untouched for **60 seconds**, the display goes back to sleep (Idle).
- **Messages**: shows one of 18 physiotherapy/rehab messages (welcome, breathing exercises, physical exercises, rest, waiting, instructions, session status, completion, and emergency alerts). `KEY1`/`KEY2` move to the next/previous message (wrapping around at the ends); `KEY0` returns to Home.
  - Each message automatically advances to the next one on its own after a few seconds — you don't need to press anything to keep it moving. The exact duration is different per message (longer for exercises you need time to perform, shorter for quick status alerts).
  - Pressing a button at any time immediately overrides the automatic advance and does what you'd expect (go to the next/previous message, or back to Home).

## On-board indicators (for demo/debugging, not needed for normal use)

- **HEX0:HEX1** (rightmost two 7-segment digits): shows the current message number (00–17) while a message is displayed; reads `00` on the Home screen or when asleep.
- **HEX4:HEX5**: shows the live countdown, in seconds, until the current screen either advances (in message mode) or goes to sleep (on the Home screen).
- **HEX2**: shows which button (0–3) was pressed most recently; shows `F` if no button has been pressed since power-on.
- **LEDR[3:0]**: lit while the corresponding `KEY` is physically held down.
- **LEDR[9]**: blinks briefly every time the countdown reaches zero — i.e. every automatic message advance, and every time the Home screen goes to sleep.

## Summary of timing

| Behavior | Duration |
|---|---|
| Home screen inactivity timeout (goes to sleep) | 60 seconds (default) |
| Each message's auto-advance duration | Varies per message, roughly 6–15 seconds — see `hw/rtl/msg_duration_rom.v` |
