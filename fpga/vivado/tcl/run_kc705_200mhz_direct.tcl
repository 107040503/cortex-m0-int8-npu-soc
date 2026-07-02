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

set experiment_name kc705_200mhz_direct
if {[info exists ::env(FPGA_EXPERIMENT_NAME)]} {
    set experiment_name $::env(FPGA_EXPERIMENT_NAME)
}

set synth_directive PerformanceOptimized
if {[info exists ::env(FPGA_SYNTH_DIRECTIVE)]} {
    set synth_directive $::env(FPGA_SYNTH_DIRECTIVE)
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
set post_route_phys_opt_directive AggressiveExplore
if {[info exists ::env(FPGA_POST_ROUTE_PHYS_OPT_DIRECTIVE)]} {
    set post_route_phys_opt_directive $::env(FPGA_POST_ROUTE_PHYS_OPT_DIRECTIVE)
}
set stop_after ""
if {[info exists ::env(FPGA_STOP_AFTER)]} {
    set stop_after $::env(FPGA_STOP_AFTER)
}

set experiments_dir [repo_file fpga/vivado/experiments]
set project_dir [file join $experiments_dir $experiment_name]
set reports_dir [file join $project_dir reports]
set bitstreams_dir [repo_file fpga/vivado/bitstreams]
file mkdir $experiments_dir
file mkdir $project_dir
file mkdir $reports_dir
file mkdir $bitstreams_dir

create_project -force $experiment_name $project_dir -part xc7k325tffg900-2
set_property board_part xilinx.com:kc705:part0:1.6 [current_project]
set_property verilog_define [list FPGA_USE_AXI_BRAM FPGA_SYNTH_BRAM KC705_ENABLE_ILA CORTEXM0DS_NO_DSP_MULT] [current_fileset]

set src_files [concat \
    [list [repo_file fpga/rtl/fpga_kc705_top.v]] \
    [list [repo_file rtl/axi_bram.v]] \
    [read_filelist [repo_file rtl/filelist_cortexm0.f]] \
]
foreach f $src_files {
    if {![file exists $f]} {
        error "Required source file is missing: $f"
    }
}
read_verilog -sv $src_files

set mem_file [repo_file fpga/vivado/mem/cortex_m0_npu_demo.mem]
add_files -norecurse -fileset sources_1 $mem_file
set_property file_type {Memory Initialization Files} [get_files $mem_file]

set xdc_file [repo_file fpga/vivado/constraints/kc705_cpu_npu.xdc]
read_xdc $xdc_file

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
generate_target synthesis [get_ips ila_cpu_npu_kc705]
set ila_xci [get_files -quiet *ila_cpu_npu_kc705.xci]
if {[llength $ila_xci] > 0} {
    set_property generate_synth_checkpoint false $ila_xci
}
set_property generic "SRAM_INIT_FILE=$mem_file FPGA_START_DELAY_CYCLES=32'hEE6B2800" [current_fileset]

synth_design -top fpga_kc705_top -part xc7k325tffg900-2 -retiming -directive $synth_directive
report_utilization -file [report_path synth_utilization.rpt]
report_timing_summary -file [report_path synth_timing_summary.rpt]
report_drc -file [report_path synth_drc.rpt]
if {$stop_after eq "synth"} {
    write_checkpoint -force [file join $project_dir "${experiment_name}_synth.dcp"]
    puts "Direct-flow stopped after synth by FPGA_STOP_AFTER."
    close_project
    return
}

if {$opt_directive ne ""} {
    opt_design -directive $opt_directive
} else {
    opt_design
}
if {$stop_after eq "opt"} {
    write_checkpoint -force [file join $project_dir "${experiment_name}_opt.dcp"]
    puts "Direct-flow stopped after opt by FPGA_STOP_AFTER."
    close_project
    return
}
if {$place_directive ne ""} {
    if {[llength [get_debug_cores -quiet]] > 0} {
        implement_debug_core
    }
    if {$stop_after eq "implement_debug_core"} {
        write_checkpoint -force [file join $project_dir "${experiment_name}_debug.dcp"]
        puts "Direct-flow stopped after implement_debug_core by FPGA_STOP_AFTER."
        close_project
        return
    }
    place_design -directive $place_directive
} else {
    if {[llength [get_debug_cores -quiet]] > 0} {
        implement_debug_core
    }
    if {$stop_after eq "implement_debug_core"} {
        write_checkpoint -force [file join $project_dir "${experiment_name}_debug.dcp"]
        puts "Direct-flow stopped after implement_debug_core by FPGA_STOP_AFTER."
        close_project
        return
    }
    place_design
}
phys_opt_design -directive $phys_opt_directive
if {$route_directive ne ""} {
    route_design -directive $route_directive
} else {
    route_design
}
phys_opt_design -directive $post_route_phys_opt_directive
write_debug_probes -force [file join $bitstreams_dir "${experiment_name}.ltx"]
write_bitstream -force [file join $bitstreams_dir "${experiment_name}.bit"]

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
puts "Direct-flow reports written to $reports_dir"
close_project
