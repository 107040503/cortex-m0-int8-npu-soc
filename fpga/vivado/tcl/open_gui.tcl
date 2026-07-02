source [file join [file dirname [file normalize [info script]]] setup_project.tcl]
start_gui
if {[info exists fpga_board_label]} {
    puts "Vivado GUI is open for $fpga_board_label CPU+NPU project inspection."
} else {
    puts "Vivado GUI is open for CPU+NPU project inspection."
}
