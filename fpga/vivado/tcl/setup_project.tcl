set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ../../..]]

if {[info exists ::env(VIVADO_PROJECT_XPR)]} {
    set project_xpr [file normalize $::env(VIVADO_PROJECT_XPR)]
} else {
    set project_xpr [file normalize "E:/Program/Vivado/project_1/project_1.xpr"]
}

if {![file exists $project_xpr]} {
    error "Vivado project not found: $project_xpr"
}

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

proc add_or_update_files {files fileset} {
    foreach f $files {
        if {![file exists $f]} {
            error "Required source file is missing: $f"
        }
        if {[llength [get_files -quiet $f]] == 0} {
            add_files -norecurse -fileset $fileset $f
        }
    }
}

open_project $project_xpr

set fpga_part xc7k325tffg900-2
set fpga_board_part xilinx.com:kc705:part0:1.6
set fpga_xdc_rel fpga/vivado/constraints/kc705_cpu_npu.xdc
set fpga_bitstream_name kc705_cpu_npu
set fpga_board_label KC705
set fpga_ila_module ila_cpu_npu_kc705
set fpga_ila_define KC705_ENABLE_ILA
set fpga_ila_probe_count 12
set fpga_start_delay_cycles 32'hEE6B2800
set fpga_mem_rel fpga/vivado/mem/cortex_m0_npu_demo.mem

if {[info exists ::env(FPGA_PART)]} {
    set fpga_part $::env(FPGA_PART)
}
if {[info exists ::env(FPGA_BOARD_PART)]} {
    set fpga_board_part $::env(FPGA_BOARD_PART)
}
if {[info exists ::env(FPGA_XDC)]} {
    set fpga_xdc_rel $::env(FPGA_XDC)
}
if {[info exists ::env(FPGA_BITSTREAM_NAME)]} {
    set fpga_bitstream_name $::env(FPGA_BITSTREAM_NAME)
}
if {[info exists ::env(FPGA_START_DELAY_CYCLES)]} {
    set fpga_start_delay_cycles $::env(FPGA_START_DELAY_CYCLES)
}

set_property part $fpga_part [current_project]
set_property board_part $fpga_board_part [current_project]

set stale_files [concat \
    [get_files -quiet [repo_file fpga/rtl/fpga_vc707_top.v]] \
    [get_files -quiet [repo_file fpga/vivado/constraints/vc707_cpu_npu.xdc]] \
    [get_files -quiet */ila_cpu_npu/ila_cpu_npu.xci] \
]
if {[llength $stale_files] > 0} {
    remove_files $stale_files
}

set src_files [concat \
    [list [repo_file fpga/rtl/fpga_kc705_top.v]] \
    [list [repo_file rtl/axi_bram.v]] \
    [read_filelist [repo_file rtl/filelist_cortexm0.f]] \
]
add_or_update_files $src_files sources_1

set known_xdc_files [list \
    [repo_file fpga/vivado/constraints/kc705_cpu_npu.xdc] \
    [repo_file fpga/vivado/constraints/kc705_cpu_npu_timing.xdc] \
]
foreach known_xdc $known_xdc_files {
    if {[llength [get_files -quiet $known_xdc]] != 0} {
        set_property used_in_synthesis false [get_files $known_xdc]
        set_property used_in_implementation false [get_files $known_xdc]
    }
}

set xdc_file [repo_file $fpga_xdc_rel]
add_or_update_files [list $xdc_file] constrs_1
set_property used_in_synthesis true [get_files $xdc_file]
set_property used_in_implementation true [get_files $xdc_file]

set timing_xdc_file [repo_file fpga/vivado/constraints/kc705_cpu_npu_timing.xdc]
add_or_update_files [list $timing_xdc_file] constrs_1
set_property used_in_synthesis false [get_files $timing_xdc_file]
set_property used_in_implementation true [get_files $timing_xdc_file]

set mem_file [repo_file $fpga_mem_rel]
if {[llength [get_files -quiet $mem_file]] == 0} {
    add_files -norecurse -fileset sources_1 $mem_file
}
set_property file_type {Memory Initialization Files} [get_files $mem_file]

set_property top fpga_kc705_top [get_filesets sources_1]
set_property generic "SRAM_INIT_FILE=$mem_file FPGA_START_DELAY_CYCLES=$fpga_start_delay_cycles" [get_filesets sources_1]

set ila_enabled 1
if {[info exists ::env(FPGA_ENABLE_ILA)] && $::env(FPGA_ENABLE_ILA) eq "0"} {
    set ila_enabled 0
}

