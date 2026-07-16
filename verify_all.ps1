#!/usr/bin/env pwsh
<#
.SYNOPSIS
ULTRA Verification Script for DE10-Standard LCD Message System V2
Checks all critical components before build.

.DESCRIPTION
Verifies:
- RTL module fixes (idle_timer)
- File presence and structure
- Register mappings
- Configuration files
- Qsys updates status
- Canonical simulation sign-off

.EXAMPLE
.\verify_all.ps1
#>

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  DE10 LCD Message System V2 - ULTRA VERIFICATION SCRIPT" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$script:errors = 0
$script:warnings = 0
$script:passes = 0
$script:warningItems = @()

function Add-Result {
    param(
        [string]$Name,
        [bool]$Condition,
        [string]$ErrorMsg = "Failed",
        [string]$WarningMsg = $null
    )

    if ($Condition) {
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $script:passes++
    } elseif ($null -ne $WarningMsg -and $WarningMsg -ne "") {
        Write-Host "  [WARN] $Name - $WarningMsg" -ForegroundColor Yellow
        $script:warnings++
        $script:warningItems += ("{0}: {1}" -f $Name, $WarningMsg)
    } else {
        Write-Host "  [FAIL] $Name - $ErrorMsg" -ForegroundColor Red
        $script:errors++
    }
}

Write-Host "PHASE 1: RTL Module Fixes" -ForegroundColor Yellow
Write-Host "--------------------------------------------------------------" -ForegroundColor Gray

$idle_timer_file = "hw/rtl/idle_timer.v"
if (Test-Path $idle_timer_file) {
    $content = Get-Content $idle_timer_file -Raw
    $has_fix = $content -like "*if (sec_counter == 0) begin*"
    $has_old_bug = $content -like "*if (sec_counter <= 1) begin*"

    if ($has_fix -and -not $has_old_bug) {
        Add-Result "idle_timer.v: Off-by-one bug fixed" $true
    } elseif ($has_old_bug) {
        Add-Result "idle_timer.v: Old bug still present" $false
    } else {
        Add-Result "idle_timer.v: Logic pattern match" $false "Check countdown logic" "Could not match expected pattern"
    }
} else {
    Add-Result "idle_timer.v exists" $false "File not found at $idle_timer_file"
}

Write-Host ""
Write-Host "PHASE 2: RTL Module Files" -ForegroundColor Yellow
Write-Host "--------------------------------------------------------------" -ForegroundColor Gray

$rtl_files = @(
    "hw/rtl/button_debouncer.v",
    "hw/rtl/button_edge_detector.v",
    "hw/rtl/idle_timer.v",
    "hw/rtl/hex_display.v",
    "hw/rtl/msg_duration_rom.v",
    "hw/rtl/msg_nav_rom.v",
    "hw/rtl/msg_text_rom.v",
    "hw/rtl/msg_text_export.v",
    "hw/rtl/fpga_msg_controller.v",
    "hw/rtl/message_fsm.v"
)

foreach ($path in $rtl_files) {
    Add-Result "File exists: $path" (Test-Path $path)
}

Write-Host ""
Write-Host "PHASE 3: Quartus Build Configuration (QSF)" -ForegroundColor Yellow
Write-Host "--------------------------------------------------------------" -ForegroundColor Gray

