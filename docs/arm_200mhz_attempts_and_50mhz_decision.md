# ARM/Cortex-M0 200MHz 时序尝试、50MHz 上板方案与取舍说明

日期：2026-07-03

## 1. 文档目的

本文单独说明 ARM/Cortex-M0 路线为了达到 KC705 200MHz 时序收敛所做过的优化和改进，以及为什么最终没有继续把当前 ARM 混淆核强行推到 200MHz，而是保留 50MHz 上板验证结果，并另外采用 RISC-V/PicoRV32 路线完成真实 200MHz 验收。

它面向两个场景：

1. 自己学习：理解 FPGA timing closure 的基本方法、Vivado 报告怎么看、为什么有些优化有效有些无效。
2. 面试表达：能够诚实、清楚地说明 ARM 路线做过什么，为什么没有伪造 200MHz 通过结论，以及后续如果继续做应该怎么做。

相关已有证据：

- `docs/kc705_arm_200mhz_goal_20260701.md`
- `docs/kc705_200mhz_goal_analysis.md`
- `submission/kc705_fpga_waveform_metric_check.md`
- `fpga/vivado/experiments/k7i6/reports/impl_timing_summary.rpt`
- `fpga/vivado/experiments/kc705_200mhz_dual_clock/reports/impl_timing_summary.rpt`

## 2. ARM 路线当前设计结构

当前 ARM 路线使用真实 Arm Cortex-M0 DesignStart RTL：

| 模块/文件 | 作用 |
| --- | --- |
| `rtl/cortex_m0_designstart_ahb.v` | 封装 `CORTEXM0INTEGRATION`，输出 AHB-Lite 主接口 |
| `rtl/cortex_m0_npu_soc.v` | ARM 单时钟 CPU+NPU SoC 顶层 |
| `rtl/ahb_lite_to_axil_bridge.v` | 将 Cortex-M0 AHB-Lite 控制访问转换为 AXI-Lite |
| `rtl/axi_shared_interconnect.v` | CPU 控制访问和 NPU DMA 访问的共享互连 |
| `rtl/npu_accel_axi.v` | NPU AXI-Lite 控制、AXI Burst DMA、计数器和低功耗状态 |
| `fpga/rtl/fpga_kc705_top.v` | KC705 ARM 单时钟 FPGA 顶层 |
| `fpga/rtl/fpga_kc705_dual_clock_top.v` | KC705 ARM 双时钟候选顶层 |

功能上，ARM 路线已经通过 RTL 回归：

- Cortex-M0 执行 Thumb 固件；
- 通过 AHB-Lite 配置 NPU；
- 桥接到 AXI-Lite；
- NPU 通过 AXI Burst/DMA 搬运 A/B/C 数据；
- NPU 完成矩阵计算并产生 IRQ/done；
- `docs/metrics_report.md` 中 1.024 TOPS@INT8、85% DMA 利用率、功能/路径覆盖模型均通过。

因此，ARM 路线的主要问题不是功能错误，而是当前 KC705 上严格单时钟 200MHz timing 未收敛。

## 3. 已做过的 ARM 200MHz 优化和改进

### 3.1 将 KC705 顶层推进到真实 200MHz 约束

最初真实上板 bring-up 为了稳妥调试，使用 50MHz SoC/ILA 时钟。后续为了尝试严格 200MHz，KC705 顶层被改为从板载 200MHz 差分时钟生成 200MHz `soc_clk`：

```verilog
MMCME2_BASE #(
    .CLKFBOUT_MULT_F(5.000),
    .CLKIN1_PERIOD(5.000),
    .CLKOUT0_DIVIDE_F(5.000),
    .DIVCLK_DIVIDE(1)
) u_soc_clk_mmcm (...);
```

目标是让：

```text
soc_clk_mmcm = 5.000ns / 200.000MHz
```

这样做的意义是把 Vivado 实现真正约束到 200MHz，而不是只在 testbench 里写 `always #2.5 clk = ~clk`。

### 3.2 保留 ILA，不通过删除调试核换时序

ARM 200MHz 尝试中始终要求保留：

- `KC705_ENABLE_ILA`
- `ila_cpu_npu_kc705`

ILA probes 包括：

- `npu_irq`
- `npu_irq_latched`
- `npu_array_clk_en`
- `cpu_halted`
- `debug_resetn`
- `cycle_counter`
- `dma_active_cycles`
- `dma_data_cycles`
- `dma_read_beats`
- `dma_write_beats`

