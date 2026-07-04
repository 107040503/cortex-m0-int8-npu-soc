# ARM/RISC-V + INT8 NPU Heterogeneous SoC
Committer：刘马均，UESTC

面向芯片设计竞赛/网申展示的 CPU + NPU 低功耗异构处理器项目。工程实现了
Arm Cortex-M0 控制子系统、RISC-V/PicoRV32 控制子系统、AXI 共享互连、
4x4 INT8 脉动阵列 NPU、AXI Burst DMA、低功耗控制与 KC705 Vivado 验证脚本。

1.当前展示实现是 **RISC-V/PicoRV32 + 自研NPU低功耗异构处理器**：该路线已在 KC705 Vivado
实现中达到真实 `soc_clk_mmcm = 5.000ns / 200.000MHz`，post-route
`WNS = 0.137ns`，DRC 无 Error，并保留 ILA。

2.ARM/Cortex-M0 + 自研NPU路线也已跑通
RTL 回归和真实 KC705 50MHz 上板 ILA 功能验证，但严格单时钟 200MHz
时序未收敛，原因见下文。

> 说明：Arm Cortex-M0 DesignStart 评估包受原厂许可约束，公开仓库不提交
> `doc/AT511-r2p0-00rel0-1/` 中的官方 RTL。复现实验时请自行获取合法授权包，
> 并按 `rtl/filelist_cortexm0.f` 中的路径放置。
>
> ARM Cortex-M0 RTL源码下载地址：https://www.arm.com/resources/free-evaluation-arm-cpus
>
> PicoRV32 使用 ISC License，作为 `third_party/picorv32` git submodule
> 引入；复现 RISC-V 路线时请执行 `git submodule update --init --recursive`。

## Project Highlights

| 方向 | 内容 |
| --- | --- |
| 处理器集成 | 支持 Arm Cortex-M0 DesignStart 与 RISC-V/PicoRV32 两条控制 CPU 路线 |
| NPU 计算 | 自研 4x4 INT8 systolic array，支持 signed INT8 GEMM 与运行时 `PE_MASK` |
| 总线/访存 | ARM 路线使用 AHB-Lite to AXI-Lite 控制桥；RISC-V 路线使用 PicoRV32 AXI 接口；两者共享 AXI Burst DMA/NPU 数据面 |
| 低功耗设计 | 阵列空闲 clock gate、auto power gate 状态、DFS wait-cycle 建模 |
| 验证方式 | VS Code + Icarus Verilog 自检 testbench，生成日志、波形与指标报告 |
| FPGA 流程 | KC705 Vivado 2019.2 脚本化综合/实现；RISC-V 路线已完成 200MHz timing signoff |

## Key Results

| 指标 | 结果 |
| --- | --- |
| ARM RTL 回归 | `tb_cortex_m0_cpu_npu` 等基础回归 PASS，真实 Cortex-M0 固件可驱动 NPU |
| ARM FPGA 功能验证 | KC705 50MHz bring-up 已完成 JTAG program + ILA capture，证明 CPU/NPU/DMA/IRQ 链路可上板运行 |
| ARM 200MHz 状态 | 已尝试严格单时钟 200MHz；最佳已知结果仍为负 WNS，最坏路径在混淆版 `CORTEXM0INTEGRATION/u_logic` 内部，因此不作为最终 200MHz 主线 |
| RISC-V RTL 回归 | `tb_picorv32_cpu_npu` PASS，PicoRV32 执行 RV32I 固件并通过 AXI/MMIO 驱动 NPU |
| RISC-V 覆盖模型 | 功能覆盖 27/27，路径覆盖 55/55，均为 100% |
| 峰值 INT8 指标 | `1024 MTOPS = 1.024 TOPS@INT8` |
| DMA Burst 利用率 | 85%，达到优化目标 `>=80%` |
| RISC-V Vivado 200MHz | `soc_clk_mmcm = 5.000ns / 200.000MHz`，post-route `WNS = 0.137ns`，DRC 0 Error，ILA 保留 |
| MNIST INT8 评估 | 8201/10000，82.01% |

详细证据见：

