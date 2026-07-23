# Diagram sources

Each `.tex` file here is a standalone, self-contained TikZ diagram: the vector source behind the corresponding PNG in [`assets/images/`](../images/). They were extracted from the project's final report and wrapped in the `standalone` document class so each one compiles independently.

## Rebuilding a diagram

Requires a TeX distribution with TikZ (MiKTeX or TeX Live) and Poppler (`pdftocairo`, for PNG export).

```
pdflatex -interaction=nonstopmode 01_soc_bridge_transaction.tex
pdftocairo -png -r 400 -singlefile 01_soc_bridge_transaction.pdf ../images/01_soc_bridge_transaction
```

Repeat per file, or loop over `*.tex` in this directory. Each diagram auto-crops to its content (`border=10pt`), so the rendered PNG needs no further trimming.

## Files

| File | Diagram |
|---|---|
| `01_soc_bridge_transaction.tex` | Cyclone V SoC block diagram: FPGA fabric, HPS, and the Lightweight Bridge |
| `02_fsm_state_diagram.tex` | UI FSM state transition diagram (INIT/MSG/SLEEP) |
| `03_register_bitfield_layout.tex` | `fsm_status_pio` / `timer_status_pio` / `msg_text_status_pio` bit-field layout |
| `04_ai_assisted_workflow.tex` | Iterative AI-assisted design loop (architecture → generation → verification → integration) |
| `05_verification_funnel.tex` | Defense-in-depth verification funnel (6 narrowing gates) |
| `06_fpga_datapath_block_diagram.tex` | FPGA real-time datapath: debounce chain through to the Lightweight Bridge |
| `07_hps_software_polling_flow.tex` | HPS software polling/render flowchart (seqlock read, round-2 3-state SLEEP check) |
| `08_token_efficiency_comparison.tex` | Illustrative token-count comparison, distilled spec vs. raw source |
