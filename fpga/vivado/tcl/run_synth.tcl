source [file join [file dirname [file normalize [info script]]] setup_project.tcl]

if {[info exists ::env(VIVADO_JOBS)]} {
    set jobs $::env(VIVADO_JOBS)
} else {
    set jobs 4
}

set reports_dir [repo_file fpga/vivado/reports]
file mkdir $reports_dir

proc report_path {name} {
    global reports_dir
    set path [file join $reports_dir $name]
    if {[file exists $path]} {
        file delete -force $path
    }
    return $path
}

reset_run synth_1
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "synth_1 status: $synth_status"
if {![string match "*Complete*" $synth_status]} {
    error "Synthesis did not complete successfully."
}

open_run synth_1
report_utilization -file [report_path synth_utilization.rpt]
report_timing_summary -file [report_path synth_timing_summary.rpt]
report_drc -file [report_path synth_drc.rpt]

puts "Synthesis reports written to $reports_dir"
