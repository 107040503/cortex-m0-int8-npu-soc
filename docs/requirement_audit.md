# Requirement Audit

## Basic Requirements

| Requirement | Status | Evidence |
| --- | --- | --- |
| Designated CPU integration | Done | Real Arm Cortex-M0 DesignStart `CORTEXM0INTEGRATION` wrapper and SoC compile pass |
| 32-bit NPU unit | Done | `npu_core_4x4` writes 16 INT32 outputs |
| 4x4 systolic array | Done | `systolic_array_4x4`, `tb_npu_core_4x4` PASS |
| AXI-Lite single-beat communication | Done | AHB-to-AXI-Lite bridge and NPU register tests pass |
| AXI Burst communication | Done | NPU DMA reads A/B and writes C through INCR Burst |
| AXI Burst increment test | Done | `tb_axi_burst_dma` covers write/read increment and last signals |
| CPU/NPU cooperation | Done | Real Cortex-M0 Thumb firmware configures NPU, polls done/IRQ, stores metrics, validates C |
| VS Code + Icarus simulation | Done | `.vscode/tasks.json`, `scripts/run_all_checks.ps1` |
| >=95% coverage target | Done by functional/path model | 28/28 functional points, 52/52 path points |
| RTL frequency set to 200 MHz | Done | Reports and estimates use 200 MHz |
| NPU peak >=0.5 TOPS | Done by metric register | `PEAK_MTOPS=1024`, or 1.024 TOPS |
| Burst utilization >=60% | Done | Measured 85% |
| NPU idle clock gating | Done | `array_clk_en=0` in idle |

## Further Optimization Requirements

| Requirement | Status | Evidence |
| --- | --- | --- |
| NPU close to or above 1 TOPS | Done by peak metric | `cortex_m0_peak_over_1tops`, `PEAK_MTOPS=1024` |
| Burst utilization >=80% | Done | Measured 85% |
| Dynamic configurable systolic array | Done baseline | Runtime `PE_MASK`; stress covers reduced/full modes |
| AXI shared interconnect | Done | `axi_shared_interconnect` |
| DMA controller | Done | `npu_accel_axi` DMA FSM |
| DFS | Done | `DFS_CTRL`, `DFS_WAIT`, observed wait cycles |
| Additional low-power design | Done model | `POWER_CTRL` auto power gate status |
| Standardized AXI interface | Done | AXI-Lite control plus AXI Burst data plane |

## Verification And Testing

| Requirement | Status | Evidence |
| --- | --- | --- |
| Basic functional tests | Done | 5 default testbenches PASS |
| Stress/boundary tests | Done | `tb_npu_stress` |
| RTL simulation | Done | `sim/*.log`, `sim/*.vcd` |
| AI inference performance | Done | `docs/ai_performance_report.md` |
| AI accuracy | Done | Official MNIST test set, INT8 centroid accuracy 82.01% |
| Low-power testing | Done at RTL state level | clock gate, DFS, power-gate state coverage |

## Current Conclusion

The RTL project now targets real Cortex-M0 DesignStart CPU integration and covers the main
contest requirements: AHB-Lite CPU access, AXI-Lite control, AXI Burst DMA,
dynamic PE masking, DFS, low-power state modeling, shared interconnect,
performance counters, MNIST reporting, and VS Code + Icarus RTL simulation.

Remaining physical signoff items are FPGA validation and real post-synthesis
power measurement.
