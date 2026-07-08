# =============================================================================
# run_all_sim.ps1 — DE10-Standard LCD Message System Simulation Runner
# Run from: c:\Fpga_project_DE10_Standard_LCD_MSGS_-V2\
# Requires: Icarus Verilog (iverilog + vvp) in PATH
# =============================================================================

$ErrorActionPreference = "Continue"   # Do NOT Stop on native tool warnings

# --- Resolve workspace root (parent of the 'sim' folder containing this script) ---
$ROOT = Split-Path -Parent $PSScriptRoot

function Test-SimToolchain {
    $iverilogCmd = Get-Command "iverilog" -ErrorAction SilentlyContinue
    $vvpCmd = Get-Command "vvp" -ErrorAction SilentlyContinue

    if ($iverilogCmd -and $vvpCmd) {
        return $true
    }

    Write-Host ""
    Write-Host "ERROR: Required simulator tools not found in PATH." -ForegroundColor Red
    if (-not $iverilogCmd) {
        Write-Host "  - Missing: iverilog" -ForegroundColor Red
    }
    if (-not $vvpCmd) {
        Write-Host "  - Missing: vvp" -ForegroundColor Red
    }

    Write-Host "" 
    Write-Host "Install Icarus Verilog (Windows):" -ForegroundColor Yellow
    Write-Host "  1) Download from: https://bleyer.org/icarus/" -ForegroundColor Yellow
    Write-Host "  2) Install, then add its bin folder to PATH" -ForegroundColor Yellow
    Write-Host "     Example path: C:\iverilog\bin" -ForegroundColor Yellow
    Write-Host "  3) Open a new PowerShell and verify:" -ForegroundColor Yellow
    Write-Host "       iverilog -V" -ForegroundColor Yellow
    Write-Host "       vvp -V" -ForegroundColor Yellow

    Write-Host ""
    Write-Host "Optional quick PATH add for current shell:" -ForegroundColor Cyan
    Write-Host '  $env:Path += ";C:\iverilog\bin"' -ForegroundColor Cyan
    Write-Host ""

    return $false
}

# --- Check simulator toolchain availability ---
if (-not (Test-SimToolchain)) {
    exit 1
}

# --- Create results directory ---
$RESULTS = "$ROOT\sim\results"
New-Item -ItemType Directory -Force -Path $RESULTS | Out-Null

# --- Path shortcuts ---
$RTL  = "$ROOT\hw\rtl"
$TBH  = "$ROOT\hw\sim\testbenches"   # canonical testbenches (correct interfaces)
$TBS  = "$ROOT\sim\testbenches_legacy"  # legacy testbenches (fixed)

# --- Tracking ---
$pass = 0
$fail = 0

# =============================================================================
# Helper: compile with iverilog, then simulate with vvp
# =============================================================================
function Invoke-Sim {
    param(
        [string]   $Name,       # short test name
        [string[]] $Sources     # all .v files (TB first, then RTL)
    )

    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $Name" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan

    $out = "$RESULTS\$Name.vvp"

    # --- Compile ---
    $compileOut = & iverilog -g2012 -Wall -o $out @Sources 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [COMPILE FAIL]" -ForegroundColor Red
        $compileOut | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        $script:fail++
        return
    }
    if ($compileOut) {
        # Show warnings even on success
        $compileOut | ForEach-Object { Write-Host "  WARN: $_" -ForegroundColor Yellow }
    }
    Write-Host "  Compile OK" -ForegroundColor Green

    # --- Simulate (run from results dir so VCD files land there) ---
    Push-Location $RESULTS
    $simOut = & vvp $out 2>&1
    $simExit = $LASTEXITCODE
    Pop-Location

    $simOut | ForEach-Object { Write-Host "  $_" }

    if ($simExit -ne 0) {
        Write-Host "  [SIM FAIL] vvp exit code $simExit" -ForegroundColor Red
        $script:fail++
    } else {
        # Heuristic: detect real test failures (avoid matching "Failed : 0" summary lines)
        $combinedOut = $simOut -join "`n"
        $hasFail = $combinedOut -match "SOME TESTS FAILED|FAIL Test \d|\[FAIL\]|FAILURES DETECTED|error:|\[PULSE WIDTH ERROR\]|FAIL \[TIMEOUT\]|\bassert(?:ion)?\b"
        if ($hasFail) {
            Write-Host "  [RESULT] FAILURES DETECTED in output" -ForegroundColor Red
            $script:fail++
        } else {
            Write-Host "  [RESULT] PASSED" -ForegroundColor Green
            $script:pass++
        }
    }
}