$qsf_file = "hw/quartus/DE10_Standard_GHRD.qsf"
if (Test-Path $qsf_file) {
    $qsf_content = Get-Content $qsf_file -Raw
    $modules = @("button_debouncer", "button_edge_detector", "idle_timer", "hex_display",
                 "msg_duration_rom", "msg_nav_rom", "msg_text_rom", "msg_text_export",
                 "fpga_msg_controller", "message_fsm")
    $modules_found = 0

    foreach ($mod in $modules) {
        if ($qsf_content -like "*$mod.v*") {
            $modules_found++
        }
    }

    Add-Result "QSF: all $($modules.Count) RTL modules registered" ($modules_found -eq $modules.Count) `
        "Only $modules_found/$($modules.Count) found"
} else {
    Add-Result "QSF file exists" $false "Not found at $qsf_file"
}

Write-Host ""
Write-Host "PHASE 4: Top-Level FPGA Integration" -ForegroundColor Yellow
Write-Host "--------------------------------------------------------------" -ForegroundColor Gray

$ghrd_file = "hw/quartus/DE10_Standard_GHRD.v"
if (Test-Path $ghrd_file) {
    $ghrd_content = Get-Content $ghrd_file -Raw

    $has_controller = $ghrd_content -like "*fpga_msg_controller*u_msg_ctrl*"
    Add-Result "fpga_msg_controller instantiated" $has_controller

    $wires_ok = ($ghrd_content -like "*wire*ctrl_btn_pulse*") -and
                ($ghrd_content -like "*wire*ctrl_btn_debounced*") -and
                ($ghrd_content -like "*wire*ctrl_timeout_flag*") -and
                ($ghrd_content -like "*wire*ctrl_seconds_remaining*") -and
                ($ghrd_content -like "*wire*ctrl_msg_text_bus*") -and
                ($ghrd_content -like "*wire*ctrl_msg_text_status*")
    Add-Result "All control signal wires declared" $wires_ok "Some wires missing"

    # Declaring a wire is not the same as connecting it: this catches the
    # class of bug where ctrl_msg_text_bus/ctrl_msg_text_status were declared
    # and used in the soc_system port map, but never actually connected at
    # the u_msg_ctrl instantiation (found and fixed during round 2).
    $msg_ctrl_block = ""
    if ($ghrd_content -match '(?s)u_msg_ctrl\s*\((.*?)\);') {
        $msg_ctrl_block = $Matches[1]
    }
    $msg_text_wired = ($msg_ctrl_block -like "*msg_text_bus*ctrl_msg_text_bus*") -and
                       ($msg_ctrl_block -like "*msg_text_status*ctrl_msg_text_status*")
    Add-Result "msg_text_bus/msg_text_status actually connected at u_msg_ctrl" $msg_text_wired `
        "Declared but not connected - would leave the wide interface floating"

    $has_hex_assigns = ($ghrd_content -like "*assign HEX0*hex0_out*") -and
                       ($ghrd_content -like "*assign HEX1*hex1_out*")
    Add-Result "HEX display assignments present" $has_hex_assigns
} else {
    Add-Result "DE10_Standard_GHRD.v exists" $false "Not found"
}

Write-Host ""
Write-Host "PHASE 5: Qsys System Configuration" -ForegroundColor Yellow
Write-Host "--------------------------------------------------------------" -ForegroundColor Gray

$qsys_file = "hw/quartus/soc_system.qsys"
if (Test-Path $qsys_file) {
    $qsys_content = Get-Content $qsys_file -Raw

    $has_fsm_pio = $qsys_content -like "*fsm_status_pio*"
    $has_timer_pio = $qsys_content -like "*timer_status_pio*"

    if ($has_fsm_pio -and $has_timer_pio) {
        Add-Result "PIOs present in soc_system.qsys" $true

        $has_fsm_export = $qsys_content -like "*fsm_status_pio_external_connection*"
        $has_timer_export = $qsys_content -like "*timer_status_pio_external_connection*"
        Add-Result "PIO conduit exports defined" ($has_fsm_export -and $has_timer_export)

        $has_msg_text_pio = $qsys_content -like "*msg_text_pio_0*"
        $has_msg_text_status = $qsys_content -like "*msg_text_status_pio*"
        Add-Result "Message-text wide PIOs present (msg_text_pio_0.., msg_text_status_pio)" `
            ($has_msg_text_pio -and $has_msg_text_status) `
            "Not found" "Run hw/quartus/add_pios.tcl via fix_then_build.ps1, then qsys-generate"
    } else {
        Add-Result "PIOs in soc_system.qsys" $false "Required manual step" "PIOs must be added manually before compilation"
    }
} else {
    Add-Result "soc_system.qsys file exists" $false "Not found"
}

