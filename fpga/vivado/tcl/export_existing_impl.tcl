set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ../../..]]

if {[info exists ::env(VIVADO_PROJECT_XPR)]} {
    set project_xpr [file normalize $::env(VIVADO_PROJECT_XPR)]
} else {
    set project_xpr [file normalize "E:/Program/Vivado/project_1/project_1.xpr"]
}

if {[info exists ::env(FPGA_BITSTREAM_NAME)]} {
    set output_base $::env(FPGA_BITSTREAM_NAME)
} else {
    set output_base kc705_cpu_npu
}

proc repo_file {relative_path} {
    global repo_root
    return [file normalize [file join $repo_root $relative_path]]
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

open_project $project_xpr

set impl_status [get_property STATUS [get_runs impl_1]]
puts "impl_1 status: $impl_status"
if {![string match "*Complete*" $impl_status]} {
    error "impl_1 is not complete; refusing to export stale implementation reports."
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

file copy -force [lindex $bit_files 0] [file join $bitstreams_dir "${output_base}.bit"]
if {[llength $ltx_files] > 0} {
    file copy -force [lindex $ltx_files 0] [file join $bitstreams_dir "${output_base}.ltx"]
}

set timing_violations [get_timing_paths -quiet -slack_lesser_than 0 -max_paths 1]
if {[llength $timing_violations] > 0} {
    puts "WARNING: timing violations are present. Check impl_timing_summary.rpt."
} else {
    puts "Timing clean: no negative-slack paths reported."
}

puts "Exported implementation reports to $reports_dir"
puts "Bitstream copied to [file join $bitstreams_dir "${output_base}.bit"]"
