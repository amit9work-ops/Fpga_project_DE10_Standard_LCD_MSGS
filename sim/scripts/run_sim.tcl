# =============================================================================
# run_sim.tcl — Questa/ModelSim canonical simulation runner
# Project: DE10-Standard LCD Message System
#
# Usage:
#   vsim -c -do sim/scripts/run_sim.tcl
#
# Optional:
#   set env(RUN_LEGACY) 1
# =============================================================================

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set ROOT       [file normalize [file join $SCRIPT_DIR .. ..]]
set RTL        "$ROOT/hw/rtl"
set TBH        "$ROOT/hw/sim/testbenches"
set TBS        "$ROOT/sim/testbenches_legacy"
set RESULTS    "$ROOT/sim/results"

file mkdir $RESULTS
cd $RESULTS

set pass_count 0
set fail_count 0

proc run_tb {name tb_file source_files} {
    global pass_count
    global fail_count

    puts ""
    puts "=================================================================="
    puts "  $name"
    puts "=================================================================="

    if {![file exists $tb_file]} {
        puts "  [FAIL] Missing testbench: $tb_file"
        incr fail_count
        return
    }

    foreach f $source_files {
        if {![file exists $f]} {
            puts "  [FAIL] Missing source: $f"
            incr fail_count
            return
        }
    }

    if {[file exists work]} {
        catch {vdel -all -lib work}
    }
    vlib work
    vmap work work

    foreach f $source_files {
        if {[catch {vlog -quiet -sv $f} err]} {
            puts "  [FAIL] Compile error in $f"
            puts "  $err"
            incr fail_count
            return
        }
    }

    if {[catch {vlog -quiet -sv $tb_file} err]} {
        puts "  [FAIL] Compile error in $tb_file"
        puts "  $err"
        incr fail_count
        return
    }

    set module [file rootname [file tail $tb_file]]

    if {[catch {vsim -quiet -lib work $module} err]} {
        puts "  [FAIL] Could not elaborate module $module"
        puts "  $err"
        incr fail_count
        return
    }

    if {[catch {run -all} err]} {
        puts "  [FAIL] Runtime error in $module"
        puts "  $err"
        incr fail_count
        catch {quit -sim}
        return
    }

    catch {quit -sim}
    puts "  [RESULT] COMPLETED"
    incr pass_count
}

puts ""
puts "###########################################################"
puts "#   PHASE 1: UNIT TESTS (hw/sim/testbenches/)            #"
puts "###########################################################"

run_tb "tb_button_debouncer_unit" \
    "$TBH/tb_button_debouncer.v" \
    [list "$RTL/button_debouncer.v"]

run_tb "tb_button_edge_detector" \
    "$TBH/tb_button_edge_detector.v" \
    [list "$RTL/button_edge_detector.v"]

run_tb "tb_idle_timer" \
    "$TBH/tb_idle_timer.v" \
    [list "$RTL/idle_timer.v"]

run_tb "tb_hex_display" \
    "$TBH/tb_hex_display.v" \
    [list "$RTL/hex_display.v"]

run_tb "tb_message_fsm" \
    "$TBH/tb_message_fsm.v" \
    [list "$RTL/message_fsm.v"]

puts ""
puts "###########################################################"
puts "#   PHASE 2: INTEGRATION TESTS                           #"
puts "###########################################################"

run_tb "tb_fpga_msg_controller" \
    "$TBH/tb_fpga_msg_controller.v" \
    [list \
        "$RTL/fpga_msg_controller.v" \
        "$RTL/message_fsm.v" \
        "$RTL/button_debouncer.v" \
        "$RTL/button_edge_detector.v" \
        "$RTL/idle_timer.v" \
        "$RTL/hex_display.v"]

run_tb "tb_soc_register_contract" \
    "$TBH/tb_soc_register_contract.v" \
    [list]

run_tb "tb_top_level" \
    "$TBS/tb_top_level.v" \
    [list \
        "$RTL/top_level.v" \
        "$RTL/fpga_msg_controller.v" \
        "$RTL/message_fsm.v" \
        "$RTL/button_debouncer.v" \
        "$RTL/button_edge_detector.v" \
        "$RTL/idle_timer.v" \
        "$RTL/hex_display.v"]

if {[info exists ::env(RUN_LEGACY)] && $::env(RUN_LEGACY) eq "1"} {
    puts ""
    puts "###########################################################"
    puts "#   PHASE 3: LEGACY TESTS (sim/testbenches_legacy/)      #"
    puts "###########################################################"

    run_tb "tb_button_debouncer_legacy" \
        "$TBS/tb_button_debouncer.v" \
        [list "$RTL/button_debouncer.v"]

    run_tb "tb_clock_divider" \
        "$TBS/tb_clock_divider.v" \
        [list "$RTL/clock_divider.v"]
} else {
    puts ""
    puts "[INFO] Legacy tests skipped. Set RUN_LEGACY=1 to include them."
}

set total_count [expr {$pass_count + $fail_count}]

puts ""
puts "=================================================================="
puts "  QUESTA SIMULATION SUMMARY"
puts "=================================================================="
puts "  Total Suites : $total_count"
puts "  Completed    : $pass_count"
puts "  Failed       : $fail_count"

if {$fail_count > 0} {
    puts "  *** SOME SUITES FAILED (compile/elaboration/runtime) ***"
    quit -code 1 -f
} else {
    puts "  *** ALL QUESTA SUITES COMPLETED ***"
    quit -code 0 -f
}