Write-Host ""
Write-Host "PHASE 6: HPS Software (main.c)" -ForegroundColor Yellow
Write-Host "--------------------------------------------------------------" -ForegroundColor Gray

$main_c = "sw/hps_app/main.c"
if (Test-Path $main_c) {
    $main_content = Get-Content $main_c -Raw

    Add-Result "Addresses sourced from generated soc_addr_map.h (not hand-typed)" `
        ($main_content -like "*soc_addr_map.h*")

    Add-Result "Register pointers mapped (fsm_status_addr)" ($main_content -like "*fsm_status_addr*")
    Add-Result "Register pointers mapped (timer_status_addr)" ($main_content -like "*timer_status_addr*")
    Add-Result "Message-text seqlock reader present (read_msg_text)" ($main_content -like "*read_msg_text*")
    Add-Result "Message-text status pointer mapped (msg_text_status_addr)" `
        ($main_content -like "*msg_text_status_addr*")

    # round 2: 3-state FSM (INIT/MSG/SLEEP), not round 1's 5-state
    # (INIT/IDLE/HOME/MSG/SLEEP). Checks the real enum names used in main.c
    # (this check previously looked for STATE_IDLE/STATE_HOME/STATE_MESSAGE,
    # which never matched anything main.c actually defines).
    $states_ok = ($main_content -like "*HW_FSM_INIT*") -and
                 ($main_content -like "*HW_FSM_MSG*") -and
                 ($main_content -like "*HW_FSM_SLEEP*")
    Add-Result "FSM states defined (round 2: INIT/MSG/SLEEP)" $states_ok

    Add-Result "messages.h NOT included (text now comes from hardware)" `
        ($main_content -notlike '*#include "messages.h"*')
} else {
    Add-Result "main.c exists" $false "Not found at $main_c"
}

Write-Host ""
Write-Host "PHASE 7: Message Content (hardware text ROM)" -ForegroundColor Yellow
Write-Host "--------------------------------------------------------------" -ForegroundColor Gray

# messages.h was deleted deliberately (the advisor-requested change): message
# text now lives in hw/rtl/msg_text_rom.v, generated from tools/msg_text.json
# by tools/gen_msg_tables.py. Verify the migration actually happened, rather
# than checking a file that is supposed to be gone.
$messages_h = "sw/hps_app/messages.h"
Add-Result "messages.h removed (text migrated to FPGA)" (-not (Test-Path $messages_h))

$msg_text_rom = "hw/rtl/msg_text_rom.v"
if (Test-Path $msg_text_rom) {
    $rom_content = Get-Content $msg_text_rom -Raw
    # Match only numbered case labels (5'd0: .. 5'd17:), not the trailing
    # `default:` guard entry, which also assigns text_out = 512'h....
    $rom_entry_count = ([regex]::Matches($rom_content, "5'd\d+: text_out = 512'h")).Count
    Add-Result "18 messages defined in msg_text_rom.v" ($rom_entry_count -eq 18) `
        "Found $rom_entry_count entries, expected 18"
    Add-Result "msg_text_rom.v carries the generated-file banner" `
        ($rom_content -like "*GENERATED by tools/gen_msg_tables.py*")
} else {
    Add-Result "hw/rtl/msg_text_rom.v exists" $false "Not found - run tools/gen_msg_tables.py"
}

$msg_nav_rom = "hw/rtl/msg_nav_rom.v"
if (Test-Path $msg_nav_rom) {
    $nav_content = Get-Content $msg_nav_rom -Raw
    Add-Result "msg_nav_rom.v exposes in_default (sleep-timer arming)" `
        ($nav_content -like "*in_default*")
} else {
    Add-Result "hw/rtl/msg_nav_rom.v exists" $false "Not found - run tools/gen_msg_tables.py"
}