# =============================================================================
# PHASE 1 — Canonical unit tests (hw/sim/testbenches/)
# =============================================================================

Write-Host ""
Write-Host "###########################################################"
Write-Host "#   PHASE 1: UNIT TESTS (hw/sim/testbenches/)            #"
Write-Host "###########################################################"

# --- TC-1: button_debouncer (4-channel, correct parameter name) ---
Invoke-Sim "tb_button_debouncer_unit" @(
    "$TBH\tb_button_debouncer.v",
    "$RTL\button_debouncer.v"
)

# --- TC-2: button_edge_detector ---
Invoke-Sim "tb_button_edge_detector" @(
    "$TBH\tb_button_edge_detector.v",
    "$RTL\button_edge_detector.v"
)

# --- TC-3: idle_timer ---
Invoke-Sim "tb_idle_timer" @(
    "$TBH\tb_idle_timer.v",
    "$RTL\idle_timer.v"
)

# --- TC-4: hex_display ---
Invoke-Sim "tb_hex_display" @(
    "$TBH\tb_hex_display.v",
    "$RTL\hex_display.v"
)

# --- TC-5: message_fsm (Verilog control FSM) ---
Invoke-Sim "tb_message_fsm" @(
    "$TBH\tb_message_fsm.v",
    "$RTL\message_fsm.v"
)

# =============================================================================
# PHASE 2 — Integration test (full fpga_msg_controller)
# =============================================================================

Write-Host ""
Write-Host "###########################################################"
Write-Host "#   PHASE 2: INTEGRATION TEST                            #"
Write-Host "###########################################################"

Invoke-Sim "tb_fpga_msg_controller" @(
    "$TBH\tb_fpga_msg_controller.v",
    "$RTL\fpga_msg_controller.v",
    "$RTL\message_fsm.v",
    "$RTL\msg_duration_rom.v",
    "$RTL\button_debouncer.v",
    "$RTL\button_edge_detector.v",
    "$RTL\idle_timer.v",
    "$RTL\hex_display.v"
)

# --- TC-6: SoC register packing contract ---
Invoke-Sim "tb_soc_register_contract" @(
    "$TBH\tb_soc_register_contract.v"
)

# --- TC-7: top_level standalone integration ---
Invoke-Sim "tb_top_level" @(
    "$TBS\tb_top_level.v",
    "$RTL\top_level.v",
    "$RTL\fpga_msg_controller.v",
    "$RTL\message_fsm.v",
    "$RTL\msg_duration_rom.v",
    "$RTL\button_debouncer.v",
    "$RTL\button_edge_detector.v",
    "$RTL\idle_timer.v",
    "$RTL\hex_display.v"
)

# =============================================================================
# PHASE 3 — Legacy testbenches (optional)
# =============================================================================

$runLegacy = $env:RUN_LEGACY -eq "1"

if ($runLegacy) {
    Write-Host ""
    Write-Host "###########################################################"
    Write-Host "#   PHASE 3: LEGACY TESTBENCHES (sim/testbenches_legacy/) #"
    Write-Host "###########################################################"

    # --- TC-L1: button_debouncer single-channel (legacy) ---
    Invoke-Sim "tb_button_debouncer_legacy" @(
        "$TBS\tb_button_debouncer.v",
        "$RTL\button_debouncer.v"
    )

    # --- TC-L2: clock_divider (legacy path) ---
    Invoke-Sim "tb_clock_divider" @(
        "$TBS\tb_clock_divider.v",
        "$RTL\clock_divider.v"
    )
} else {
    Write-Host ""
    Write-Host "[INFO] Skipping optional legacy suites. Set RUN_LEGACY=1 to include them." -ForegroundColor Yellow
}

# =============================================================================
# FINAL SUMMARY
# =============================================================================
$total = $pass + $fail
Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "  SIMULATION SUMMARY" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "  Total Suites : $total"
Write-Host "  Passed       : $pass" -ForegroundColor Green
if ($fail -gt 0) {
    Write-Host "  Failed       : $fail" -ForegroundColor Red
} else {
    Write-Host "  Failed       : $fail" -ForegroundColor Green
}
Write-Host ""
if ($fail -eq 0) {
    Write-Host "  *** ALL SIMULATION SUITES PASSED ***" -ForegroundColor Green
} else {
    Write-Host "  *** $fail SUITE(S) FAILED - fix before proceeding to synthesis ***" -ForegroundColor Red
}
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host ""
Write-Host "  VCD waveform files saved to: $RESULTS"
Write-Host ""
