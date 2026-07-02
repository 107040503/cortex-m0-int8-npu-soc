set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ../../..]]

proc repo_file {relative_path} {
    global repo_root
    return [file normalize [file join $repo_root $relative_path]]
}

proc report_path {name} {
    global reports_dir
    set path [file join $reports_dir $name]
    if {[file exists $path]} {
        file delete -force $path
    }
    return $path
}

set experiment_name kc705_impl_from_dcp
if {[info exists ::env(FPGA_EXPERIMENT_NAME)]} {
    set experiment_name $::env(FPGA_EXPERIMENT_NAME)
}

set synth_dcp [repo_file fpga/vivado/experiments/k7e1/k7e1.runs/synth_1/fpga_kc705_top.dcp]
if {[info exists ::env(FPGA_SYNTH_DCP)]} {
    set synth_dcp [file normalize $::env(FPGA_SYNTH_DCP)]
}
if {![file exists $synth_dcp]} {
    error "Synthesis checkpoint not found: $synth_dcp"
}
set ila_dcp [repo_file fpga/vivado/experiments/k7e1/k7e1.runs/ila_cpu_npu_kc705_synth_1/ila_cpu_npu_kc705.dcp]
if {[info exists ::env(FPGA_ILA_DCP)]} {
    set ila_dcp [file normalize $::env(FPGA_ILA_DCP)]
}
if {![file exists $ila_dcp]} {
    error "ILA checkpoint not found: $ila_dcp"
}

set opt_directive ""
if {[info exists ::env(FPGA_OPT_DIRECTIVE)]} {
    set opt_directive $::env(FPGA_OPT_DIRECTIVE)
}
set place_directive ""
if {[info exists ::env(FPGA_PLACE_DIRECTIVE)]} {
    set place_directive $::env(FPGA_PLACE_DIRECTIVE)
}
set phys_opt_directive AggressiveExplore
if {[info exists ::env(FPGA_PHYS_OPT_DIRECTIVE)]} {
    set phys_opt_directive $::env(FPGA_PHYS_OPT_DIRECTIVE)
}
set route_directive ""
if {[info exists ::env(FPGA_ROUTE_DIRECTIVE)]} {
    set route_directive $::env(FPGA_ROUTE_DIRECTIVE)
}
set post_route_phys_opt_directive AddRetime
if {[info exists ::env(FPGA_POST_ROUTE_PHYS_OPT_DIRECTIVE)]} {
    set post_route_phys_opt_directive $::env(FPGA_POST_ROUTE_PHYS_OPT_DIRECTIVE)
}

set experiments_dir [repo_file fpga/vivado/experiments]
set project_dir [file join $experiments_dir $experiment_name]
set reports_dir [file join $project_dir reports]
set bitstreams_dir [repo_file fpga/vivado/bitstreams]
file mkdir $experiments_dir
file mkdir $project_dir
file mkdir $reports_dir
file mkdir $bitstreams_dir

open_checkpoint $synth_dcp
read_checkpoint -cell u_ila_cpu_npu $ila_dcp
set_property webtalk.parent_dir [file join $project_dir wt] [current_project]
set_property parent.project_path [file join $project_dir ${experiment_name}.xpr] [current_project]
set_property ip_output_repo [file join $project_dir ip_cache] [current_project]
set_property ip_cache_permissions {read write} [current_project]
set_property XPM_LIBRARIES {XPM_CDC XPM_MEMORY} [current_project]

if {$opt_directive ne ""} {
    opt_design -directive $opt_directive
} else {
    opt_design
}
write_checkpoint -force [file join $project_dir fpga_kc705_top_opt.dcp]
report_drc -file [report_path opt_drc.rpt]

if {[llength [get_debug_cores -quiet]] > 0} {
    implement_debug_core
}

if {$place_directive ne ""} {
    place_design -directive $place_directive
} else {
    place_design
}
write_checkpoint -force [file join $project_dir fpga_kc705_top_placed.dcp]
report_utilization -file [report_path placed_utilization.rpt]

phys_opt_design -directive $phys_opt_directive
write_checkpoint -force [file join $project_dir fpga_kc705_top_physopt.dcp]

if {$route_directive ne ""} {
    route_design -directive $route_directive
} else {
    route_design
}
write_checkpoint -force [file join $project_dir fpga_kc705_top_routed.dcp]

phys_opt_design -directive $post_route_phys_opt_directive
write_checkpoint -force [file join $project_dir fpga_kc705_top_postroute_physopt.dcp]

write_bitstream -force [file join $bitstreams_dir "${experiment_name}.bit"]
catch {write_debug_probes -quiet -force [file join $bitstreams_dir "${experiment_name}.ltx"]}

report_timing_summary -file [report_path impl_timing_summary.rpt]
report_timing -max_paths 25 -sort_by group -file [report_path impl_timing_paths_25.rpt]
report_utilization -file [report_path impl_utilization.rpt]
report_power -file [report_path impl_power.rpt]
report_drc -file [report_path impl_drc.rpt]
report_methodology -file [report_path impl_methodology.rpt]

set timing_violations [get_timing_paths -quiet -slack_lesser_than 0 -max_paths 1]
if {[llength $timing_violations] > 0} {
    puts "WARNING: timing violations are present. Check [file join $reports_dir impl_timing_summary.rpt]."
} else {
    puts "Timing met for $experiment_name."
}
puts "Implementation-from-DCP reports written to $reports_dir"
close_project