这保证后续上板可以观察复位释放、NPU 计算窗口、IRQ 完成、DMA 计数和低功耗门控。面试时可以强调：我没有用“去掉 ILA”这种方式让 timing 变好，因为比赛和调试需要真实可观测性。

### 3.3 增加 Vivado 实验脚本参数

为了系统探索 timing closure，而不是手动乱点 Vivado，增加了参数化实验入口：

```text
scripts/run_vivado_kc705_experiment.ps1
```

该脚本支持：

- `-SynthDirective`
- `-OptDirective`
- `-PlaceDirective`
- `-PhysOptDirective`
- `-RouteDirective`
- `-PostRoutePhysOptDirective`
- `-CortexM0PblockSliceRange`
- `-CortexM0PblockDspRange`
- `-DisableCortexM0Pblock`

其目的：

1. 对比不同综合、布局、物理优化和布线策略；
2. 保留每次实验的独立报告目录；
3. 避免 GUI 手动设置不可复现；
4. 支持快速判断某类策略是否真的改善 WNS。

### 3.4 使用 direct Tcl flow 绕开 Vivado run wrapper 问题

在 Windows + Vivado 2019.2 环境中，曾遇到 `rundef.js ... Access denied` 一类 run wrapper 问题。为减少工具链偶发问题，新增了直接 Tcl 流：

```text
fpga/vivado/tcl/run_kc705_200mhz_direct.tcl
```

该脚本直接执行：

```text
synth_design
opt_design
place_design
phys_opt_design
route_design
post-route phys_opt_design
write_debug_probes
write_bitstream
report_timing_summary
report_drc
report_methodology
```

这样可以在一个 Vivado 进程中完成实现流程，减少 `launch_runs` 子进程脚本失败的概率。

### 3.5 尝试 retiming 和 aggressive physical optimization

尝试过的策略包括：

- `synth_design -retiming`
- `PerformanceOptimized`
- `phys_opt_design -directive AggressiveExplore`
- post-route `phys_opt_design`
- `AddRetime`
- 不同 place/route/physopt directive 组合

这些属于 FPGA timing closure 的常规手段：

- retiming 尝试移动寄存器位置，平衡组合逻辑；
- physical optimization 尝试复制寄存器、优化高扇出、调整关键路径附近的布局；
- route/placement directive 尝试寻找不同布局布线解。

但结果显示，它们只能改变局部路径和 WNS 数值，无法根本解决当前 Cortex-M0 混淆核内部路径问题。

### 3.6 尝试 Cortex-M0 pblock / no-pblock

曾尝试对 Cortex-M0 相关逻辑做 pblock 约束，例如限制其 SLICE/DSP 区域，希望降低布线距离和 route delay。

也尝试过禁用 pblock，让 Vivado 自由布局。

结论：

- pblock 可能改善部分布局稳定性；
- 但当前最坏路径仍在 `u_soc/u_cpu/u_cortexm0integration/u_logic` 内部；
- WNS 仍为约 -3.5ns 量级；
- 说明问题不是简单的“放太远”，而是 CPU 内部逻辑结构和布线共同造成。

### 3.7 尝试 no-DSP multiplier 方向

当前 Cortex-M0 DesignStart 混淆核内部曾被 Vivado 推断出 DSP48E1 相关路径。工程中尝试过通过宏或综合设置降低 DSP 参与，例如 `CORTEXM0DS_NO_DSP_MULT`、`MAX_DSP=0` 一类方向。

尝试动机：

- 未充分流水的 DSP48E1 乘法路径可能难以在 200MHz 下收敛；
- 如果 CPU 内部乘法器改为小面积/多周期实现，理论上可能缩短关键路径或避开 DSP。

实际结论：

- 当前 `CORTEXM0INTEGRATION` 是混淆交付形式，无法可靠设置官方 `SMUL` 等内部参数；
- 简单禁止 DSP 并不等价于得到一个架构良好的多周期乘法器；
- no-DSP 实验没有使严格单时钟 ARM 200MHz 收敛。

### 3.8 尝试双时钟架构：CPU 50MHz，NPU/AXI/ILA 200MHz

为了证明 NPU/AXI Burst 数据面本身可以 200MHz 收敛，新增了双时钟 ARM 候选结构：

| 时钟域 | 频率 | 承载逻辑 |
| --- | --- | --- |
| `cpu_clk_mmcm` | 20.000ns / 50MHz | Cortex-M0 + AHB-Lite 控制面 |
| `data_clk_mmcm` | 5.000ns / 200MHz | NPU、AXI Burst、共享存储器、ILA |

