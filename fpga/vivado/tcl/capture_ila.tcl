source [file join [file dirname [file normalize [info script]]] program_hw.tcl]

set captures_dir [file normalize [file join $repo_root fpga/vivado/captures]]
file mkdir $captures_dir
set capture_stamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set summary_file [file join $captures_dir "kc705_ila_capture_${capture_stamp}.txt"]
set summary_fh [open $summary_file w]

proc log_capture {message} {
    global summary_fh
    puts $message
    puts $summary_fh $message
    flush $summary_fh
}

proc find_hw_probe_by_name {ila patterns} {
    foreach pattern $patterns {
        set matches [get_hw_probes -quiet $pattern -of_objects $ila]
        if {[llength $matches] > 0} {
            return [lindex $matches 0]
        }
        foreach probe [get_hw_probes -quiet -of_objects $ila] {
            set probe_name [get_property NAME $probe]
            if {[string match "*$pattern*" $probe_name]} {
                return $probe
            }
        }
    }
    return ""
}

set ilas [get_hw_ilas]
if {[llength $ilas] == 0} {
    error "No ILA cores found. Build with FPGA_ENABLE_ILA enabled and ensure the .ltx file is loaded."
}

foreach ila $ilas {
    log_capture "Configuring ILA: $ila"
    set probes [get_hw_probes -quiet -of_objects $ila]
    foreach probe $probes {
        set probe_width "unknown"
        catch {set probe_width [get_property PORT_WIDTH $probe]}
        log_capture "  probe: [get_property NAME $probe] width=$probe_width"
    }

    catch {set_property CONTROL.TRIGGER_POSITION 16 $ila}
    set trigger_probe [find_hw_probe_by_name $ila [list debug_resetn probe4]]
    if {$trigger_probe ne ""} {
        set trigger_result [catch {set_property TRIGGER_COMPARE_VALUE {eq1'b1} $trigger_probe} trigger_message]
        if {$trigger_result == 0} {
            log_capture "Trigger: [get_property NAME $trigger_probe] == 1"
        } else {
            log_capture "WARNING: failed to set trigger compare on [get_property NAME $trigger_probe]: $trigger_message"
        }
    } else {
        log_capture "WARNING: debug_resetn/probe4 trigger probe not found; using Vivado default trigger."
    }

    run_hw_ila $ila
    set wait_result [catch {wait_on_hw_ila -timeout 90 $ila} wait_message]
    if {$wait_result != 0} {
        log_capture "WARNING: ILA wait failed or timed out: $wait_message"
    }
    set data [upload_hw_ila_data $ila]
    set safe_name [string map {/ _ \\ _ : _} $ila]
    set csv_file [file join $captures_dir "${capture_stamp}_${safe_name}.csv"]
    write_hw_ila_data -csv_file $csv_file $data
    log_capture "CSV: $csv_file"
}

close $summary_fh
puts "ILA capture files written to $captures_dir"
