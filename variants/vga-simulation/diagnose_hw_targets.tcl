open_hw_manager
connect_hw_server

set servers [get_hw_servers]
puts "HW_SERVERS=$servers"

set targets [get_hw_targets]
puts "HW_TARGETS=$targets"

foreach target $targets {
    puts "TARGET=$target NAME=[get_property NAME $target] IS_OPEN=[get_property IS_OPEN $target]"
}

if {[llength $targets] > 0} {
    set target [lindex $targets 0]
    open_hw_target $target
    puts "OPENED_TARGET=$target"
    set devices [get_hw_devices]
    puts "HW_DEVICES=$devices"
    foreach dev $devices {
        puts "DEVICE=$dev PART=[get_property PART $dev]"
    }
}
