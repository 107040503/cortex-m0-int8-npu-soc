# RISC-V/PicoRV32 200MHz 时序收敛方法与优化说明

日期：2026-07-03

## 1. 文档目的

本文单独说明当前工程切换到 RISC-V/PicoRV32 后，为了在 KC705 上达到真实 200MHz Vivado 实现验收所采用的方法、代码改动和工程取舍。它面向两个场景：

1. 自己复盘：理解为什么 RISC-V 路线比当前 ARM/Cortex-M0 路线更容易收敛到 200MHz。
2. 面试表达：能够清楚说明自己做了哪些 RTL、约束、脚本和验证层面的工作，而不是只说“换了一个 CPU”。

当前已验证结果见：

- `docs/kc705_riscv_200mhz_result_20260703.md`
- `docs/riscv_metrics_report.md`
- `fpga/vivado/experiments/kc705_riscv_200mhz/reports/impl_timing_summary.rpt`

## 2. 结论摘要

RISC-V/PicoRV32 路线已经完成当前阶段 200MHz 验收：

| 项目 | 结果 |
| --- | --- |
| RTL 仿真频率 | 5ns 周期，即 200MHz |
| CPU/NPU 协同 | PicoRV32 执行 RV32I 固件，配置并轮询 NPU |
| NPU 峰值指标 | 1024 MTOPS = 1.024 TOPS@INT8 |
| AXI Burst/DMA 利用率 | 85%，高于 80% |
| 功能覆盖模型 | 27/27 = 100% |
| 路径覆盖模型 | 55/55 = 100% |
| Vivado 时钟 | `soc_clk_mmcm = 5.000ns / 200.000MHz` |
| Vivado WNS | `0.137ns`，满足 `WNS >= 0` |
| DRC | 0 Error，0 Critical Warning |
| ILA | 保留，已生成 `.ltx` 探针文件 |

关键点是：RISC-V 路线不是削弱 NPU 性能来换 timing，而是保留原有 4x4 INT8 NPU、AXI Burst/DMA、计数器和 ILA 观测路径，同时把 CPU 控制侧替换为更可控、更轻量、可参数化的 PicoRV32。

## 3. 主要新增与修改文件

| 文件 | 作用 |
| --- | --- |
| `rtl/picorv32_npu_soc.v` | RISC-V/PicoRV32 + NPU SoC 集成顶层 |
| `third_party/picorv32/picorv32.v` | PicoRV32 开源 CPU RTL |
| `fpga/rtl/fpga_kc705_riscv_top.v` | KC705 RISC-V FPGA 顶层，生成 200MHz `soc_clk` 并接入 ILA |
| `fpga/vivado/mem/picorv32_npu_demo.mem` | RV32I 固件初始化镜像 |
| `fpga/vivado/tcl/run_kc705_riscv_200mhz_direct.tcl` | Vivado 直接流脚本，综合、实现、bitstream、LTX 和报告一次完成 |
| `scripts/run_vivado_kc705_riscv_experiment.ps1` | PowerShell 入口，调用 Vivado RISC-V 200MHz 直接流 |
| `tb/tb_picorv32_cpu_npu.v` | RISC-V CPU+NPU 端到端自检 testbench |
| `scripts/gen_riscv_metrics_report.ps1` | 生成 RISC-V 指标报告 |
| `docs/kc705_riscv_200mhz_result_20260703.md` | 当前 RISC-V 200MHz 验收记录 |

## 4. 方法一：选择可控、轻量、开源的 PicoRV32 CPU

### 4.1 为什么 PicoRV32 对时序更友好

当前 ARM 路线使用 Arm DesignStart `CORTEXM0INTEGRATION` 混淆交付形式，CPU 内部逻辑不可改、不可可靠传参，最坏路径也落在 CPU 内部。相比之下，PicoRV32 有几个工程优势：

- RTL 源码可见，综合器能更充分优化。
- 参数可控，可以关闭不需要的长路径功能。
- 自带 AXI 接口，能直接接入 AXI interconnect，减少 AHB-Lite 到 AXI-Lite 桥接层带来的控制路径复杂度。
- 作为控制 CPU 足够轻量，当前任务只需要配置寄存器、传递 A/B/C 地址、轮询 done/IRQ，不需要 CPU 自己做矩阵乘法。

这符合异构处理器的设计思想：CPU 负责控制，NPU 负责高吞吐矩阵计算。CPU 不应成为 200MHz 数据面时序的主要负担。