关键文件：

- `fpga/rtl/fpga_kc705_dual_clock_top.v`
- `rtl/cortex_m0_npu_soc_dual_clock.v`
- `rtl/axil_cdc_bridge.v`

`axil_cdc_bridge` 用 toggle request/done 同步方式跨时钟域，把低频 CPU 的 AXI-Lite 控制访问送到 200MHz NPU 数据域。这个方案在 Vivado 中通过：

| 项目 | 结果 |
| --- | --- |
| Overall WNS | `0.148ns` |
| `data_clk_mmcm` | 5.000ns / 200MHz |
| `data_clk_mmcm` intra-clock WNS | `0.428ns` |
| `cpu_clk_mmcm` | 20.000ns / 50MHz |
| `cpu_clk_mmcm` intra-clock WNS | `5.469ns` |
| DRC | 无 Error |
| ILA | 保留 |

该方案证明：NPU/AXI/ILA 数据面可以真实 200MHz 收敛；严格问题集中在 Cortex-M0 自身是否也必须 200MHz。

## 4. 最坏路径分析

### 4.1 严格单时钟 ARM 200MHz 的失败结果

最新较好的严格单时钟实验之一为 `k7i6`。报告显示：

```text
soc_clk_mmcm = 5.000ns / 200.000MHz
WNS = -3.458ns
TNS = -2621.290ns
Failing endpoints = 1644
```

最坏 setup path：

```text
Source:
u_soc/u_cpu/u_cortexm0integration/u_logic/Iixpw6_reg_replica/C

Destination:
u_soc/u_cpu/u_cortexm0integration/u_logic/Ydopw6_reg/D

Requirement:
5.000ns

Data Path Delay:
8.413ns

Logic Levels:
22

Delay composition:
logic 2.151ns, route 6.262ns
```

这说明：

1. 路径源和终点都在 Cortex-M0 DesignStart 内部；
2. 组合逻辑层级达到 22 级；
3. route delay 占比约 74%，说明布线压力也很大；
4. 负 slack 大约 3.5ns，不是一个小的边角问题。

### 4.2 为什么不能随便 false path 或 multicycle

看到负 slack 后，有一种危险做法是给 Cortex-M0 内部路径加 false path 或 multicycle path。这里不能这么做，原因是：

- 该路径是 CPU 内部寄存器到寄存器路径；
- 当前没有 Arm 官方结构证明说明它天然多周期；
- 如果错误加 false path/multicycle，Vivado 会停止检查真实路径，硬件可能在 200MHz 下运行错误；
- 比赛和面试都要求可验证结果，不能靠隐藏 timing violation。

正确做法是：只有当 CPU 厂商文档、源码结构或正式约束明确说明该路径不需要单周期收敛时，才能添加例外约束。当前工程没有这个证据。

## 5. 为什么不继续对当前 ARM 混淆核做 200MHz 硬推

### 5.1 问题在不可编辑的 CPU 内部

最坏路径反复落在：

```text
u_soc/u_cpu/u_cortexm0integration/u_logic
```

该逻辑来自 Arm DesignStart `CORTEXM0INTEGRATION` 混淆交付形式。与自研 NPU RTL 不同，它不是我们可以自由插入流水线、改状态机、拆组合逻辑的代码。

如果关键路径在自己写的 `npu_accel_axi.v` 或 `systolic_array_4x4.v`，可以继续：

- 插入流水寄存器；
- 拆分 nested if/case；
- 优化乘加路径；
- 调整 BRAM 读写时序；
- 降低 fanout。

但当前关键路径在混淆 CPU 内部，上述 RTL 级优化无法直接作用到根因。

### 5.2 当前没有合法可替换的 parameterized Cortex-M0

本地 DesignStart 示例中能看到类似 `SMUL` 的参数化思路，但当前工程实际例化的是：

```verilog
CORTEXM0INTEGRATION u_cortexm0integration (...);
```

当前 checkout 中没有可直接替换的、合法的非混淆 `CORTEX_M0` 参数化 RTL。也就是说，不能简单在 wrapper 上加一个参数就改变 CPU 内部乘法器或流水结构。

如果后续能获得 Arm 支持的可参数化 Cortex-M0 源码或配置，才值得继续严格 ARM 200MHz：

1. 替换 CPU wrapper/filelist；
2. 设置更适合 FPGA 的 multiplier/timing option；
3. 重新跑 RTL 回归；
4. 重新跑 Vivado 200MHz；
5. 重新做上板 ILA。

