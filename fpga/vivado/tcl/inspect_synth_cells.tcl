source [file join [file dirname [file normalize [info script]]] setup_project.tcl]

if {[info exists ::env(VIVADO_JOBS)]} {
    set jobs $::env(VIVADO_JOBS)
} else {
    set jobs 4
}

set reports_dir [repo_file fpga/vivado/reports]
file mkdir $reports_dir
set report_file [file join $reports_dir synth_cortexm0_cells.txt]

set synth_status [get_property STATUS [get_runs synth_1]]
set synth_needs_refresh [get_property NEEDS_REFRESH [get_runs synth_1]]
if {![string match "*Complete*" $synth_status] || $synth_needs_refresh} {
    if {$synth_needs_refresh} {
        reset_run synth_1
    }
    launch_runs synth_1 -jobs $jobs
    wait_on_run synth_1
}

open_run synth_1

set fh [open $report_file w]
puts $fh "Cortex-M0 synthesized hierarchy inspection"
puts $fh "Generated: [clock format [clock seconds]]"
puts $fh ""

set queries [list \
    {NAME =~ *u_soc/u_cpu*} \
    {NAME =~ *u_cortexm0integration*} \
    {NAME =~ *u_logic*} \
    {REF_NAME =~ DSP48E1} \
]

foreach query $queries {
    set cells [lsort [get_cells -quiet -hierarchical -filter $query]]
    puts $fh "QUERY: $query"
    puts $fh "COUNT: [llength $cells]"
    foreach cell [lrange $cells 0 199] {
        puts $fh $cell
    }
    puts $fh ""
}

set dsp_cells [lsort [get_cells -quiet -hierarchical -filter {REF_NAME =~ DSP48E1 && NAME =~ *u_cortexm0integration*}]]
puts $fh "CORTEXM0 DSP48E1 COUNT: [llength $dsp_cells]"
foreach cell $dsp_cells {
    puts $fh $cell
}

close $fh
puts "Wrote $report_file"
