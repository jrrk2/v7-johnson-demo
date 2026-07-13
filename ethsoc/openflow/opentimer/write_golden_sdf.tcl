open_checkpoint vc707_ethloop.dcp
write_sdf -force openflow/opentimer/golden_ethloop.sdf
report_timing -delay_type max -max_paths 20 -file openflow/opentimer/golden_timing.rpt
puts "SDF_DONE"