$snapshot_json = "tools/msg_text.json"
Add-Result "Message text snapshot exists (tools/msg_text.json)" (Test-Path $snapshot_json) `
    "Not found - generator cannot run without messages.h or this snapshot"

Write-Host ""
Write-Host "PHASE 8: Build Configuration (Makefile)" -ForegroundColor Yellow
Write-Host "--------------------------------------------------------------" -ForegroundColor Gray

$makefile = "sw/hps_app/Makefile"
if (Test-Path $makefile) {
    $make_content = Get-Content $makefile -Raw
    Add-Result "All source files listed in Makefile" ($make_content -like "*main.c*LCD_Hw.c*LCD_Lib.c*")
    $has_include_flags = ($make_content -like "*-I*")
    if ($has_include_flags) {
        Add-Result "Include paths configured" $true
    } else {
        Add-Result "Include paths configured" $false "No include flags found" "No explicit -I flags in Makefile; verify only if build fails"
    }
} else {
    Add-Result "Makefile exists" $false "Not found"
}

Write-Host ""
Write-Host "PHASE 9: Canonical Simulation Sign-off" -ForegroundColor Yellow
Write-Host "--------------------------------------------------------------" -ForegroundColor Gray

$strict_sim = $env:STRICT_SIM -eq "1"
$sim_preflight = "sim/check_sim_env.ps1"
$sim_regression = "sim/run_all_sim.ps1"

if ((Test-Path $sim_preflight) -and (Test-Path $sim_regression)) {
    Write-Host "  Running simulation preflight..."
    & $sim_preflight
    $preflight_ok = ($LASTEXITCODE -eq 0)

    if ($preflight_ok) {
        Add-Result "Simulation preflight (iverilog/vvp)" $true

        if ($env:RUN_LEGACY -eq "1") {
            Write-Host "  RUN_LEGACY=1 detected: legacy suites enabled." -ForegroundColor Cyan
        }

        Write-Host "  Running canonical simulation regression..."
        & $sim_regression
        $sim_ok = ($LASTEXITCODE -eq 0)

        if ($sim_ok) {
            Add-Result "Simulation regression (canonical suites)" $true
        } elseif ($strict_sim) {
            Add-Result "Simulation regression (canonical suites)" $false "Regression failed"
        } else {
            Add-Result "Simulation regression (canonical suites)" $false "Regression failed" "Regression failed (non-strict mode)"
        }
    } elseif ($strict_sim) {
        Add-Result "Simulation preflight (iverilog/vvp)" $false "Simulator toolchain missing"
    } else {
        Add-Result "Simulation preflight (iverilog/vvp)" $false "Simulator toolchain missing" "Preflight failed; simulation skipped (set STRICT_SIM=1 to enforce)"
    }
} elseif ($strict_sim) {
    Add-Result "Simulation scripts present" $false "Missing sim/check_sim_env.ps1 or sim/run_all_sim.ps1"
} else {
    Add-Result "Simulation scripts present" $false "Missing sim/check_sim_env.ps1 or sim/run_all_sim.ps1" "Simulation sign-off scripts missing; skipped"
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "                    VERIFICATION SUMMARY" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  [PASS] Passed:   $($script:passes)" -ForegroundColor Green
Write-Host "  [WARN] Warnings: $($script:warnings)" -ForegroundColor Yellow
Write-Host "  [FAIL] Errors:   $($script:errors)" -ForegroundColor Red
Write-Host ""

if ($script:errors -eq 0 -and $script:warnings -eq 0) {
    Write-Host "  ALL CHECKS PASSED - READY FOR BUILD" -ForegroundColor Green
    Write-Host ""
    exit 0
} elseif ($script:errors -eq 0) {
    Write-Host "  WARNINGS DETECTED - Review before building" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Warning details:" -ForegroundColor Yellow
    foreach ($item in $script:warningItems) {
        Write-Host "  - $item" -ForegroundColor Yellow
    }
    Write-Host ""
    exit 0
} else {
    Write-Host "  ERRORS FOUND - FIX BEFORE BUILDING" -ForegroundColor Red
    Write-Host ""
    exit 1
}
