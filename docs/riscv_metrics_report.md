# RISC-V Metrics Report

Generated from Icarus Verilog logs in `sim/` for the PicoRV32 + NPU route.

## Simulation Pass Status

- tb_axi_burst_dma.log: PASS tb_axi_burst_dma
- tb_hetero_soc.log: PASS tb_hetero_soc
- tb_npu_core_4x4.log: PASS tb_npu_core_4x4
- tb_npu_stress.log: PASS tb_npu_stress
- tb_picorv32_cpu_npu.log: PASS tb_picorv32_cpu_npu
- No FAIL lines found in current RISC-V metric logs.

## Functional Coverage

- Required functional coverage points: 27
- Hit functional coverage points: 27
- Functional coverage score: 100%

- [hit] core_basic_matmul
- [hit] core_signed_int8
- [hit] core_clock_gate_idle
- [hit] axi_incr_write_burst
- [hit] axi_incr_read_burst
- [hit] axi_wlast_rlast
- [hit] soc_axil_control
- [hit] soc_dma_burst_read_write
- [hit] soc_irq_done
- [hit] soc_bus_util_over_80
- [hit] soc_peak_over_1tops
- [hit] soc_power_gate_idle
- [hit] undefined_register_read
- [hit] dynamic_pe_mask_single_pe
- [hit] dfs_divider_slow_mode
- [hit] clear_done
- [hit] irq_disable
- [hit] repeated_start
- [hit] dfs_full_speed_mode
- [hit] auto_power_gate_idle
- [hit] actual_picorv32_cpu_fetch
- [hit] actual_picorv32_axil_mmio
- [hit] actual_picorv32_cpu_npu_poll
- [hit] actual_picorv32_npu_irq
- [hit] actual_picorv32_zero_copy_addresses
- [hit] picorv32_peak_over_1tops
- [hit] picorv32_bus_util_over_80

## Code Path Coverage Model

- Required path coverage points: 55
- Hit path coverage points: 55
- Code path coverage score: 100%

- [hit] core_state_idle
- [hit] core_state_clear
- [hit] core_state_run
- [hit] core_state_done
- [hit] core_dfs_div0_tick
- [hit] core_pe_mask_all_enabled
- [hit] core_signed_positive_negative_zero
- [hit] core_array_clk_gate_idle
- [hit] axi_ram_aw_accept
- [hit] axi_ram_wdata_beats
- [hit] axi_ram_wlast_response
- [hit] axi_ram_ar_accept
- [hit] axi_ram_rdata_beats
- [hit] axi_ram_rlast_finish
- [hit] axi_ram_incr_address
- [hit] axi_ram_beat_counters
- [hit] axil_write_a_addr
- [hit] axil_write_b_addr
- [hit] axil_write_c_addr
- [hit] axil_write_pe_mask
- [hit] axil_write_ctrl_start_irq
- [hit] axil_read_status_busy_done
- [hit] axil_read_dma_counters
- [hit] axil_read_peak_mtops
- [hit] axil_read_power_ctrl
- [hit] npu_fsm_idle_to_read_a
- [hit] npu_fsm_read_a_ar
- [hit] npu_fsm_read_a_r
- [hit] npu_fsm_read_b_ar
- [hit] npu_fsm_read_b_r
- [hit] npu_fsm_core_start_wait
- [hit] npu_fsm_write_c_aw
- [hit] npu_fsm_write_c_w
- [hit] npu_fsm_write_c_b_done
- [hit] dma_data_util_counter
- [hit] dma_read_write_beat_counters
- [hit] irq_latched_done
- [hit] power_gate_idle_status
- [hit] axil_default_read_path
- [hit] pe_mask_single_enabled_path
- [hit] dfs_wait_increment_path
- [hit] dfs_divider_nonzero_path
- [hit] ctrl_clear_done_path
- [hit] ctrl_irq_disable_path
- [hit] repeated_start_path
- [hit] dfs_divider_zero_path
- [hit] power_auto_gate_status_path
- [hit] cpu_fetch_from_shared_sram
- [hit] cpu_store_npu_mmio_regs
- [hit] cpu_load_npu_status
- [hit] cpu_branch_poll_loop
- [hit] cpu_zero_copy_a_b_c_addresses
- [hit] interconnect_cpu_to_npu_path
- [hit] interconnect_cpu_fetch_ram_path
- [hit] interconnect_npu_dma_ram_path

## Performance And Power Evidence

- tb_hetero_soc.log: INFO soc DMA data utilization percent=85
- tb_hetero_soc.log: INFO soc peak mtops=1024
- tb_npu_stress.log: INFO stress dfs_wait_cycles=22
- tb_picorv32_cpu_npu.log: INFO picorv32 DMA data utilization percent=85
- tb_picorv32_cpu_npu.log: INFO picorv32 peak mtops=1024
- RTL clock target: 200 MHz
- Peak INT8 metric register: 1024 MTOPS = 1.024 TOPS
- DMA burst utilization target: >=80%, measured: 85%
- RISC-V integration evidence: PicoRV32 executes RV32I firmware from shared SRAM, issues AXI-Lite MMIO stores/loads to NPU registers, polls done/IRQ, and passes zero-copy A/B/C addresses.
- Clock gating/power-gate evidence: soc_power_gate_idle and auto_power_gate_idle coverage points hit

## Notes

This is a functional coverage report generated from self-checking Icarus testbenches.
Line/branch/toggle code coverage requires an additional coverage tool such as Verilator or covered.