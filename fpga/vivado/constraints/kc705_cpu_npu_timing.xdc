create_pblock pblock_cortex_m0_logic
add_cells_to_pblock [get_pblocks pblock_cortex_m0_logic] [get_cells -quiet -hierarchical -filter {NAME =~ *u_soc/u_cpu/u_cortexm0integration/u_logic*}]
resize_pblock [get_pblocks pblock_cortex_m0_logic] -add {SLICE_X80Y32:SLICE_X119Y127 DSP48_X2Y12:DSP48_X3Y47}
