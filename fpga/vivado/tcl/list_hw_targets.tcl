open_hw_manager
connect_hw_server -allow_non_jtag

puts "HW servers:"
foreach server [get_hw_servers -quiet] {
    puts "  $server"
}

puts "HW targets before refresh:"
foreach target [get_hw_targets -quiet *] {
    puts "  $target"
}

catch {refresh_hw_server [current_hw_server]} refresh_message
if {[info exists refresh_message] && $refresh_message ne ""} {
    puts "refresh_hw_server: $refresh_message"
}

puts "HW targets after refresh:"
set targets [get_hw_targets -quiet *]
foreach target $targets {
    puts "  $target"
    foreach prop [list NAME TYPE IS_OPEN IS_CONNECTED] {
        catch {puts "    $prop = [get_property $prop $target]"}
    }
}

if {[llength $targets] > 0} {
    current_hw_target [lindex $targets 0]
    open_hw_target
    puts "HW devices:"
    foreach device [get_hw_devices -quiet] {
        puts "  $device"
        foreach prop [list PART IDCODE PROGRAM.FILE PROBES.FILE] {
            catch {puts "    $prop = [get_property $prop $device]"}
        }
    }
} else {
    puts "No hardware targets found."
}