- [`docs/metrics_report.md`](docs/metrics_report.md)
- [`docs/riscv_metrics_report.md`](docs/riscv_metrics_report.md)
- [`docs/simulation_report.md`](docs/simulation_report.md)
- [`docs/mnist_accuracy_report.md`](docs/mnist_accuracy_report.md)
- [`docs/kc705_riscv_200mhz_result_20260703.md`](docs/kc705_riscv_200mhz_result_20260703.md)
- [`docs/riscv_200mhz_timing_closure_explanation.md`](docs/riscv_200mhz_timing_closure_explanation.md)
- [`docs/arm_200mhz_attempts_and_50mhz_decision.md`](docs/arm_200mhz_attempts_and_50mhz_decision.md)
- [`submission/kc705_fpga_waveform_metric_check.md`](submission/kc705_fpga_waveform_metric_check.md)

## Architecture

```text
ARM route:
  Arm Cortex-M0 -> AHB-Lite -> AHB-to-AXI-Lite bridge

RISC-V route:
  PicoRV32 AXI master

Common accelerator path:
  CPU control access -> AXI-Lite NPU registers
                     -> NPU AXI accelerator
                     -> AXI Burst DMA -> Shared AXI Interconnect -> AXI SRAM/BRAM
                     -> 4x4 INT8 Systolic Array
                     -> IRQ / done / performance counters / power status
```

## CPU Route Selection

两条 CPU 路线都跑通了，但最终 200MHz 展示实现选择 RISC-V/PicoRV32：

| 路线 | 已完成内容 | 不作为/作为 200MHz 主线的原因 |
| --- | --- | --- |
| ARM/Cortex-M0 | RTL 回归 PASS；真实 KC705 50MHz program + ILA 捕获 PASS；NPU 指标、DMA 利用率和低功耗观测链路已验证 | 严格单时钟 200MHz 多次 Vivado 实现仍为负 WNS，最坏路径在 Arm DesignStart 混淆核 `CORTEXM0INTEGRATION/u_logic` 内部；当前无法合法插入流水线或设置内部 `SMUL` 等参数，不能用 false path/multicycle 或 50MHz 上板结果满足指标要求 |
| RISC-V/PicoRV32 | RTL 回归 PASS；PicoRV32 固件通过 AXI/MMIO 配置 NPU；Vivado KC705 200MHz 实现 WNS 为正；ILA `.ltx` 已生成 | PicoRV32 RTL 开源可控，可关闭乘除法/计数器并启用 two-cycle ALU/compare，控制面更轻量，适合作为当前 200MHz timing signoff 主线 |

## Repository Layout

| 路径 | 说明 |
| --- | --- |
| `rtl/` | SoC、NPU、AXI、AHB bridge、Cortex-M0 wrapper、PicoRV32 wrapper 等 RTL |
| `third_party/picorv32/picorv32.v` | PicoRV32 CPU RTL，以 submodule 形式用于 RISC-V 路线 |
| `tb/` | Icarus Verilog 自检 testbench |
| `scripts/` | 一键回归、报告生成、Vivado/KC705 自动化脚本 |
| `docs/` | 设计说明、仿真报告、覆盖/性能/MNIST 指标报告 |
| `submission/` | 面向比赛提交/展示的设计文档与验证记录 |
| `fpga/` | KC705 顶层 wrapper、XDC、Vivado TCL、MATLAB helper |
| `fpga/rtl/fpga_kc705_riscv_top.v` | KC705 RISC-V/PicoRV32 200MHz FPGA 顶层 |

## Quick Start

环境依赖：

- Windows PowerShell
- Icarus Verilog，可放置在 `D:\Application\iverilog\bin`
- PicoRV32 submodule：`git submodule update --init --recursive`
- 可选：GTKWave 查看 `sim/*.vcd`
- 可选：Vivado 2019.2 + KC705 board files 运行 FPGA 流程
- 可选：MATLAB R2024b 运行 MATLAB helper

运行完整 RTL 回归与报告生成：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_all_checks.ps1
```

运行 RISC-V/PicoRV32 专项回归与指标报告：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_iverilog.ps1 -Top tb_picorv32_cpu_npu
powershell -ExecutionPolicy Bypass -File scripts/gen_riscv_metrics_report.ps1
```

VS Code 中可直接执行：