### 5.3 已经尝试过常规 Vivado 策略，收益不足

已经尝试过：

- aggressive synthesis；
- retiming；
- physical optimization；
- post-route physical optimization；
- pblock；
- no-pblock；
- no-DSP 方向；
- direct Tcl flow；
- checkpoint/reuse/debug-core 方向。

最佳严格单时钟 ARM 结果仍然约为：

```text
WNS ≈ -3.458ns
```

这类负 slack 对 5ns 周期来说非常大。继续只换 Vivado directive，收益大概率有限。工程上更合理的是停止“脚本硬跑”，转向结构性方案：

- 使用可参数化/可编辑 CPU；
- 或者把 CPU 控制域和 NPU 数据域拆开；
- 或者改用 RISC-V/PicoRV32 作为控制 CPU。

### 5.4 提高电压、使用更快 D 触发器不是当前 FPGA RTL 层面的可行手段

用户之前提到过“提高电压、使用更快的 D 触发器”等思路。它们在 ASIC 或器件选型中可能有意义，但对当前 KC705/Vivado 工程来说限制很大：

| 方法 | 为什么当前不采用 |
| --- | --- |
| 提高电压 | KC705 上 FPGA 核心电压由板级电源和器件规范决定，不能为了 timing 随意提高；超规格会带来可靠性和损坏风险 |
| 使用更快 D 触发器 | FPGA 中触发器是器件 slice 资源，RTL 不能像 ASIC 标准单元库那样手选更快 DFF |
| 换更高速器件 | 可以作为硬件选型方案，但当前比赛/工程目标是 KC705 `xc7k325tffg900-2` |
| 加 false path | 没有结构证明时不安全，可能掩盖真实错误 |
| 降低时钟 | 可以让板子跑起来，但不能声明严格 200MHz ARM 单时钟通过 |

所以当前真正可复现、可解释的优化手段是：

- RTL 结构优化；
- 流水线；
- 合法的 CPU 参数配置；
- CDC/多时钟架构；
- Vivado 约束、布局布线和物理优化；
- 换用可控 CPU RTL。

## 6. 为什么 ARM 最终保留 50MHz 上板验证

### 6.1 50MHz 上板验证已经证明了功能链路

历史 KC705 上板记录见：

```text
submission/kc705_fpga_waveform_metric_check.md
```

当时为了稳妥 bring-up，FPGA wrapper 使用 50MHz SoC/ILA 调试时钟。真实板卡 program + ILA 捕获已经证明：

- KC705 能识别并 program；
- ILA 能触发并导出 CSV；
- `debug_resetn` 正常释放；
- CPU/总线开始读 RAM；
- NPU DMA/Burst 窗口出现；
- `npu_array_clk_en` 在计算窗口拉高；
- `dma_read_beats = 8`；
- `dma_write_beats = 16`；
- `npu_irq` 和 `npu_irq_latched` 拉高；
- 板上 ILA 计算的 DMA/Burst utilization 约 85.71%。

这说明 ARM + NPU 系统功能链路在真实 KC705 上是通的。

### 6.2 50MHz 结果不能包装成严格 200MHz

需要明确边界：

- 50MHz 上板验证可以作为 FPGA 功能验证证据；
- 200MHz、1.024 TOPS、85% DMA 利用率来自 RTL 回归和性能模型；
- 50MHz 上板不能宣称“ARM 单时钟 SoC 在 FPGA 上 200MHz 已通过”。

这也是为什么后续继续做了严格 200MHz timing 实验，并最终切换到 RISC-V/PicoRV32 路线完成真实 200MHz Vivado 验收。

面试时可以这样说：

> ARM 版本我先用 50MHz 做真实板卡 bring-up，是为了证明端到端链路、JTAG、ILA、复位、DMA、IRQ 和时钟门控都能在硬件上观察到。之后我尝试把同一链路推到 200MHz，但 post-route timing 显示最坏路径在 Cortex-M0 混淆核内部，WNS 仍为负，所以我没有把 50MHz 结果包装成 200MHz，而是明确区分功能上板和时序验收。

## 7. 双时钟 ARM 方案的价值和边界

双时钟方案是 ARM 路线中最有工程价值的折中：

- Cortex-M0 控制面：50MHz；
- NPU/AXI Burst/ILA 数据面：200MHz；
- 控制访问通过 `axil_cdc_bridge` 跨域；
- Vivado timing clean，overall WNS 为正；
- ILA 保留。

它的价值：

