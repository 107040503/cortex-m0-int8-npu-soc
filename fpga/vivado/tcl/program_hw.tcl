set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ../../..]]

if {[info exists ::env(BIT_FILE)]} {
    set bit_file [file normalize $::env(BIT_FILE)]
} else {
    if {[info exists ::env(FPGA_BITSTREAM_NAME)]} {
        set bitstream_name $::env(FPGA_BITSTREAM_NAME)
    } else {
        set bitstream_name kc705_cpu_npu
    }
    set bit_file [file normalize [file join $repo_root fpga/vivado/bitstreams "${bitstream_name}.bit"]]
}

if {[info exists ::env(LTX_FILE)]} {
    set ltx_file [file normalize $::env(LTX_FILE)]
} else {
    if {![info exists bitstream_name]} {
        if {[info exists ::env(FPGA_BITSTREAM_NAME)]} {
            set bitstream_name $::env(FPGA_BITSTREAM_NAME)
        } else {
            set bitstream_name kc705_cpu_npu
        }
    }
    set ltx_file [file normalize [file join $repo_root fpga/vivado/bitstreams "${bitstream_name}.ltx"]]
}

if {![file exists $bit_file]} {
    error "Bitstream not found: $bit_file"
}

open_hw_manager
connect_hw_server -allow_non_jtag

set hw_targets [get_hw_targets -quiet *]
if {[llength $hw_targets] == 0} {
    error "No hardware targets found. Check board power, USB-JTAG cable, and drivers."
}
current_hw_target [lindex $hw_targets 0]
open_hw_target

set hw_devices [get_hw_devices]
if {[llength $hw_devices] == 0} {
    error "No hardware devices found. Check board power, USB-JTAG cable, and drivers."
}

set selected_hw_device [lindex $hw_devices 0]
if {[info exists ::env(FPGA_EXPECTED_DEVICE)]} {
    set expected_device [string tolower $::env(FPGA_EXPECTED_DEVICE)]
    set selected_hw_device ""
    foreach hw_device $hw_devices {
        set hw_part [string tolower [get_property PART $hw_device]]
        if {[string match "*$expected_device*" $hw_part]} {
            set selected_hw_device $hw_device
            break
        }
    }
    if {$selected_hw_device eq ""} {
        error "Expected hardware device matching '$expected_device', found: $hw_devices"
    }
}

current_hw_device $selected_hw_device
refresh_hw_device [current_hw_device]
set_property PROGRAM.FILE $bit_file [current_hw_device]
if {[file exists $ltx_file]} {
    set_property PROBES.FILE $ltx_file [current_hw_device]
}
program_hw_devices [current_hw_device]
refresh_hw_device [current_hw_device]

puts "Programmed [get_property PART [current_hw_device]] with $bit_file"