### 4.2 实际采用的 PicoRV32 参数

在 `rtl/picorv32_npu_soc.v` 中，PicoRV32 例化参数如下：

```verilog
picorv32_axi #(
    .ENABLE_COUNTERS(0),
    .ENABLE_COUNTERS64(0),
    .TWO_CYCLE_COMPARE(1),
    .TWO_CYCLE_ALU(1),
    .ENABLE_MUL(0),
    .ENABLE_FAST_MUL(0),
    .ENABLE_DIV(0),
    .ENABLE_IRQ(1),
    .ENABLE_IRQ_TIMER(0),
    .PROGADDR_RESET(32'h0000_0000),
    .STACKADDR(32'h0000_4000)
) u_cpu (...);
```

这些参数的作用如下：

| 参数 | 优化目的 |
| --- | --- |
| `ENABLE_COUNTERS=0`、`ENABLE_COUNTERS64=0` | 关闭 CPU 内部 cycle/instret 等计数器，减少寄存器和加法链 |
| `TWO_CYCLE_COMPARE=1` | 把比较路径拆成两拍，降低单周期组合深度 |
| `TWO_CYCLE_ALU=1` | 把 ALU 路径拆成两拍，牺牲少量控制延迟换取更好 Fmax |
| `ENABLE_MUL=0`、`ENABLE_FAST_MUL=0` | 关闭 CPU 乘法器，避免引入 DSP 或长乘法组合路径 |
| `ENABLE_DIV=0` | 关闭除法器，避免长迭代或控制路径 |
| `ENABLE_IRQ=1` | 保留中断能力，满足 NPU done/IRQ 协同验证 |
| `ENABLE_IRQ_TIMER=0` | 关闭本任务不需要的 timer IRQ |

面试时可以这样讲：

> 我没有让 CPU 承担矩阵运算，所以不需要打开乘除法器。PicoRV32 只做 MMIO 配置和轮询，关闭乘除法、计数器，并启用 two-cycle ALU/compare，可以显著缩短 CPU 内部关键路径。NPU 的 1.024 TOPS 指标来自专用脉动阵列，不依赖 CPU 乘法器。

## 5. 方法二：减少总线适配层级，使用 AXI 原生控制路径

ARM 路线中，Cortex-M0 通过 AHB-Lite 发起访问，再由 `ahb_lite_to_axil_bridge` 转换为 AXI-Lite。这个设计在功能上正确，但增加了一个协议转换层。

RISC-V 路线中，`picorv32_axi` 直接输出 AXI 风格接口，再由 SoC 地址译码访问：

- 共享 SRAM/BRAM 取指和数据访问；
- NPU AXI-Lite 控制寄存器；
- NPU AXI Burst/DMA 数据面。

这样做的好处：

1. 逻辑层级减少，控制面组合路径更短。
2. CPU 到 NPU 的 MMIO 路径更直接，更利于综合优化。
3. 保留原有 NPU AXI Burst/DMA，不改变核心加速器性能路径。

这也是为什么 RISC-V 路线可以在保持 ILA 和 200MHz 时钟的情况下收敛，而不是依赖移除调试逻辑或降低频率。

## 6. 方法三：保持 NPU 数据面不降级

RISC-V 收敛不是通过减少 NPU 功能实现的。当前仍保留：

- `rtl/systolic_array_4x4.v`：4x4 INT8 脉动阵列；
- `rtl/npu_core_4x4.v`：NPU 计算控制；
- `rtl/npu_accel_axi.v`：AXI-Lite 寄存器、AXI Burst DMA、性能计数和低功耗状态；
- `rtl/axi_shared_interconnect.v`：CPU/NPU 到共享存储器的互连；
- `rtl/axi_bram.v`：FPGA 实现中使用的片上存储器路径。

仿真报告仍然显示：

- `INFO picorv32 peak mtops=1024`
- `INFO picorv32 DMA data utilization percent=85`
- `PASS tb_picorv32_cpu_npu`

这说明切换 CPU 没有破坏比赛要求中的 NPU 算力、AXI Burst 和 DMA 利用率指标。

## 7. 方法四：KC705 顶层明确生成真实 200MHz SoC/ILA 时钟

在 `fpga/rtl/fpga_kc705_riscv_top.v` 中，板载 200MHz 差分时钟进入 MMCM：

