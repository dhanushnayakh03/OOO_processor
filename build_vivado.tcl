# ==============================================================================
# File: build_vivado.tcl
# Description: Automated 1-Click Vivado Project & Bitstream Generation Script
# Target Board: PYNQ-Z2 (Zynq-7000 xc7z020clg400-1)
# Top Module: design_1_wrapper (containing Zynq PS + ooo_axi_wrapper_0)
# ==============================================================================

# Determine directory of this script
set script_dir [file dirname [file normalize [info script]]]
if {$script_dir eq ""} { set script_dir "." }
set src_dir [file join $script_dir "src"]

set project_name "pynq_ooo_scalar_fin"
set project_dir  [file join $script_dir "vivado_project"]
set part_number  "xc7z020clg400-1"

puts "=================================================================="
puts " Creating Clean Vivado Project: $project_name for $part_number"
puts " Project Location: $project_dir"
puts "=================================================================="

# 1. Close any open project and create a fresh one
catch { close_project }
file delete -force $project_dir
create_project -force $project_name $project_dir -part $part_number

# 2. Add All Clean RTL Source Files
set src_files [list \
    [file join $src_dir "defs.v"] \
    [file join $src_dir "branch_predictor.v"] \
    [file join $src_dir "fetch_stage.v"] \
    [file join $src_dir "map_table.v"] \
    [file join $src_dir "arch_map_table.v"] \
    [file join $src_dir "free_list.v"] \
    [file join $src_dir "physical_regfile.v"] \
    [file join $src_dir "rob.v"] \
    [file join $src_dir "store_queue.v"] \
    [file join $src_dir "reservation_station.v"] \
    [file join $src_dir "dispatch_stage.v"] \
    [file join $src_dir "issue_stage.v"] \
    [file join $src_dir "fu_alu.v"] \
    [file join $src_dir "fu_mult.v"] \
    [file join $src_dir "fu_branch.v"] \
    [file join $src_dir "fu_load.v"] \
    [file join $src_dir "complete_stage.v"] \
    [file join $src_dir "retire_stage.v"] \
    [file join $src_dir "core.v"] \
    [file join $src_dir "memory.v"] \
    [file join $src_dir "ooo_axi_wrapper.v"] \
]

add_files -norecurse $src_files
set_property include_dirs $src_dir [get_filesets sources_1]
update_compile_order -fileset sources_1

# 3. Create Block Design
puts "=================================================================="
puts " Building Block Design with ZYNQ PS & ooo_axi_wrapper_0"
puts "=================================================================="
create_bd_design "design_1"

# Instantiate ZYNQ Processing System
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7_0

# Configure PS: Enable M_AXI_GP0, FCLK0 at 20 MHz (non-negative slack), and Resets
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {20} \
    CONFIG.PCW_EN_RST0_PORT {1} \
] [get_bd_cells ps7_0]

# Try applying PYNQ-Z2 board preset; fallback to making DDR/FIXED_IO external
catch {
    apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable" } [get_bd_cells ps7_0]
}
catch {
    make_bd_intf_pins_external [get_bd_intf_pins ps7_0/DDR]
    make_bd_intf_pins_external [get_bd_intf_pins ps7_0/FIXED_IO]
}

# Instantiate OoO Processor AXI Wrapper as Module Reference
create_bd_cell -type module -reference ooo_axi_wrapper ooo_axi_wrapper_0

# Run Connection Automation for AXI Interconnect, Clocks, Resets
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { \
    Master "/ps7_0/M_AXI_GP0" \
    Clk "Auto" \
} [get_bd_pins ooo_axi_wrapper_0/s_axi]

# Validate and Save Block Design
validate_bd_design
save_bd_design

# 4. Generate Output Products & HDL Wrapper
puts "=================================================================="
puts " Generating Block Design Output Products & HDL Wrapper"
puts "=================================================================="
set bd_file [get_files "design_1.bd"]
generate_target all $bd_file
make_wrapper -files $bd_file -top
add_files -norecurse [get_files -of_objects [get_filesets sources_1] *design_1_wrapper*]
set_property top design_1_wrapper [current_fileset]
update_compile_order -fileset sources_1

# 5. Run Synthesis and Implementation to Generate Bitstream
puts "=================================================================="
puts " Running Fresh Synthesis & Implementation (Zero Cache)..."
puts "=================================================================="
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# 6. Copy Bitstream and Hardware Handoff (.hwh) for PYNQ
set bit_file [get_property DIRECTORY [get_runs impl_1]]/design_1_wrapper.bit

file copy -force $bit_file [file join $script_dir "ooo_scalar.bit"]
catch {
    set hwh_files [glob -nocomplain [file join $project_dir "$project_name.gen" "sources_1" "bd" "design_1" "hw_handoff" "*.hwh"]]
    if {[llength $hwh_files] > 0} {
        file copy -force [lindex $hwh_files 0] [file join $script_dir "ooo_scalar.hwh"]
    }
}

puts "=================================================================="
puts " BUILD COMPLETE!"
puts " Output files generated:"
puts "   -> [file join $script_dir ooo_scalar.bit]"
puts "   -> [file join $script_dir ooo_scalar.hwh]"
puts " Copy ooo_scalar.bit to your PYNQ board and run test_branch_simple.s!"
puts "=================================================================="
