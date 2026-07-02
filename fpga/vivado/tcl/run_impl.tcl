source [file join [file dirname [file normalize [info script]]] setup_project.tcl]

if {[info exists ::env(VIVADO_JOBS)]} {
    set jobs $::env(VIVADO_JOBS)
} else {
    set jobs 4
}

set reports_dir [repo_file fpga/vivado/reports]
set bitstreams_dir [repo_file fpga/vivado/bitstreams]
file mkdir $reports_dir
file mkdir $bitstreams_dir

proc report_path {name} {
    global reports_dir
    set path [file join $reports_dir $name]
    if {[file exists $path]} {
        file delete -force $path
    }
    return $path
}

set synth_status [get_property STATUS [get_runs synth_1]]
set synth_needs_refresh [get_property NEEDS_REFRESH [get_runs synth_1]]
if {![string match "*Complete*" $synth_status] || $synth_needs_refresh} {
    if {$synth_needs_refresh} {
        reset_run synth_1
    }
    launch_runs synth_1 -jobs $jobs
    wait_on_run synth_1
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "impl_1 status: $impl_status"
if {![string match "*Complete*" $impl_status]} {
    error "Implementation did not complete successfully."
}

open_run impl_1
report_timing_summary -file [report_path impl_timing_summary.rpt]
report_utilization -file [report_path impl_utilization.rpt]
report_power -file [report_path impl_power.rpt]
report_drc -file [report_path impl_drc.rpt]
report_methodology -file [report_path impl_methodology.rpt]

set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set bit_files [glob -nocomplain -directory $impl_dir *.bit]
set ltx_files [glob -nocomplain -directory $impl_dir *.ltx]
if {[llength $bit_files] == 0} {
    error "No bitstream found in $impl_dir"
}

if {[info exists ::env(FPGA_BITSTREAM_NAME)]} {
    set output_base $::env(FPGA_BITSTREAM_NAME)
} elseif {[info exists fpga_bitstream_name]} {
    set output_base $fpga_bitstream_name
} else {
    set output_base kc705_cpu_npu
}

file copy -force [lindex $bit_files 0] [file join $bitstreams_dir "${output_base}.bit"]
if {[llength $ltx_files] > 0} {
    file copy -force [lindex $ltx_files 0] [file join $bitstreams_dir "${output_base}.ltx"]
}

set timing_violations [get_timing_paths -quiet -slack_lesser_than 0 -max_paths 1]
if {[llength $timing_violations] > 0} {
    puts "WARNING: timing violations are present. Check impl_timing_summary.rpt."
}

puts "Bitstream copied to [file join $bitstreams_dir "${output_base}.bit"]"