```verilog
MMCME2_BASE #(
    .CLKFBOUT_MULT_F(5.000),
    .CLKIN1_PERIOD(5.000),
    .CLKOUT0_DIVIDE_F(5.000),
    .DIVCLK_DIVIDE(1)
) u_soc_clk_mmcm (...);
```

时钟关系为：

```text
输入时钟：200MHz，周期 5ns
VCO：200MHz * 5 = 1000MHz
输出：1000MHz / 5 = 200MHz
```

输出 `soc_clk_mmcm` 经 BUFG 得到 `soc_clk`，同时驱动：

- `picorv32_npu_soc`
- debug 计数器
- ILA core

因此这次 Vivado 实现不是“仿真 200MHz、板上慢速”，而是 FPGA 实现报告中真实存在 `soc_clk_mmcm = 5.000ns / 200.000MHz`。

## 8. 方法五：保留 ILA，不靠移除调试核换取时序

RISC-V 顶层保留了 `KC705_ENABLE_ILA`：

```verilog
`ifdef KC705_ENABLE_ILA
    ila_cpu_npu_kc705 u_ila_cpu_npu (
        .clk    (soc_clk),
        .probe0 (npu_irq),
        .probe1 (npu_irq_latched),
        .probe2 (npu_array_clk_en),
        .probe3 (trap),
        .probe4 (debug_resetn),
        .probe5 (ram_write_beats),
        .probe6 (ram_read_beats),
        .probe7 (cycle_counter),
        .probe8 (dma_active_cycles),
        .probe9 (dma_data_cycles),
        .probe10(dma_read_beats),
        .probe11(dma_write_beats)
    );
`endif
```

已生成：

- `fpga/vivado/bitstreams/kc705_riscv_200mhz.bit`
- `fpga/vivado/bitstreams/kc705_riscv_200mhz.ltx`

LTX 中确认包含 `npu_irq`、`npu_array_clk_en`、`cycle_counter`、`dma_read_beats`、`dma_write_beats` 等探针。也就是说，200MHz 收敛结果保留了后续上板 ILA 捕获能力。

## 9. 方法六：使用 Vivado 直接流提高可复现性

RISC-V 实现使用：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_kc705_riscv_experiment.ps1 -Jobs 4 -ExperimentName kc705_riscv_200mhz
```

底层 Tcl 为：

```text
fpga/vivado/tcl/run_kc705_riscv_200mhz_direct.tcl
```

该脚本完成：

1. 创建 KC705 工程；
2. 设置 `xc7k325tffg900-2` 和 `xilinx.com:kc705:part0:1.6`；
3. 读取 RISC-V SoC、NPU、AXI、BRAM 和 PicoRV32 RTL；
4. 定义 `FPGA_USE_AXI_BRAM FPGA_SYNTH_BRAM KC705_ENABLE_ILA`；
5. 创建 12 probe ILA；
6. 执行 `synth_design`、`opt_design`、`place_design`、`phys_opt_design`、`route_design`、post-route `phys_opt_design`；
7. 导出 bitstream、LTX、timing、DRC、utilization、power 和 methodology 报告。

这样做比依赖 GUI 手动点击更适合工程复现，也避免了之前 Windows/Vivado 2019.2 中 `launch_runs` 生成脚本偶发 `rundef.js ... Access denied` 的问题。

## 10. 方法七：用 timing gate 脚本做硬验收

实现完成后使用：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check_vivado_timing_gate.ps1 `
  -TimingReport fpga\vivado\experiments\kc705_riscv_200mhz\reports\impl_timing_summary.rpt `
  -ClockName soc_clk_mmcm
```

输出：

```text
Clock soc_clk_mmcm: period=5.000 ns, frequency=200.000 MHz
Overall WNS: 0.137 ns
Timing gate passed.
```

这个脚本的意义是把验收标准固定下来：

- 必须找到指定时钟；
- 周期必须是 5.000ns；
- WNS 必须大于等于 0；
- 不能只看 Vivado 是否生成 bitstream。

面试时可以强调：

> 我把 timing signoff 做成了脚本化 gate，而不是凭主观判断。生成 bitstream 不等于时序通过，只有 post-route timing summary 里目标时钟周期正确且 WNS 非负，才算 200MHz 实现通过。

## 11. 为什么这些优化能帮助 200MHz 收敛

### 11.1 缩短 CPU 内部关键路径

关闭乘除法、计数器，并启用 two-cycle ALU/compare，本质上是在减少 CPU 内部单周期组合逻辑深度。200MHz 的周期只有 5ns，寄存器到寄存器路径必须在 5ns 内完成：

