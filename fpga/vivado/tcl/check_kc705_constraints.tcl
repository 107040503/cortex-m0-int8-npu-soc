source [file join [file dirname [file normalize [info script]]] setup_project.tcl]

set reports_dir [repo_file fpga/vivado/reports]
file mkdir $reports_dir
set report_file [file join $reports_dir kc705_constraint_check.txt]

set run_to_open impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "*Complete*" $impl_status]} {
    set run_to_open synth_1
}

open_run $run_to_open

set fh [open $report_file w]
puts $fh "KC705 constraint check"
puts $fh "Generated: [clock format [clock seconds]]"
puts $fh "Opened run: $run_to_open"
puts $fh ""

set pblocks [get_pblocks -quiet pblock_cortex_m0_logic]
puts $fh "pblock_cortex_m0_logic count: [llength $pblocks]"
if {[llength $pblocks] > 0} {
    set pblock_cells [get_cells -quiet -of_objects [get_pblocks pblock_cortex_m0_logic]]
    puts $fh "pblock_cortex_m0_logic cell count: [llength $pblock_cells]"
    puts $fh "pblock_cortex_m0_logic ranges: [get_property GRID_RANGES [get_pblocks pblock_cortex_m0_logic]]"
}

set cortex_cells [get_cells -quiet -hierarchical -filter {NAME =~ *u_soc/u_cpu/u_cortexm0integration/u_logic*}]
puts $fh "matched Cortex-M0 u_logic cell count: [llength $cortex_cells]"

set ila_cells [get_cells -quiet -hierarchical -filter {NAME =~ *u_ila_cpu_npu*}]
puts $fh "ILA instance cell count: [llength $ila_cells]"

set ila_ips [get_ips -quiet ila_cpu_npu_kc705]
puts $fh "ila_cpu_npu_kc705 IP count: [llength $ila_ips]"

close $fh
puts "Wrote $report_file"
