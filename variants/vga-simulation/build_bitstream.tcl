# Genera el bitstream Basys3 CNC rapido_es_v3 desde Vivado Tcl Shell.
set script_dir [file dirname [file normalize [info script]]]
cd $script_dir

set part_name xc7a35tcpg236-1
set out_dir [file join $script_dir build rapido_es_v3]
file mkdir $out_dir

read_vhdl -vhdl2008 [list \
    FPGA_CNC.srcs/sources_1/new/uart_rx.vhd \
    FPGA_CNC.srcs/sources_1/new/uart_tx.vhd \
    FPGA_CNC.srcs/sources_1/new/FSM_Main.vhd \
    FPGA_CNC.srcs/sources_1/new/divisor_reloj.vhd \
    {FPGA_CNC.srcs/sources_1/imports/Proyecto FPGA/pen_controller.vhd} \
    FPGA_CNC.srcs/sources_1/new/tb6600_axis_driver.vhd \
    FPGA_CNC.srcs/sources_1/new/bresenham_3d.vhd \
    FPGA_CNC.srcs/sources_1/new/vga_shapes.vhd \
    FPGA_CNC.srcs/sources_1/new/top_level.vhd \
]

read_xdc FPGA_CNC.srcs/constrs_1/imports/Tutorial/Basys3_Master.xdc

synth_design -top top_level -part $part_name
opt_design
place_design
phys_opt_design
route_design

report_utilization -file [file join $out_dir top_level_utilization.rpt]
report_timing_summary -file [file join $out_dir top_level_timing_summary.rpt]

set setup_violations [get_timing_paths -delay_type max -max_paths 1 -slack_lesser_than 0]
set hold_violations [get_timing_paths -delay_type min -max_paths 1 -slack_lesser_than 0]
if {[llength $setup_violations] > 0 || [llength $hold_violations] > 0} {
    error "Fallo de temporizacion; revisa build/rapido_es_v3/top_level_timing_summary.rpt"
}

set bit_file [file join $out_dir top_level_cnc_rapido_es_v3.bit]
write_bitstream -force $bit_file
puts "BUILD_OK=$bit_file"
