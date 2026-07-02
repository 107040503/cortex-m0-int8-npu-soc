# RTL Simulation Report

## 1. Environment

- Editor: VS Code.
- Simulator: Icarus Verilog.
- Icarus path: `D:\Application\iverilog\bin`.
- CPU RTL: Arm Cortex-M0 DesignStart `CORTEXM0INTEGRATION` from
  `doc/AT511-r2p0-00rel0-1`.
- Main script: `scripts/run_all_checks.ps1`.
- Waveforms: `sim/*.vcd`.

Command:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_all_checks.ps1
```

## 2. Passing Results

```text
PASS tb_npu_core_4x4
PASS tb_axi_burst_dma
PASS tb_hetero_soc
PASS tb_npu_stress
PASS tb_cortex_m0_cpu_npu
All requested simulations passed.
Cortex-M0 + NPU SoC compile check passed.
Functional coverage score: 100%
Code path coverage score: 100%
MNIST INT8 accuracy: 82.01%
```

## 3. Testbench Coverage

| Testbench | Coverage target | Result |
| --- | --- | --- |
| `tb_npu_core_4x4` | 4x4 signed INT8 GEMM, idle clock gate | PASS |
| `tb_axi_burst_dma` | AXI INCR Burst read/write and last signals | PASS |
| `tb_hetero_soc` | AXI-Lite control, DMA, IRQ, counters, peak metric | PASS |
| `tb_npu_stress` | PE mask, DFS, repeated start, IRQ disable, invalid read | PASS |
| `tb_cortex_m0_cpu_npu` | Real Cortex-M0 Thumb firmware, AHB-Lite control, bridge, IRQ polling, zero-copy addresses | PASS |

## 4. Performance And Power Evidence

```text
INFO cortex_m0 DMA data utilization percent=85
INFO cortex_m0 peak mtops=1024
INFO stress dfs_wait_cycles=20
```

- RTL clock target: 200 MHz.
- Peak INT8 metric: 1024 MTOPS, or 1.024 TOPS.
- DMA Burst utilization: 85%, above the 80% optimization target.
- Low power: `array_clk_en=0` after completion, auto power gate idle covered.
- DFS: slow mode inserts 20 wait cycles in stress testing.
- CPU/NPU cooperation: real Cortex-M0 firmware configures the NPU, polls STATUS,
  stores metrics to SRAM, and writes a completion sentinel.

## 5. AI Inference Evidence

`docs/mnist_accuracy_report.md` uses the official MNIST IDX test set:

```text
Correct predictions: 8201/10000
MNIST INT8 accuracy: 82.01%
Estimated RTL throughput: 8721.4 FPS
```

`docs/ai_performance_report.md` gives a deterministic MNIST MLP estimate:

```text
Estimated MNIST inference time: 620.88 us
Estimated MNIST throughput: 1610.6 FPS
```

## 6. Logs And Waveforms

Logs:

- `sim/tb_npu_core_4x4.log`
- `sim/tb_axi_burst_dma.log`
- `sim/tb_hetero_soc.log`
- `sim/tb_npu_stress.log`
- `sim/tb_cortex_m0_cpu_npu.log`

Recommended waveform:

```powershell
& "D:\Application\iverilog\gtkwave\bin\gtkwave.exe" "D:\Documents\Program\IC\sim\tb_cortex_m0_cpu_npu.vcd"
```
