# EN: Recreate either original variant without development-machine cache paths.
# ES: Recrea cada variante sin las rutas de cache de la maquina de desarrollo.
# vivado -mode batch -source scripts/create_project.tcl -tclargs hardware-homing
if {$argc != 1} {
    error "Expected one variant: hardware-homing or vga-simulation"
}
set variant [lindex $argv 0]
if {$variant ni {hardware-homing vga-simulation}} {
    error "Unknown variant: $variant"
}
set repo_root [file dirname [file dirname [file normalize [info script]]]]
set variant_root [file join $repo_root variants $variant]
set source_root [file join $variant_root FPGA_CNC.srcs]
set output_dir [file join $repo_root build $variant]
if {[file exists [file join $output_dir FPGA_CNC.xpr]]} {
    error "Project already exists: $output_dir. Open it or choose a fresh checkout."
}
set rtl [glob -directory [file join $source_root sources_1 new] *.vhd]
lappend rtl [file join $source_root sources_1 imports {Proyecto FPGA} pen_controller.vhd]
set tests [glob -directory [file join $source_root sim_1 new] *.vhd]
set constraints [file join $source_root constrs_1 imports Tutorial Basys3_Master.xdc]
foreach source [concat $rtl $tests [list $constraints]] {
    if {![file exists $source]} { error "Missing source: $source" }
}
create_project FPGA_CNC $output_dir -part xc7a35tcpg236-1
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]
add_files -fileset sources_1 $rtl
add_files -fileset constrs_1 $constraints
add_files -fileset sim_1 $tests
set_property file_type {VHDL 2008} [get_files *.vhd]
set_property top top_level [get_filesets sources_1]
set_property top tb_top_level [get_filesets sim_1]
update_compile_order -fileset sources_1
puts "PROJECT_READY=$output_dir/FPGA_CNC.xpr"
puts "Original testbenches are retained; see docs/VALIDATION.md before simulation."
close_project