```text
Terminal > Run Task... > Project: run all checks and reports
```

预期输出包含：

```text
PASS tb_npu_core_4x4
PASS tb_axi_burst_dma
PASS tb_hetero_soc
PASS tb_npu_stress
PASS tb_cortex_m0_cpu_npu
Cortex-M0 + NPU SoC compile check passed.
Functional coverage score: 100%
Code path coverage score: 100%
MNIST INT8 accuracy: 82.01%
```

RISC-V 专项预期输出包含：

```text
PASS tb_picorv32_cpu_npu
INFO picorv32 DMA data utilization percent=85
INFO picorv32 peak mtops=1024
Functional coverage score: 100%
Code path coverage score: 100%
```

## FPGA Flow

KC705 自动化脚本位于 `fpga/` 和 `scripts/`。

RISC-V/PicoRV32 200MHz Vivado 实现：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check_kc705_env.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_vivado_kc705_riscv_experiment.ps1 -Jobs 4 -ExperimentName kc705_riscv_200mhz
powershell -ExecutionPolicy Bypass -File scripts/check_vivado_timing_gate.ps1 -TimingReport fpga\vivado\experiments\kc705_riscv_200mhz\reports\impl_timing_summary.rpt -ClockName soc_clk_mmcm
```

RISC-V 200MHz 验收结果：

```text
Clock soc_clk_mmcm: period=5.000 ns, frequency=200.000 MHz
Overall WNS: 0.137 ns
Timing gate passed.
```

ARM/Cortex-M0 的真实 KC705 50MHz program + ILA 捕获证据见
`submission/kc705_fpga_waveform_metric_check.md`。ARM 严格单时钟 200MHz
当前不作为 signoff bitstream；不要把负 WNS bitstream 或 50MHz bring-up
结果包装成 200MHz FPGA 通过。

Vivado/MATLAB 路径可在脚本参数中覆盖；本地默认路径记录在 `fpga/README.md`。

## Waveform Review

ARM 主推荐波形：

```powershell
& "D:\Application\iverilog\gtkwave\bin\gtkwave.exe" "D:\Documents\Program\IC\sim\tb_cortex_m0_cpu_npu.vcd"
```

重点观察信号：

- `tb_cortex_m0_cpu_npu.dut.u_cpu.haddr`
- `tb_cortex_m0_cpu_npu.dut.u_ahb_to_axil.state`
- `tb_cortex_m0_cpu_npu.dut.u_npu.state`
- `tb_cortex_m0_cpu_npu.npu_irq`
- `tb_cortex_m0_cpu_npu.npu_array_clk_en`
- `tb_cortex_m0_cpu_npu.dut.u_sram.mem`

RISC-V 主推荐波形：

```powershell
& "D:\Application\iverilog\gtkwave\bin\gtkwave.exe" "D:\Documents\Program\IC\sim\tb_picorv32_cpu_npu.vcd"
```

重点观察 PicoRV32 取指、AXI/MMIO 写 NPU 寄存器、轮询 done/IRQ、DMA read/write beat 计数和 `npu_array_clk_en`。

## Resume-Friendly Summary

项目完成了 ARM/Cortex-M0 与 RISC-V/PicoRV32 两条控制 CPU 路线的自研
INT8 NPU 异构 SoC。NPU 通过 AXI Burst DMA 访问共享 SRAM/BRAM，4x4
systolic array 完成 INT8 矩阵乘，支持 PE mask、DFS 建模和空闲时钟门控。

ARM 路线已完成 RTL 功能回归和 KC705 50MHz 真实上板 ILA 功能验证；
严格单时钟 200MHz 因混淆版 Cortex-M0 内部关键路径未收敛，不作为最终
200MHz signoff 主线。RISC-V/PicoRV32 路线使用可控开源 CPU RTL，关闭
不需要的乘除法和计数器，启用 two-cycle ALU/compare，最终在 KC705 Vivado
实现中达到 `soc_clk_mmcm = 5.000ns / 200.000MHz`、`WNS = 0.137ns`、
DRC 0 Error，并保留 ILA。RTL 指标保持 1.024 TOPS@INT8、DMA Burst
利用率 85%，功能/路径覆盖模型均为 100%。
