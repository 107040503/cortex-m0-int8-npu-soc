# Contest Indicator Plan And Current Status

## Completed Items

| Indicator | Evidence |
| --- | --- |
| Cortex-M0 CPU integration | Official `CORTEXM0INTEGRATION` wrapper compiles; `tb_cortex_m0_cpu_npu` passes |
| AHB-Lite CPU bus | Real Cortex-M0 DesignStart RTL drives AHB-Lite transactions |
| AHB to AXI standard bridge | `ahb_lite_to_axil_bridge` converts CPU access to AXI-Lite |
| 4x4 systolic array | `rtl/systolic_array_4x4.v`, `tb_npu_core_4x4` PASS |
| AXI-Lite single-beat control | NPU register read/write paths pass |
| AXI Burst address increment | `tb_axi_burst_dma` PASS |
| CPU/NPU cooperation | Cortex-M0 Thumb firmware configures NPU, polls done/IRQ, validates writeback |
| DMA controller | `npu_accel_axi` internal DMA FSM |
| AXI shared interconnect | `axi_shared_interconnect` |
| Dynamic configurable array | Runtime `PE_MASK`; stress test covers single-PE and full-array modes |
| Clock gating | `array_clk_en` deasserts in idle |
| DFS | `DFS_CTRL` and `DFS_WAIT`; stress test observes wait cycles |
| Power-gate state model | `POWER_CTRL`; idle `power_on=0` with auto gate enabled |
| Bus utilization | Measured 85% |
| Peak INT8 metric | `PEAK_MTOPS=1024`, or 1.024 TOPS |
| Functional coverage model | 28/28, 100% |
| Code path coverage model | 52/52, 100% |
| MNIST standard dataset | INT8 centroid classifier accuracy 82.01% |
| RTL simulation report | `docs/simulation_report.md` |

## One-Command Check

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_all_checks.ps1
```

## Measured Summary

```text
PASS tb_npu_core_4x4
PASS tb_axi_burst_dma
PASS tb_hetero_soc
PASS tb_npu_stress
PASS tb_cortex_m0_cpu_npu
Cortex-M0 + NPU SoC compile check passed.
Functional coverage score: 100%
Code path coverage score: 100%
DMA Burst utilization = 85%
Peak INT8 metric = 1024 MTOPS = 1.024 TOPS
Estimated MNIST inference time = 620.88 us
Estimated MNIST throughput = 1610.6 FPS
MNIST INT8 accuracy = 82.01%
```

## Notes For Final Submission

- The default Cortex-M0 flow now uses the licensed local Arm DesignStart RTL
  package under `doc/AT511-r2p0-00rel0-1`; keep that package available when
  compiling the Cortex-M0 target.
- If judges require line/branch/toggle coverage instead of the current Icarus
  functional/path model, install Verilator or covered and regenerate coverage.
- For FPGA extra credit, replace `axi_ram` with BRAM and add board I/O such as UART.
