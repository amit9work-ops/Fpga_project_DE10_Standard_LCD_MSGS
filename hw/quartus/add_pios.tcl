package require -exact qsys 14.0

# ============================================================================
# add_pios.tcl - add/maintain the custom Avalon PIO slaves for the LCD message
# system on the Lightweight HPS-to-FPGA bridge (mm_bridge_0.m0).
#
# IMPORTANT history: earlier versions requested baseAddress 0x6000/0x7000 for
# the status PIOs, but mm_bridge_0 only had a 10-bit (1 KB) address span, so
# Qsys silently relocated them to 0x0110/0x0100. That mismatch is why the docs
# and main.c disagreed. This version pins the bridge address width and assigns
# explicit, in-range addresses, and the authoritative map is regenerated from
# the .sopcinfo by gen_addr_map.ps1 into sw/hps_app/soc_addr_map.h - software
# never hand-types an address again.
# ============================================================================

load_system soc_system.qsys

# ---------------------------------------------------------
# Pin the LW bridge address space so adding slaves cannot silently renumber
# the existing ones. Verified against the full mm_bridge_0.m0 slave list in
# soc_system.qsys (not just the small PIOs): jtag_uart.avalon_jtag_slave
# sits at 0x00020000, far above the 0x0000-0x0510 range everything else
# uses. 18 bits = 256 KB (0x00000-0x3FFFF) comfortably covers jtag_uart's
# 0x20000-0x20007 plus the existing PIOs (0x0100-0x0150) and the
# message-text window (0x0400-0x0500), with headroom to spare. (An earlier
# version of this script pinned 12 bits/4 KB, which fit the PIOs but was
# too small to reach jtag_uart and made qsys-generate fail outright:
# "jtag_uart.avalon_jtag_slave (0x20000..0x20007) is outside the master's
# address range (0x0..0xfff)".)
# ---------------------------------------------------------
set_instance_parameter_value mm_bridge_0 USE_AUTO_ADDRESS_WIDTH 0
set_instance_parameter_value mm_bridge_0 ADDRESS_WIDTH 18

# ---------------------------------------------------------
# Helper: create an Input PIO if absent, connect clk/reset/s1, set its base
# address, and export its conduit as <name>_external_connection.
# ---------------------------------------------------------
proc ensure_input_pio {name width base} {
    if {[lsearch [get_instances] $name] == -1} {
        send_message info "Adding $name (width $width @ $base)..."
        add_instance $name altera_avalon_pio
        set_instance_parameter_value $name width $width
        set_instance_parameter_value $name direction Input
        add_connection clk_0.clk $name.clk
        add_connection clk_0.clk_reset $name.reset
        add_connection mm_bridge_0.m0 $name.s1
        add_interface ${name}_external_connection conduit end
        set_interface_property ${name}_external_connection EXPORT_OF $name.external_connection
    } else {
        send_message info "$name already exists."
    }
    # Set the address every run (idempotent) so the map stays locked.
    set_connection_parameter_value mm_bridge_0.m0/$name.s1 baseAddress $base
}

# ---------------------------------------------------------
# Existing status PIOs - real addresses (were 0x6000/0x7000 in the old script).
# ---------------------------------------------------------
ensure_input_pio timer_status_pio 8 0x0100
ensure_input_pio fsm_status_pio   8 0x0110

# ---------------------------------------------------------
# Message-text wide interface: 16 x 32-bit read-only words (64 bytes of text,
# byte B=line*16+col carried in word B/4) plus an 8-bit status = {seq[2:0],
# text_index[4:0]} for the HPS seqlock. Each PIO spans 0x10 bytes.
# ---------------------------------------------------------
for {set i 0} {$i < 16} {incr i} {
    set base [expr {0x0400 + $i * 0x10}]
    ensure_input_pio msg_text_pio_$i 32 [format 0x%04X $base]
}
ensure_input_pio msg_text_status_pio 8 0x0500

save_system soc_system.qsys
