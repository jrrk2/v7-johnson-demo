# Program the VC707 BPI (parallel NOR) configuration flash over JTAG via the
# Vivado hardware manager -- the NON-VOLATILE path openFPGALoader's SPI-only
# `-f` can't reach on this board.  Adapted from cva6's corev_apu/fpga/scripts/
# flash.tcl: parameterized (any bitstream via $BIT), auto-generates the .mcs,
# and defaults to the VC707.
#
#   BIT=<bitstream.bit> [MCS=<out.mcs>] [BOARD=vc707] \
#     vivado -mode batch -source flash_bpi.tcl
#
# Needs a running hw_server (Vivado starts a local one on connect); the board
# powered up in JTAG mode.  Non-volatile: survives power-cycle (unlike the
# openFPGALoader --cable SRAM load).

set BOARD [expr {[info exists ::env(BOARD)] ? $::env(BOARD) : "vc707"}]
if {![info exists ::env(BIT)]} { puts "ERROR: set BIT=<bitstream.bit>"; exit 1 }
set bit $::env(BIT)
set mcs [expr {[info exists ::env(MCS)] ? $::env(MCS) : "[file rootname $bit].mcs"}]

# Board -> (jtag device, cfgmem part, cfgmem geometry).
if {$BOARD eq "vc707"} {
    set device_name xc7vx485t_0
    set flash_type  mt28gu01gaax1e-bpi-x16
    set iface       BPIx16
    set size        128       ;# 1 Gib = 128 MiB
} elseif {$BOARD eq "genesys2" || $BOARD eq "kc705"} {
    set device_name xc7k325t_0
    set flash_type  s25fl256sxxxxxx0-spi-x1_x2_x4
    set iface       SPIx4
    set size        32
} else {
    puts "ERROR: unknown BOARD=$BOARD"; exit 1
}

# 1. bit -> mcs (skip if a fresh .mcs already exists next to the bit).
if {![file exists $mcs] || [file mtime $mcs] < [file mtime $bit]} {
    puts "=== write_cfgmem: $bit -> $mcs ($iface, ${size}MiB) ==="
    write_cfgmem -force -format mcs -interface $iface -size $size \
        -loadbit "up 0x0 $bit" -file $mcs
}

# MCS_ONLY=1 (or -tclargs mcs-only): stop after the .mcs is generated -- no
# board / hw_server needed.  Used by the `%.mcs: %.bit` make rule.
if {[info exists ::env(MCS_ONLY)] || ([llength $argv] > 0 && [lindex $argv 0] eq "mcs-only")} {
    puts "=== MCS-only: wrote $mcs, skipping hardware programming ==="
    exit 0
}

# 2. hardware manager: find the target holding our device.
open_hw_manager
connect_hw_server -url localhost:3121
set found 0
foreach target [get_hw_targets] {
    open_hw_target $target
    if {[llength [get_hw_devices $device_name]] > 0} { set found 1; break }
    close_hw_target
}
if {!$found} { puts "ERROR: device $device_name not found on any JTAG target"; exit 1 }

current_hw_device [get_hw_devices $device_name]
refresh_hw_device -update_hw_probes false [current_hw_device]

# 3. configure the cfgmem programming operation.
create_hw_cfgmem -hw_device [current_hw_device] \
    [lindex [get_cfgmem_parts $flash_type] 0]
set cfgmem [get_property PROGRAM.HW_CFGMEM [current_hw_device]]
set_property PROGRAM.FILES [list $mcs]      $cfgmem
set_property PROGRAM.PRM_FILE {}            $cfgmem
set_property PROGRAM.ADDRESS_RANGE {use_file} $cfgmem
set_property PROGRAM.BLANK_CHECK 0          $cfgmem
set_property PROGRAM.ERASE 1               $cfgmem
set_property PROGRAM.CFG_PROGRAM 1         $cfgmem
set_property PROGRAM.VERIFY 1              $cfgmem
set_property PROGRAM.CHECKSUM 0            $cfgmem
if {$BOARD eq "vc707"} {
    set_property PROGRAM.BPI_RS_PINS {none}              $cfgmem
    set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} $cfgmem
}

# 4. load the flash-programming bridge into the FPGA, then program the flash.
puts "=== programming $BOARD BPI flash (this erases + writes + verifies) ==="
create_hw_bitstream -hw_device [current_hw_device] \
    [get_property PROGRAM.HW_CFGMEM_BITFILE [current_hw_device]]
program_hw_devices [current_hw_device]
refresh_hw_device [current_hw_device]
program_hw_cfgmem -hw_cfgmem $cfgmem
puts "=== FLASH DONE: $BOARD now boots $bit from BPI flash (power-cycle to confirm) ==="
close_hw_target
