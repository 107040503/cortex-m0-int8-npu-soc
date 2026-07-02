#ARM Cortex-M0 + INT8 NPU Heterogeneous SoC
Committer：刘马均，UESTC

CPU+自研NPU异构处理器项目。工程实现了
Arm Cortex-M0 控制子系统、AHB-Lite 到 AXI-Lite 桥、AXI 共享互连、
4x4 INT8 脉动阵列 NPU、AXI Burst DMA、低功耗控制与 FPGA 上板验证。

> 说明：Arm Cortex-M0 DesignStart 评估包受原厂许可约束，公开仓库不提交
> `doc/AT511-r2p0-00rel0-1/` 中的官方 RTL。复现实验时请自行获取合法授权包，
> 并按 `rtl/filelist_cortexm0.f` 中的路径放置。
>
> ARM Cortex-M0 RTL源码下载地址：https://www.arm.com/resources/free-evaluation-arm-cpus

## Project Highlights

| 方向 | 内容 |
| --- | --- |
| 处理器集成 | 真实 Arm Cortex-M0 DesignStart RTL，经本地 AHB-Lite wrapper 接入 SoC |
| NPU 计算 | 自研 4x4 INT8 systolic array，支持 signed INT8 GEMM 与运行时 `PE_MASK` |
| 总线/访存 | AHB-Lite to AXI-Lite 控制桥，AXI shared interconnect，AXI Burst DMA |
| 低功耗设计 | 阵列空闲 clock gate、auto power gate 状态、DFS wait-cycle 建模 |
| 验证方式 | VS Code + Icarus Verilog 自检 testbench，生成日志、波形与指标报告 |
| FPGA 流程 | KC705 Vivado 2019.2 脚本化 setup/synth/impl/program/capture |

## Key Results

| 指标 | 结果 |
| --- | --- |
| RTL 回归 | `tb_npu_core_4x4`、`tb_axi_burst_dma`、`tb_hetero_soc`、`tb_npu_stress`、`tb_cortex_m0_cpu_npu` 全部 PASS |
| 功能覆盖模型 | 28/28，100% |
| 路径覆盖模型 | 52/52，100% |
| 峰值 INT8 指标 | `1024 MTOPS = 1.024 TOPS` |
| DMA Burst 利用率 | 85% |
| MNIST INT8 评估 | 8201/10000，82.01% |
| FPGA 上板 | KC705 bitstream 生成、JTAG 下载与 ILA 捕获流程已打通 |

详细证据见：

- [`docs/metrics_report.md`](docs/metrics_report.md)
- [`docs/simulation_report.md`](docs/simulation_report.md)
- [`docs/mnist_accuracy_report.md`](docs/mnist_accuracy_report.md)
- [`submission/kc705_fpga_waveform_metric_check.md`](submission/kc705_fpga_waveform_metric_check.md)

## Architecture

```text
Arm Cortex-M0
      |
      | AHB-Lite
      v
AHB-Lite to AXI-Lite Bridge
      |
      v
AXI-Lite Control Registers
      |
      v
NPU AXI Accelerator
      |
      +-- AXI Burst DMA -- Shared AXI Interconnect -- AXI SRAM
      |
      +-- 4x4 INT8 Systolic Array
      |
      +-- IRQ / done / performance counters / power status
```

## Repository Layout

| 路径 | 说明 |
| --- | --- |
| `rtl/` | SoC、NPU、AXI、AHB bridge、Cortex-M0 wrapper 等 RTL |
| `tb/` | Icarus Verilog 自检 testbench |
| `scripts/` | 一键回归、报告生成、Vivado/KC705 自动化脚本 |
| `docs/` | 设计说明、仿真报告、覆盖/性能/MNIST 指标报告 |
| `submission/` | 面向比赛提交/展示的设计文档与验证记录 |
| `fpga/` | KC705 顶层 wrapper、XDC、Vivado TCL、MATLAB helper |
| `rtl/picorv32_npu_soc.v` | 备用/参考 PicoRV32 SoC wrapper |

## Quick Start

环境依赖：

- Windows PowerShell
- Icarus Verilog，可放置在 `D:\Application\iverilog\bin`
- 可选：GTKWave 查看 `sim/*.vcd`
- 可选：Vivado 2019.2 + KC705 board files 运行 FPGA 流程
- 可选：MATLAB R2024b 运行 MATLAB helper

运行完整 RTL 回归与报告生成：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_all_checks.ps1
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

## FPGA Flow

KC705 自动化脚本位于 `fpga/` 和 `scripts/`。常用命令：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check_kc705_env.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_vivado_kc705.ps1 -Action setup
powershell -ExecutionPolicy Bypass -File scripts/run_vivado_kc705.ps1 -Action synth
powershell -ExecutionPolicy Bypass -File scripts/run_vivado_kc705.ps1 -Action impl
powershell -ExecutionPolicy Bypass -File scripts/run_vivado_kc705.ps1 -Action program
```

Vivado/MATLAB 路径可在脚本参数中覆盖；本地默认路径记录在 `fpga/README.md`。

## Waveform Review

主推荐波形：

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

## Resume-Friendly Summary

项目完成了一个可仿真、可上板的 Cortex-M0 + 自研 INT8 NPU 异构 SoC：
CPU 通过 AHB-Lite/AXI-Lite 配置 NPU，NPU 通过 AXI Burst DMA 访问共享 SRAM，
4x4 systolic array 完成 INT8 矩阵乘，支持 PE mask、DFS 和空闲时钟门控。
RTL 自检回归全部通过，功能覆盖模型和路径覆盖模型均为 100%，峰值指标为
1.024 TOPS@INT8，DMA Burst 利用率 85%，并完成 KC705 Vivado/ILA 验证流程。
