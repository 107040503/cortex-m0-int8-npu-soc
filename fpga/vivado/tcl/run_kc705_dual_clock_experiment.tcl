set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ../../..]]

proc repo_file {relative_path} {
    global repo_root
    return [file normalize [file join $repo_root $relative_path]]
}

proc read_filelist {filelist_path} {
    set files {}
    set fh [open $filelist_path r]
    while {[gets $fh line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string match "#*" $line]} {
            continue
        }
        lappend files [repo_file $line]
    }
    close $fh
    return $files
}

proc report_path {name} {
    global reports_dir
    set path [file join $reports_dir $name]
    if {[file exists $path]} {
        file delete -force $path
    }
    return $path
}

set experiment_name kc705_200mhz_dual_clock
if {[info exists ::env(FPGA_EXPERIMENT_NAME)]} {
    set experiment_name $::env(FPGA_EXPERIMENT_NAME)
}

set jobs 4
if {[info exists ::env(VIVADO_JOBS)]} {
    set jobs $::env(VIVADO_JOBS)
}

set experiments_dir [repo_file fpga/vivado/experiments]
set project_dir [file join $experiments_dir $experiment_name]
set reports_dir [file join $project_dir reports]
set bitstreams_dir [repo_file fpga/vivado/bitstreams]
file mkdir $experiments_dir
file mkdir $reports_dir
file mkdir $bitstreams_dir

create_project -force $experiment_name $project_dir -part xc7k325tffg900-2
set_property board_part xilinx.com:kc705:part0:1.6 [current_project]

set src_files [concat \
    [list [repo_file fpga/rtl/fpga_kc705_dual_clock_top.v]] \
    [read_filelist [repo_file rtl/filelist_cortexm0_dual_clock.f]] \
]
foreach f $src_files {
    if {![file exists $f]} {
        error "Required source file is missing: $f"
    }
}
add_files -norecurse -fileset sources_1 $src_files

set mem_file [repo_file fpga/vivado/mem/cortex_m0_npu_demo.mem]
add_files -norecurse -fileset sources_1 $mem_file
set_property file_type {Memory Initialization Files} [get_files $mem_file]

set xdc_file [repo_file fpga/vivado/constraints/kc705_cpu_npu.xdc]
add_files -norecurse -fileset constrs_1 [list $xdc_file]

create_ip -name ila -vendor xilinx.com -library ip -module_name ila_cpu_npu_kc705
set_property -dict [list \
    CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_NUM_OF_PROBES {12} \
    CONFIG.C_PROBE0_WIDTH {1} \
    CONFIG.C_PROBE1_WIDTH {1} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {32} \
    CONFIG.C_PROBE6_WIDTH {32} \
    CONFIG.C_PROBE7_WIDTH {32} \
    CONFIG.C_PROBE8_WIDTH {32} \
    CONFIG.C_PROBE9_WIDTH {32} \
    CONFIG.C_PROBE10_WIDTH {32} \
    CONFIG.C_PROBE11_WIDTH {32} \
] [get_ips ila_cpu_npu_kc705]
generate_target all [get_ips ila_cpu_npu_kc705]

set verilog_defines [list FPGA_USE_AXI_BRAM FPGA_SYNTH_BRAM KC705_ENABLE_ILA CORTEXM0DS_NO_DSP_MULT]
set_property verilog_define $verilog_defines [get_filesets sources_1]
set_property top fpga_kc705_dual_clock_top [get_filesets sources_1]
set_property generic "SRAM_INIT_FILE=$mem_file FPGA_START_DELAY_CYCLES=32'hEE6B2800" [get_filesets sources_1]

set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE PerformanceOptimized [get_runs synth_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]

update_compile_order -fileset sources_1

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
report_timing -max_paths 25 -sort_by group -file [report_path impl_timing_paths_25.rpt]
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
file copy -force [lindex $bit_files 0] [file join $bitstreams_dir "${experiment_name}.bit"]
if {[llength $ltx_files] > 0} {
    file copy -force [lindex $ltx_files 0] [file join $bitstreams_dir "${experiment_name}.ltx"]
}

set timing_violations [get_timing_paths -quiet -slack_lesser_than 0 -max_paths 1]
if {[llength $timing_violations] > 0} {
    puts "WARNING: timing violations are present. Check [file join $reports_dir impl_timing_summary.rpt]."
} else {
    puts "Timing met for $experiment_name."
}
puts "Experiment reports written to $reports_dir"
close_project
exit
