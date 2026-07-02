set script_dir [file dirname [file normalize [info script]]]
set ::env(FPGA_STOP_AFTER) implement_debug_core
source [file join $script_dir run_kc705_200mhz_direct.tcl]
