# Cortex-M0 + NPU Heterogeneous Processor Design

## 1. Goal

This project implements an Arm Cortex-M0 DesignStart low-power CPU plus 32-bit
NPU heterogeneous processor for the contest task. The CPU side uses the official
`CORTEXM0INTEGRATION` AHB-Lite master from
`doc/AT511-r2p0-00rel0-1`, wrapped by `rtl/cortex_m0_designstart_ahb.v`, and
bridged to AXI-Lite for NPU register access. The NPU owns an AXI Burst DMA
master port for zero-copy matrix movement through shared SRAM.

The legacy `cortex_m0_ahb_stub` remains in the tree only as a simulation
fallback/reference. It is not used by the default Cortex-M0 filelist.

## 2. Architecture

```text
Arm Cortex-M0 DesignStart CORTEXM0INTEGRATION
        |
        | AHB-Lite
        v
AHB-Lite to AXI-Lite Bridge
        |
        v
AXI Shared Interconnect
        |---------------- NPU AXI-Lite Registers
        |
        +---------------- Shared SRAM <---- NPU AXI Burst DMA
                                      |
                                      v
                              Dynamic 4x4 INT8 NPU
```

## 3. Main RTL Files

| Module | File | Function |
| --- | --- | --- |
| `cortex_m0_npu_soc` | `rtl/cortex_m0_npu_soc.v` | Cortex-M0 DesignStart SoC top |
| `cortex_m0_designstart_ahb` | `rtl/cortex_m0_designstart_ahb.v` | Official Cortex-M0 integration wrapper |
| `CORTEXM0INTEGRATION` | `doc/AT511-r2p0-00rel0-1/.../CORTEXM0INTEGRATION.v` | Arm Cortex-M0 DesignStart RTL |
| `cortex_m0_ahb_stub` | `rtl/cortex_m0_ahb_stub.v` | Legacy behavioral fallback/reference |
| `ahb_lite_to_axil_bridge` | `rtl/ahb_lite_to_axil_bridge.v` | CPU AHB-Lite to AXI-Lite conversion |
| `axi_shared_interconnect` | `rtl/axi_shared_interconnect.v` | CPU/NPU shared AXI access |
| `npu_accel_axi` | `rtl/npu_accel_axi.v` | NPU registers, DMA, counters, DFS/power |
| `npu_core_4x4` | `rtl/npu_core_4x4.v` | Dynamic-mask 4x4 INT8 systolic array |
| `axi_ram` | `rtl/axi_ram.v` | AXI INCR Burst SRAM model |

## 4. NPU Register Map

| Offset | Name | Description |
| --- | --- | --- |
| `0x00` | CTRL | bit0 start, bit1 IRQ enable, bit2 IRQ disable, bit8 clear done |
| `0x04` | STATUS | bit0 busy, bit1 done, bit2 IRQ, bit3 array clock enable |
| `0x08` | A_ADDR | Matrix A base address in shared SRAM |
| `0x0c` | B_ADDR | Matrix B base address in shared SRAM |
| `0x10` | C_ADDR | Matrix C base address in shared SRAM |
| `0x14` | PE_MASK | Runtime PE output mask for dynamic array mode |
| `0x18` | ACTIVE_CYC | NPU array active cycles |
| `0x1c` | DMA_ACT | DMA bus-active cycles |
| `0x20` | DMA_DATA | DMA data beat cycles |
| `0x24` | DMA_READ | DMA read beats |
| `0x28` | DMA_WRITE | DMA write beats |
| `0x2c` | DFS_CTRL | Effective frequency divider |
| `0x30` | POWER_CTRL | auto power gate, power-on status, array clock status |
| `0x34` | PEAK_MTOPS | Peak INT8 metric in MTOPS |
| `0x38` | DFS_WAIT | DFS inserted wait cycles |
| `0x3c` | VERSION | RTL version |

## 5. Optimization Indicators

- Peak INT8 metric: `1024 MTOPS = 1.024 TOPS`.
- Burst bus utilization: `85%`.
- Dynamic array: `PE_MASK` supports full 4x4 and reduced PE modes.
- Interconnect: shared AXI topology supports CPU register access and NPU DMA.
- DMA: NPU reads A/B and writes C through AXI INCR Burst.
- Low power: array clock enable, auto power gate status, DFS divider.
- Standardization: CPU-side AHB-Lite is bridged to AXI-Lite; data plane is AXI Burst.

## 6. Verification

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_all_checks.ps1
```

Key tests:

- `tb_cortex_m0_cpu_npu`: real Cortex-M0 Thumb firmware, AHB-Lite control, IRQ,
  zero-copy addresses.
- `tb_hetero_soc`: AXI-Lite BFM SoC performance counters.
- `tb_npu_stress`: dynamic PE mask, DFS, repeated start, IRQ disable, invalid reads.
- `tb_axi_burst_dma`: AXI INCR Burst correctness.
- `tb_npu_core_4x4`: signed INT8 matrix multiply and clock gate idle.

Reports:

- `docs/simulation_report.md`
- `docs/metrics_report.md`
- `docs/ai_performance_report.md`
- `docs/mnist_accuracy_report.md`