set fpga_verilog_defines [list FPGA_USE_AXI_BRAM FPGA_SYNTH_BRAM]
if {[info exists ::env(FPGA_CORTEXM0_NO_DSP_MULT)] && $::env(FPGA_CORTEXM0_NO_DSP_MULT) eq "1"} {
    lappend fpga_verilog_defines CORTEXM0DS_NO_DSP_MULT
}

if {$ila_enabled} {
    set_property verilog_define [concat $fpga_verilog_defines [list $fpga_ila_define]] [get_filesets sources_1]
    if {[llength [get_ips -quiet $fpga_ila_module]] == 0} {
        set existing_ila_xci [glob -nocomplain [file join [file dirname $project_xpr] *.srcs sources_1 ip $fpga_ila_module "${fpga_ila_module}.xci"]]
        if {[llength $existing_ila_xci] > 0} {
            add_files -norecurse -fileset sources_1 [lindex $existing_ila_xci 0]
        } else {
            create_ip -name ila -vendor xilinx.com -library ip -module_name $fpga_ila_module
        }
    }
    set ila_config [list \
        CONFIG.C_DATA_DEPTH {1024} \
        CONFIG.C_NUM_OF_PROBES $fpga_ila_probe_count \
        CONFIG.C_PROBE0_WIDTH {1} \
        CONFIG.C_PROBE1_WIDTH {1} \
        CONFIG.C_PROBE2_WIDTH {1} \
        CONFIG.C_PROBE3_WIDTH {1} \
        CONFIG.C_PROBE4_WIDTH {1} \
        CONFIG.C_PROBE5_WIDTH {32} \
        CONFIG.C_PROBE6_WIDTH {32} \
        CONFIG.C_PROBE7_WIDTH {32} \
    ]
    if {$fpga_ila_probe_count >= 12} {
        lappend ila_config CONFIG.C_PROBE8_WIDTH {32}
        lappend ila_config CONFIG.C_PROBE9_WIDTH {32}
        lappend ila_config CONFIG.C_PROBE10_WIDTH {32}
        lappend ila_config CONFIG.C_PROBE11_WIDTH {32}
    }
    set_property -dict $ila_config [get_ips $fpga_ila_module]
    generate_target all [get_ips $fpga_ila_module]
} else {
    set_property verilog_define $fpga_verilog_defines [get_filesets sources_1]
}

update_compile_order -fileset sources_1

if {[info exists ::env(FPGA_MAX_DSP)]} {
    set_property STEPS.SYNTH_DESIGN.ARGS.MAX_DSP $::env(FPGA_MAX_DSP) [get_runs synth_1]
} else {
    reset_property STEPS.SYNTH_DESIGN.ARGS.MAX_DSP [get_runs synth_1]
}
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]
if {[info exists ::env(FPGA_SYNTH_DIRECTIVE)]} {
    set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE $::env(FPGA_SYNTH_DIRECTIVE) [get_runs synth_1]
} else {
    reset_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE [get_runs synth_1]
}

if {[info exists ::env(FPGA_OPT_DIRECTIVE)]} {
    set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE $::env(FPGA_OPT_DIRECTIVE) [get_runs impl_1]
} else {
    set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
}
if {[info exists ::env(FPGA_PLACE_DIRECTIVE)]} {
    set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE $::env(FPGA_PLACE_DIRECTIVE) [get_runs impl_1]
} else {
    set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraNetDelay_high [get_runs impl_1]
}
if {[info exists ::env(FPGA_PHYS_OPT_DIRECTIVE)]} {
    set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE $::env(FPGA_PHYS_OPT_DIRECTIVE) [get_runs impl_1]
} else {
    set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
}
if {[info exists ::env(FPGA_ROUTE_DIRECTIVE)]} {
    set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE $::env(FPGA_ROUTE_DIRECTIVE) [get_runs impl_1]
} else {
    set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
}
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
if {[info exists ::env(FPGA_POST_ROUTE_PHYS_OPT_DIRECTIVE)]} {
    set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE $::env(FPGA_POST_ROUTE_PHYS_OPT_DIRECTIVE) [get_runs impl_1]
} else {
    set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
}

puts "$fpga_board_label project setup complete."
puts "Part: $fpga_part"
puts "Board part: $fpga_board_part"
puts "Constraint: $xdc_file"
puts "Bitstream base name: $fpga_bitstream_name"
puts "ILA module: $fpga_ila_module"
puts "Start delay cycles: $fpga_start_delay_cycles"
puts "Repo root: $repo_root"
puts "Vivado project: $project_xpr"
