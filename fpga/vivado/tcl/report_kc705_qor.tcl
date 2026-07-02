set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ../../..]]

if {[info exists ::env(VIVADO_PROJECT_XPR)]} {
    set project_xpr [file normalize $::env(VIVADO_PROJECT_XPR)]
} else {
    set project_xpr [file normalize "E:/Program/Vivado/project_1/project_1.xpr"]
}

proc repo_file {relative_path} {
    global repo_root
    return [file normalize [file join $repo_root $relative_path]]
}

set reports_dir [repo_file fpga/vivado/reports]
file mkdir $reports_dir

open_project $project_xpr

set impl_status [get_property STATUS [get_runs impl_1]]
puts "impl_1 status: $impl_status"
if {![string match "*Complete*" $impl_status]} {
    error "impl_1 is not complete; cannot report QoR from current implementation."
}

open_run impl_1

report_timing -max_paths 25 -sort_by group -file [file join $reports_dir impl_timing_paths_25.rpt]
report_design_analysis -timing -logic_level_distribution -file [file join $reports_dir impl_design_analysis_timing.rpt]
report_qor_suggestions -file [file join $reports_dir impl_qor_suggestions.rpt]
report_high_fanout_nets -max_nets 50 -file [file join $reports_dir impl_high_fanout_nets.rpt]

puts "Wrote QoR reports to $reports_dir"
