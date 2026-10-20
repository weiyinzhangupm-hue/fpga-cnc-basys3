# Programa la Basys3 con el bitstream generado por build_bitstream.tcl.
set script_dir [file dirname [file normalize [info script]]]
set bit_file [file join $script_dir build rapido_es_v3 top_level_cnc_rapido_es_v3.bit]

if {![file exists $bit_file]} {
    error "Bitstream no encontrado: $bit_file. Ejecuta primero: source build_bitstream.tcl"
}

open_hw_manager
connect_hw_server

set targets [get_hw_targets]
if {[llength $targets] == 0} {
    error "No se encontro hardware target. Conecta y enciende la Basys3."
}

set target [lindex $targets 0]
open_hw_target $target

set devices [get_hw_devices *xc7a35t*]
if {[llength $devices] == 0} {
    set devices [get_hw_devices]
}
if {[llength $devices] == 0} {
    error "No se encontro ningun FPGA en la cadena JTAG."
}

set dev [lindex $devices 0]
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev
set_property PROGRAM.FILE $bit_file $dev
program_hw_devices $dev
puts "PROGRAM_OK=$dev FILE=$bit_file"
