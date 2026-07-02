# CPU + NPU 异构处理器验证项目

Committer：刘马均
> 面向 CPU + NPU 异构处理器的验证展示项目。
> 本仓库主要用于作品集、实习/校招网申和项目经历展示。仓库中的 RTL 是用于展示验证流程的
> 已验证快照，不声明为最新设计分支；项目重点是展示 UVM、DPI-C、AXI 和回归验证能力。

## 项目亮点

- 针对 `npu_core_4x4` 和 `npu_accel_axi` 搭建了模块级 UVM 验证环境。
- 集成 DPI-C C++ golden model，用于 signed INT8 4x4 矩阵乘法、INT32 累加和运行时
  `PE_MASK` 输出屏蔽校验。
- 使用可复用的 AXI memory slave BFM 验证 AXI-Lite 寄存器控制，以及 AXI4 master DMA
  读写访问。
- 保留原有 VS Code + Icarus Verilog 回归流程，用于快速 RTL smoke test。
- 当前已完成的本地 UVM smoke test 使用 QuestaSim 10.7c 跑通，结果为 `UVM_ERROR : 0`；
  验证平台结构保持 simulator-agnostic，可迁移到 VCS 或 Vivado Simulator/XSIM。

## 本项目展示的能力

本项目重点展示验证架构设计和验证闭环执行能力：

| 方向 | 对应证据 |
| --- | --- |
| UVM 验证架构 | `uvm_tb/` 中的 env、agent、sequence、scoreboard |
| DPI-C 联合仿真 | `uvm_tb/c_model/npu_golden_model.cpp` |
| AXI 协议验证 | AXI-Lite config agent 和 AXI memory slave BFM |
| 算法级比对 | Scoreboard 将 RTL 输出与 C++ golden model 结果进行比对 |
| 自动化回归 | `uvm_tb/sim/run.ps1`、`scripts/run_all_checks.ps1` |
| 验证文档 | `docs/uvm_verification_plan.md`、`docs/simulation_report.md`、`docs/metrics_report.md` |

## 被测架构

```text
CPU / AXI-Lite 控制
        |
        v
 npu_accel_axi
   |        |
   |        +-- AXI4 master DMA 读取 A/B 矩阵并写回 C 矩阵
   v
 npu_core_4x4
   |
   +-- 4x4 signed INT8 systolic array，INT32 累加
```

UVM 平台覆盖两个验证层级：

1. **Core direct verification**：直接驱动 `start`、`a_matrix`、`b_matrix`、
   `pe_mask` 和 `dfs_divider`，对 `npu_core_4x4` 进行矩阵计算功能验证。
2. **Accelerator verification**：通过 AXI-Lite 配置 `npu_accel_axi`，由 AXI memory BFM
   提供 A/B 矩阵数据，捕获 C 矩阵写回结果，并复用同一套 DPI-C golden model 进行比对。

## 仓库结构

```text
rtl/                 用于验证展示的 RTL 快照
tb/                  轻量级自检查 Verilog testbench
uvm_tb/
  agent/             UVM core、AXI-Lite 和 AXI memory agent
  env/               Environment、scoreboard、test
  seq/               Core corner sequence 和 accelerator sequence
  c_model/           DPI-C C++ golden model 与自测试
  sim/               Questa/Icarus 运行脚本和可迁移的 UVM filelist
docs/                验证计划、仿真报告和指标报告
scripts/             Icarus 回归与报告生成脚本
submission/          比赛/评审风格的设计、RTL 和仿真说明文档
```

## 快速开始

### 1. 运行当前已验证的 Questa UVM Smoke Test

脚本默认使用的 Questa 路径：

```text
E:\Application\questasim64_10.7c
```

运行命令：

```powershell
powershell -ExecutionPolicy Bypass -File uvm_tb\sim\run.ps1 -Mode questa -Test npu_smoke_test
```

预期关键结果：

```text
[CORE_PASS] 7
[ACCEL_PASS] 1
UVM_ERROR : 0
```

### 2. 运行 Open-Source Smoke Test

需要安装 Icarus Verilog 和 MinGW `g++`：

```powershell
powershell -ExecutionPolicy Bypass -File uvm_tb\sim\run.ps1 -Mode smoke
```

该命令会依次运行：

- C++ golden model 自测试
- `tb_npu_core_4x4`
- `tb_axi_burst_dma`
- `tb_hetero_soc`
- `tb_npu_stress`

### 3. 运行完整本地回归

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_all_checks.ps1
```

完整 Cortex-M0 测试路径需要本地具备 Arm Cortex-M0 DesignStart evaluation package。
该授权包受许可限制，不包含在公开展示仓库中。

ARM Cortex-M0 RTL源码下载地址：https://www.arm.com/resources/free-evaluation-arm-cpus

## 商业仿真器支持

本项目的 UVM 验证平台采用 simulator-agnostic 结构设计，核心 testbench、agent、sequence、
scoreboard 和 DPI-C golden model 不绑定特定厂商仿真器。

当前已在本地完成验证的环境：

- QuestaSim 10.7c：UVM smoke test 通过，`UVM_ERROR : 0`

面向 ASIC/FPGA 工程复现时，推荐迁移到以下商业仿真器：

- Synopsys VCS：适合标准 UVM 回归、DPI-C 联合仿真和覆盖率收集
- Vivado Simulator / XSIM：适合 Xilinx FPGA RTL smoke test 和 Vivado 工程联动
- Questa Advanced Simulator：适合已有 Siemens EDA 授权环境下复现

说明：README 中的 QuestaSim 结果表示本项目已完成的本地验证证据；VCS 支持作为工程迁移目标保留，
不在未实际跑通前声明为已验证结果。

## 已验证结果

最近一次本地验证结果：

```text
QuestaSim 10.7c UVM:
  CORE_PASS: 7
  ACCEL_PASS: 1
  UVM_ERROR: 0

Icarus regression:
  PASS tb_npu_core_4x4
  PASS tb_axi_burst_dma
  PASS tb_hetero_soc
  PASS tb_npu_stress
  PASS tb_cortex_m0_cpu_npu
  Functional coverage score: 100%
  Code path coverage score: 100%
  DMA data utilization: 85%
  Peak INT8 metric: 1024 MTOPS = 1.024 TOPS
  MNIST INT8 accuracy: 82.01%
```

## 关键验证文件

- UVM top: `uvm_tb/tb/npu_uvm_top.sv`
- UVM package: `uvm_tb/npu_uvm_pkg.sv`
- AXI memory BFM: `uvm_tb/agent/axi_mem_slave_agent.svh`
- Scoreboard: `uvm_tb/env/npu_scoreboard.svh`
- Accelerator sequence: `uvm_tb/seq/npu_accel_sequences.svh`
- DPI-C golden model: `uvm_tb/c_model/npu_golden_model.cpp`
- Run script: `uvm_tb/sim/run.ps1`
- Verification plan: `docs/uvm_verification_plan.md`

## 给评审/面试官的说明

- 本仓库是验证展示项目，不是最新 RTL 设计分支。
- 自动生成的仿真输出、波形文件、商业仿真器 work library、数据集以及受许可限制的 Arm
  官方包均未纳入版本管理。
- UVM smoke test 不依赖授权版 Cortex-M0 package；完整本地 SoC 回归会依赖该授权包。
