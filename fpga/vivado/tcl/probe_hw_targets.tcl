open_hw_manager
connect_hw_server

set targets [get_hw_targets *]
puts "HW_TARGET_COUNT=[llength $targets]"
foreach target $targets {
    puts "HW_TARGET=$target"
    catch {
        current_hw_target $target
        open_hw_target
        puts "HW_DEVICES=[get_hw_devices]"
        close_hw_target
    } result
    if {$result ne ""} {
        puts "HW_TARGET_RESULT=$result"
    }
}

disconnect_hw_server