```text
Tclk >= Tco + Tlogic + Troute + Tsetup + Tskew/uncertainty
```

如果 ALU、比较器、乘法器、计数器都放在一个周期内，`Tlogic + Troute` 很容易超过 5ns。把复杂运算拆到两拍，等价于在关键路径中插入流水寄存器，降低每拍的组合逻辑压力。

### 11.2 避免在 CPU 控制面引入 DSP 路径

当前任务的高性能计算在 NPU 中完成，CPU 不需要乘法器。关闭 PicoRV32 乘法器后：

- 不会在 CPU 内部推断 DSP；
- 不会形成 CPU 乘法长路径；
- DSP 资源和时序压力留给真正需要的加速器数据面。

### 11.3 减少协议桥接路径

AHB-Lite 到 AXI-Lite 桥接在 ARM 路线里是必要的，因为 Cortex-M0 输出 AHB-Lite。但 RISC-V/PicoRV32 可以直接使用 AXI 接口，减少协议转换逻辑。少一层桥接，就少一组地址、数据、ready/valid、状态机路径。

### 11.4 保持调试和真实约束

很多 FPGA 设计可以通过移除 ILA、降低时钟、放松约束临时得到更好的 WNS，但这种结果不能支撑比赛或面试。当前 RISC-V 路线保持：

- ILA 存在；
- `soc_clk_mmcm` 为 5ns；
- post-route WNS 非负；
- DRC 无阻塞错误。

因此它是可解释、可复现的工程结果。

## 12. 与 ARM 路线的本质差异

| 对比项 | ARM/Cortex-M0 当前路线 | RISC-V/PicoRV32 路线 |
| --- | --- | --- |
| CPU RTL 可见性 | DesignStart 混淆交付，内部不可改 | 开源 RTL，可综合优化 |
| 参数控制 | 当前 wrapper 无法可靠设置 `SMUL` 等内部参数 | 可直接设置 ALU、compare、mul/div、counter 等参数 |
| 总线接口 | AHB-Lite，经桥转换到 AXI-Lite | PicoRV32 AXI 接口，路径更直接 |
| 最坏路径位置 | 多次落在 `CORTEXM0INTEGRATION/u_logic` 内部 | 已收敛，WNS 为正 |
| 200MHz 结果 | 严格单时钟 ARM 路线未收敛 | RISC-V 单时钟 SoC/ILA 200MHz 已通过 |

## 13. 面试讲法示例

可以按下面顺序讲：

1. 先说明目标：在 KC705 上验证 CPU+NPU 异构 SoC，要求 RTL 指标保持 1.024 TOPS@INT8、DMA 利用率 80% 以上，同时 Vivado 实现真实 200MHz。
2. 说明 ARM 路线的问题：Cortex-M0 DesignStart 混淆核内部路径在 5ns 约束下无法收敛，最坏路径落在 CPU 内部，不是我可编辑的 NPU RTL。
3. 说明 RISC-V 方案：使用开源 PicoRV32 替换控制 CPU，保留 NPU/AXI Burst/DMA 数据面。
4. 说明具体优化：关闭 PicoRV32 乘除法和计数器，启用 two-cycle ALU/compare，减少 CPU 控制面关键路径。
5. 说明验证：Icarus 回归 PASS，PicoRV32 固件真实配置 NPU，DMA 利用率 85%，峰值寄存器 1024 MTOPS；Vivado post-route `soc_clk_mmcm=5ns`，WNS=0.137ns，ILA 保留。
6. 强调工程边界：当前阶段没有做真实板卡 program，这是按任务要求暂不执行；但 bitstream 和 LTX 已生成，下一步可以直接做 Hardware Manager program 和 ILA 捕获。

## 14. 后续可继续优化的方向

如果还要继续提高余量或做报告增强，可以考虑：

1. 给 RISC-V 路线补真实板卡 program + ILA 捕获。
2. 将 `REQP-1839` 这类 BRAM 异步控制 warning 做结构优化，提升报告质量。
3. 做更多 Vivado QoR 比较，例如不同 `phys_opt_design` directive 下的 WNS/资源变化。
4. 在文档中补充 RISC-V 固件流程图和 MMIO 寄存器访问序列。
5. 如果要追求更高频率，可以继续分析 RISC-V 路线的 post-route top 25 timing paths，再针对 fanout、BRAM、ILA trace memory 或 interconnect 做定点优化。