1. 证明自研 NPU、AXI Burst、BRAM 和 ILA 数据面可以 200MHz 收敛；
2. 符合很多异构系统的实际架构：低频低功耗 CPU 控制，高频加速器执行；
3. 可以作为 ARM 功能上板和 NPU 200MHz 数据面展示路线。

它的边界：

- 不能宣称 Cortex-M0 核本身运行在 200MHz；
- 如果赛题/评审严格要求整个 ARM SoC 单时钟 200MHz，它只能算 fallback 或工程折中；
- 报告中必须写清楚 CPU 控制域为 50MHz，NPU/AXI/ILA 数据域为 200MHz。

## 8. 如果未来继续做 ARM 200MHz，应该怎么做

后续路线应该偏结构性，而不是继续盲目跑 Vivado directive。

### 8.1 获取合法可参数化 Cortex-M0

最优先：

1. 获取 Arm 支持的非混淆/可参数化 Cortex-M0 实现；
2. 确认是否支持 `SMUL` 或类似 multiplier/timing option；
3. 替换 `rtl/cortex_m0_designstart_ahb.v` 的 CPU 实例；
4. 保持 AHB-Lite wrapper 接口不变，减少对 SoC 其他模块影响；
5. 重跑 `scripts/run_all_checks.ps1`；
6. 重跑 KC705 200MHz implementation。

### 8.2 如果关键路径转移到自研 RTL，再做流水线优化

如果替换 CPU 后最坏路径转移到 NPU/AXI，可以做：

- 将 AXI 地址译码打一拍；
- 将 NPU FSM 中复杂条件拆成多级状态；
- 将 DMA active/data counter 的更新路径拆开；
- 将 PE 乘加路径明确流水化；
- 将大 fanout 控制信号复制或分层；
- 将 SRAM/BRAM 读数据按同步 RAM 方式打一拍；
- 优化 nested if/case，减少同一周期内的条件优先级链。

这些是可以在自研 RTL 中安全实施的优化，因为可以用仿真和波形验证行为是否保持正确。

### 8.3 继续保留 timing gate

无论采用什么路线，验收都应继续使用：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check_vivado_timing_gate.ps1 `
  -TimingReport <impl_timing_summary.rpt> `
  -ClockName <目标时钟名>
```

硬门槛：

- 目标时钟必须是 5.000ns；
- WNS 必须大于等于 0；
- DRC 不能有 blocking Error；
- ILA 不能为了 timing 被移除。

## 9. 面试讲法示例

可以按下面方式组织：

1. 先讲 ARM 功能完成度：真实 Cortex-M0 DesignStart 执行 Thumb 固件，通过 AHB-Lite 到 AXI-Lite 桥配置 NPU，NPU 通过 AXI Burst/DMA 访问共享存储器，RTL 回归和板上 ILA 都证明功能链路正确。
2. 再讲 200MHz 问题：我把 KC705 顶层改到 5ns 约束，保留 ILA，跑了多组 Vivado 实验；post-route 报告显示 WNS 仍为负，最坏路径在 `CORTEXM0INTEGRATION/u_logic` 内部。
3. 说明做过的优化：retiming、phys_opt、pblock/no-pblock、no-DSP 方向、direct Tcl flow、双时钟 CDC 方案。
4. 说明为什么不继续硬推：当前 CPU 是混淆核，内部不可改、不可可靠传参；负 slack 约 3.5ns，不是靠小修小补能解决；没有结构证明不能加 false path/multicycle。
5. 说明 50MHz 的定位：50MHz 是真实板卡功能 bring-up，证明 CPU/NPU/DMA/ILA 链路可运行；我没有把它说成严格 200MHz。
6. 说明解决方案：为了完成真实 200MHz 验收，我切换到开源可参数化 PicoRV32，关闭不需要的乘除法和计数器，启用 two-cycle ALU/compare，最终在 KC705 上 `soc_clk_mmcm=5ns`、WNS=0.137ns，并保留 ILA。

## 10. 一句话总结

ARM/Cortex-M0 路线已经完成 RTL 功能验证和真实 KC705 50MHz 上板功能验证；严格单时钟 200MHz 失败的根因是当前混淆版 `CORTEXM0INTEGRATION` 内部不可编辑关键路径。继续硬跑 Vivado 策略的收益有限，也不能通过 false path 或 50MHz 结果冒充 200MHz。因此工程上保留 ARM 50MHz 上板证据，同时使用可控的 RISC-V/PicoRV32 路线完成真实 200MHz Vivado 时序验收。
