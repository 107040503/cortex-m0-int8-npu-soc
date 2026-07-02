puts "phys_opt_design -help:"
catch {phys_opt_design -help} phys_help
puts $phys_help
puts "synth_design -help:"
catch {synth_design -help} synth_help
puts $synth_help
