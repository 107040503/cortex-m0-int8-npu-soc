# KC705 ARM Cortex-M0 + NPU 200MHz 目标分析

## 1. 范围与假设

- 当前只验证 ARM/Cortex-M0 路线，不使用也不验证 RISC-V/PicoRV32。
- FPGA 目标板卡为 KC705，器件为 `xc7k325tffg900-2`，板卡文件为 `xilinx.com:kc705:part0:1.6`。
- ILA 必须保留，默认使用 `KC705_ENABLE_ILA` 和 `ila_cpu_npu_kc705`，不使用 `-NoIla`。
- 200MHz 目标按严格口径处理：KC705 上 `soc_clk_mmcm` 为 5.000ns，并要求实现后 `WNS >= 0`。
- 在 `WNS < 0` 时，不能把生成的 bitstream 作为 200MHz timing signoff 结果。

## 2. 当前设计代码事实

### 2.1 ARM + NPU 集成

- 当前 ARM 路线顶层为 `rtl/cortex_m0_npu_soc.v`。
- CPU 使用 Arm Cortex-M0 DesignStart：
  - `doc/.../cortexm0ds_logic.v`
  - `doc/.../CORTEXM0INTEGRATION.v`
  - wrapper 为 `rtl/cortex_m0_designstart_ahb.v`
- CPU 通过 AHB-Lite 发起控制访问，经 `ahb_lite_to_axil_bridge` 转换到 AXI-Lite。
- NPU 控制面为 AXI-Lite，数据面为 AXI Burst DMA，经 `axi_shared_interconnect` 访问共享 SRAM/BRAM。

### 2.2 NPU 与竞赛指标

- `rtl/systolic_array_4x4.v` 实现 4x4 INT8 脉动阵列。
- `rtl/npu_accel_axi.v` 实现：
  - AXI-Lite 控制寄存器；
  - AXI INCR Burst 读 A/B、写 C；
  - DMA active/data/read/write 计数器；
  - `PE_MASK` 动态 PE 屏蔽；
  - `DFS_CTRL`/`DFS_WAIT` 频率调节行为建模；
  - `array_clk_en` 阵列时钟使能/门控；
  - `PEAK_MTOPS = 1024`，即 1.024 TOPS@INT8。

## 3. 已验证结果

### 3.1 RTL 回归

已运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_all_checks.ps1
```

结果：

- `tb_npu_core_4x4` PASS
- `tb_axi_burst_dma` PASS
- `tb_hetero_soc` PASS
- `tb_npu_stress` PASS
- `tb_cortex_m0_cpu_npu` PASS
- 真实 Cortex-M0 DesignStart 固件完成 AHB-Lite 控制、AXI-Lite 桥访问、NPU 启动、IRQ/done 轮询、zero-copy 地址传递。
- `docs/metrics_report.md` 显示：
  - RTL clock target: 200 MHz
  - Peak INT8: 1.024 TOPS
  - DMA Burst utilization: 85%
  - Functional coverage: 100%
  - Code path coverage model: 100%

结论：RTL 功能和竞赛性能模型已经满足 ARM 路线的基础指标与大部分优化指标。

### 3.2 Vivado KC705 200MHz 实现

已运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_kc705.ps1 -Action impl -Jobs 4
```

结果：

- Vivado 成功综合、实现并生成 bitstream。
- ILA 保留，生成：
  - `fpga/vivado/bitstreams/kc705_cpu_npu.bit`
  - `fpga/vivado/bitstreams/kc705_cpu_npu.ltx`
- `fpga/vivado/reports/impl_timing_summary.rpt` 显示：
  - `soc_clk_mmcm` 周期为 5.000ns，即 200.000MHz；
  - WNS = -3.869ns；
  - 失败端点数为 1598；
  - 最坏路径在 Cortex-M0 DesignStart 内部 `u_logic`；
  - 最坏路径包含 `DSP48E1=1`、14 级逻辑，Data Path Delay = 8.917ns。
- `fpga/vivado/reports/impl_drc.rpt` 显示：
  - DRC error 为 0；
  - 主要 warning 是 BRAM 异步复位控制相关 `REQP-1839`，以及 ILA/debug hub 相关 `RTSTAT-10`。

结论：当前 bitstream 不能作为严格 200MHz FPGA 验收结果，因为实现后 timing 未收敛。

## 4. 资料与开源方案调研结论

参考资料：

- AMD Vivado UG906 Design Analysis and Closure Techniques：用于判断 WNS/TNS、timing path 和 closure 问题。
- AMD Vivado UG904 Implementation：用于实现策略、`phys_opt_design`、route/place directive 和 timing closure 流程。
- AMD 7 Series DSP48E1 UG479：DSP48E1 乘法路径需要流水寄存器，未流水的 DSP 输入/输出通常难以在高频下收敛。
- Arm Cortex-M0 资料：Cortex-M0 乘法器存在快/慢实现等 silicon option，但当前 DesignStart 混淆核实例不能直接通过参数调整。
- Gemmini、VTA、NVDLA 等开源加速器：都证明 CPU 控制 + 片上缓冲/DMA + 专用矩阵加速器是合理架构，但它们不能直接解决当前 Cortex-M0 obfuscated RTL 的内部 DSP timing。

关键发现：

- 本地 DesignStart 示例系统中存在 `SMUL` 参数，但注释说明 obfuscated DesignStart 路线不会向 `CORTEXM0INTEGRATION` 传参；只有非混淆 `CORTEX_M0` 路线才是 parameterized code。
- 当前工程直接实例化 `CORTEXM0INTEGRATION`，Vivado 综合后在 Cortex-M0 内部生成 3 个 `DSP48E1`，最坏路径正落在该区域。
- 已尝试修正 Cortex-M0 pblock 约束和 aggressive implementation directive，但 WNS 仍为 -3.869ns，说明单靠 floorplan/directive 不足以解决该结构性路径。

## 5. 目标 Goal

目标：仅针对 ARM/Cortex-M0 的 KC705 CPU+自研 NPU 设计，在 200MHz 条件下达到竞赛可验收指标。

验收标准：

1. RTL 回归保持通过：
   - `scripts/run_all_checks.ps1` 全部 PASS；
   - `tb_cortex_m0_cpu_npu` 仍为真实 Cortex-M0 DesignStart 固件协同 NPU；
   - 1.024 TOPS@INT8、DMA Burst 利用率 85%、功能/路径覆盖指标保持通过。
2. Vivado 实现达到严格 200MHz：
   - `soc_clk_mmcm` = 5.000ns / 200.000MHz；
   - `WNS >= 0`；
   - DRC 无 Error，关键 warning 有解释或修复；
   - ILA 保留且 `.ltx` 与 bitstream 匹配。
3. 真实 KC705 上板：
   - Hardware Manager 识别 `xc7k325t`；
   - program 成功；
   - ILA 捕获 `debug_resetn`、`npu_array_clk_en`、`npu_irq/npu_irq_latched`、DMA 计数器和 cycle counter；
   - 捕获结果能支撑矩阵任务完成、阵列空闲关断、DMA Burst 利用率计算。

## 6. 下一步路线

首选路线：解决 Cortex-M0 内部乘法/DSP timing。

1. 查找是否具备合法的非混淆 Cortex-M0 RTL 或可参数化 `CORTEXM0INTEGRATION`。
2. 若可用，使用可参数化核替换当前 obfuscated 实例，并明确设置/验证 `SMUL` 乘法器实现，使 ARM 核不再形成当前未流水 DSP48E1 关键路径。
3. 重新跑 ARM RTL 回归，确保固件行为和 AHB-Lite 总线行为不变。
4. 重新跑 KC705 implementation，目标 `WNS >= 0`。

备选路线：若竞赛允许 CPU 与 NPU 不同频。

1. 保持 NPU/AXI Burst/ILA 为 200MHz。
2. Cortex-M0 运行在较低可收敛频率，通过 CDC/异步桥访问 200MHz NPU 控制域。
3. 报告中明确写明 200MHz 指标对应 NPU/数据面，而不是整个 ARM SoC 单时钟域。

不建议路线：

- 在没有 Arm 官方约束或结构证明的情况下，对 Cortex-M0 内部乘法路径随意加 multicycle/false path。
- 在 WNS 为负时直接 program 并声称 200MHz FPGA 验证通过。
- 为了过 timing 移除 ILA 或降低目标频率。

## 7. 本轮补充调研与目标设定

### 7.1 调研假设

- 只处理 ARM/Cortex-M0 路线，不使用 RISC-V/PicoRV32 路线规避问题。
- 200MHz 是真实 Vivado 实现时钟要求，不只是 testbench `#2.5` 时钟。
- ILA 是上板验证证据的一部分，不能通过 `-NoIla` 或删除 `ila_cpu_npu_kc705` 换取 timing。
- 不能对第三方 Cortex-M0 混淆 RTL 内部路径添加没有结构依据的 false path/multicycle path。

### 7.2 网络资料、论文和开源代码结论

- AMD UG906 将 timing closure 视为基于 timing report、methodology report、clock/constraint/floorplan 的迭代分析流程；因此当前 `WNS=-3.869ns` 不能被忽略，必须作为 signoff 阻塞项处理。
- AMD UG904 说明 Vivado implementation 由 place/route/phys_opt 等命令和策略组成；当前脚本已经启用 aggressive implementation directive，但还需要确认约束是否实际生效，并尝试更多合法 QoR 策略。
- VTA 论文显示，面向边缘 FPGA 的 NPU/张量加速器通常采用 CPU 控制、显式 load/compute/store pipeline、片上 SRAM、DMA 和参数化硬件设计空间；这支持当前 CPU 控制 + NPU 矩阵计算 + DMA 搬运的总体架构。
- Gemmini 开源代码/文档显示，成熟 systolic-array 加速器核心包含脉动阵列、scratchpad/accumulator SRAM、DMA、INT8 输入与 INT32 累加等结构；这与当前 4x4 INT8 NPU、共享存储、DMA 读写 A/B/C 的设计方向一致。
- NVDLA 文档显示，开源 DNN accelerator 常由外部 CPU 管理，Verilog RTL、AXI/TL adapter、FPGA sample platform、clock/power gating 和 partition/retiming 都是工程化关注点；这支持把 FPGA 上板验证、ILA 捕获、功耗状态作为比赛加分证据。

### 7.3 当前代码分析结论

- `rtl/cortex_m0_designstart_ahb.v` 直接例化 `CORTEXM0INTEGRATION`，FCLK/SCLK/HCLK/DCLK 同接 `soc_clk`。
- 本地 DesignStart 官方示例在 `cmsdk_mcu_system.v` 中明确区分：
  - `CORTEX_M0DESIGNSTART`：obfuscated code，不传任何参数；
  - `CORTEX_M0`：non-obfuscated parameterized code，可传 `SMUL`。
- 因此当前混淆版 Cortex-M0 不能通过简单 wrapper 参数把 fast multiplier 改成 small multiplier。
- Vivado DRC/methodology 已指出 Cortex-M0 内部存在未流水 DSP48E1 乘法器；当前最坏路径也落在 `u_soc/u_cpu/u_cortexm0integration/u_logic` 内部。
- `MAX_DSP=0` 实验已经移除 DSP48E1，但综合 timing 更差，说明单纯禁止 DSP 不是可行主路线。
- `fpga/vivado/constraints/kc705_cpu_npu_timing.xdc` 已改为纯 XDC pblock 命令，下一步必须用 fresh implementation 确认 pblock 是否真正生效。

### 7.4 Goal

目标：在保留 ARM/Cortex-M0、KC705、ILA 的前提下，让 CPU+自研 NPU 设计在真实 200MHz 条件下达到竞赛可验收指标。

达标判据：

1. RTL/比赛指标：
   - `scripts/run_all_checks.ps1` 全部 PASS；
   - `docs/metrics_report.md` 保持 RTL clock target 200MHz；
   - 峰值算力保持 `1.024 TOPS@INT8`；
   - AXI Burst/DMA 利用率保持 `85%`，不低于 80%；
   - ARM Cortex-M0 固件协同、AHB-Lite 到 AXI-Lite、NPU DMA、IRQ/done、低功耗状态覆盖保持通过。
2. Vivado/KC705 200MHz：
   - `soc_clk_mmcm` timing period 为 `5.000ns / 200.000MHz`；
   - implementation 后 `WNS >= 0`、TNS 为 0；
   - DRC 无 error，关键 methodology warning 有修复或解释；
   - bitstream 与 `.ltx` 匹配，ILA 保留。
3. 真实板卡验证：
   - Hardware Manager 识别 `xc7k325t`；
   - program KC705 成功；
   - ILA 捕获 `debug_resetn` 释放、`npu_array_clk_en` 计算期间拉高且空闲关闭、`npu_irq/npu_irq_latched` 完成标志、DMA active/data/read/write 计数器和 cycle counter；
   - 捕获数据能支撑矩阵任务完成、Burst 利用率和低功耗门控证据。

若 fresh implementation 仍无法使 Cortex-M0 混淆核在 200MHz 下收敛，则不伪造 200MHz FPGA 通过结论，转入结构性方案：

1. 寻找/替换合法 non-obfuscated parameterized Cortex-M0，并设置可收敛的 multiplier 配置；
2. 或者在用户确认后改成 CPU 低频域 + NPU/AXI Burst/ILA 200MHz 域，并用 CDC/异步桥明确报告“200MHz 指标对应 NPU 数据面”。

### 7.5 新增 Vivado retiming/DSP register optimization 实验

为确认是否还能通过 Vivado 实现策略解决，而不改 RTL、不移除 ILA、不降低频率，新增脚本参数：

- `-SynthDirective`
- `-OptDirective`
- `-PlaceDirective`
- `-PhysOptDirective`
- `-RouteDirective`
- `-PostRoutePhysOptDirective`

实验命令：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_kc705.ps1 -Action impl -Jobs 4 -BitstreamName kc705_cpu_npu_retime -SynthDirective PerformanceOptimized -PhysOptDirective AlternateFlowWithRetiming -PostRoutePhysOptDirective AddRetime
```

Vivado 2019.2 命令帮助确认 `phys_opt_design` 支持：

- `-dsp_register_opt`
- `-retime`
- `AlternateFlowWithRetiming`
- `AddRetime`

实验结果：

- ILA 保留，生成：
  - `fpga/vivado/bitstreams/kc705_cpu_npu_retime.bit`
  - `fpga/vivado/bitstreams/kc705_cpu_npu_retime.ltx`
- `soc_clk_mmcm` 仍为 `5.000ns / 200.000MHz`。
- implementation 后仍有 timing violation：
  - WNS = `-3.992ns`
  - TNS = `-3003.659ns`
  - failing endpoints = `1507`
- 最坏路径仍落在 `u_soc/u_cpu/u_cortexm0integration/u_logic`。
- 最坏路径包含 `DSP48E1=2`，Data Path Delay = `8.966ns`。
- DRC 仍报告 Cortex-M0 内部 DSP 输入/输出/乘法级未流水：
  - `DPIP-1`
  - `DPOP-1`
  - `DPOP-2`

结论：显式启用 Vivado retiming/DSP register optimization 变体后，WNS 未改善，反而从前一轮 `-3.880ns` 变为 `-3.992ns`。这进一步证明当前主要瓶颈不是普通 place/route 策略，而是 obfuscated Cortex-M0 内部 fast multiplier/DSP 结构无法在 KC705 `-2` speed grade 下满足 5ns 单周期时序。

## 8. 本轮补充分析：资料调研、代码定位与目标设定

### 8.1 本轮假设

- 只处理 ARM/Cortex-M0 路线；RISC-V/PicoRV32 不作为本阶段验收对象。
- 200MHz 指真实 Vivado 实现约束中的 `soc_clk_mmcm = 5.000ns / 200.000MHz`，不是只在 testbench 中写 `always #2.5 clk = ~clk`。
- ILA 是上板证据链的一部分，不能通过 `-NoIla` 或移除 `ila_cpu_npu_kc705` 来换取 timing。
- 在 `WNS < 0` 时，不把 bitstream program 结果宣传为 200MHz FPGA 验收通过。

### 8.2 网络资料、论文与开源代码结论

- AMD Vivado timing closure 方法论要求以 timing summary、critical path、methodology/DRC 和 QoR 建议为核心证据。当前 `WNS=-3.992ns`、`TNS=-3003.659ns`、1507 个失败端点，因此必须视为 signoff 阻塞项。
- AMD Vivado implementation/phys-opt 资料说明 retiming、physical optimization 和 DSP register optimization 是合法尝试；本工程已经用 `PerformanceOptimized`、`AlternateFlowWithRetiming`、`AddRetime` 做过实验，但未改善最坏路径。
- Xilinx/AMD DSP48E1 相关资料和 Vivado DRC 一致指向同一个问题：高频乘法路径通常需要输入、乘法级和输出流水。当前 DRC 中 `DPIP-1`、`DPOP-1`、`DPOP-2` 都落在 `u_soc/u_cpu/u_cortexm0integration/u_logic/Affpw60*` DSP 上，说明工具无法在混淆核内部安全插入所需流水。
- Cortex-M0 DesignStart 本地示例显示存在 `SMUL` 乘法器配置：`SMUL=0` 为 fast multiplier，`SMUL=1` 为 small multiplier。但当前工程直接例化的是 `CORTEXM0INTEGRATION` 混淆交付形态，不能在本 wrapper 中可靠地改写内部乘法器结构。
- Gemmini、VTA、NVDLA 等开源/论文架构都采用 CPU 控制、片上存储、DMA/Load-Store 数据搬运、矩阵/张量计算阵列的分工。这证明当前 CPU 只做控制、NPU 用 4x4 INT8 阵列和 AXI Burst DMA 做矩阵计算的总体架构是合理的；它们不能解决当前 ARM 混淆核内部 DSP timing，但能支撑比赛文档中的架构合理性论证。

### 8.3 当前代码与报告定位

- RTL 仿真证据已经达标：`docs/metrics_report.md` 写明 `RTL clock target: 200 MHz`、`1024 MTOPS = 1.024 TOPS`、DMA Burst 利用率 `85%`、功能覆盖和路径覆盖模型均为 `100%`。
- `rtl/cortex_m0_designstart_ahb.v` 中 `FCLK/SCLK/HCLK/DCLK` 全部接同一个 `hclk`，所以当前 FPGA 单时钟方案要求 Cortex-M0 内核也在 200MHz 下收敛。
- `fpga/rtl/fpga_kc705_top.v` 中 MMCM 参数为 `CLKIN1_PERIOD=5.000`、`CLKOUT0_DIVIDE_F=5.000`，ILA 时钟接 `soc_clk`，说明 KC705 wrapper 已按 200MHz SoC/ILA 目标配置。
- `fpga/vivado/reports/impl_timing_summary.rpt` 显示 `soc_clk_mmcm` 为 `5.000ns / 200.000MHz`，但 timing constraints are not met。
- `fpga/vivado/reports/impl_timing_paths_25.rpt` 最坏路径从 `Ydopw6_reg/C` 到 `Ydopw6_reg/D`，层级为 `u_soc/u_cpu/u_cortexm0integration/u_logic`，Data Path Delay `8.966ns`，含 `DSP48E1=2`、`CARRY4=2`、多级 LUT。

### 8.4 设定的 Goal

目标：仅针对 ARM/Cortex-M0 的 KC705 CPU+自研 NPU 设计，在保留 ILA、保持真实 200MHz 的条件下达到比赛可验收指标。

验收标准：

1. RTL 回归继续通过：
   - `scripts/run_all_checks.ps1` 全部 PASS。
   - `tb_cortex_m0_cpu_npu` 仍是 Cortex-M0 固件控制 NPU。
   - `1.024 TOPS@INT8`、AXI Burst/DMA 利用率 `85%`、覆盖指标保持达标。
2. Vivado/KC705 严格 200MHz timing signoff：
   - `soc_clk_mmcm` 周期为 `5.000ns`。
   - implementation 后 `WNS >= 0`、`TNS = 0`。
   - DRC 无 error；关键 methodology/DRC warning 已修复或有明确解释。
   - ILA 保留，bitstream 与 `.ltx` 匹配。
3. 真实板卡验证：
   - Hardware Manager 识别并 program `xc7k325t`。
   - ILA 捕获 `debug_resetn` 释放、`npu_array_clk_en` 计算期拉高且空闲关闭、`npu_irq/npu_irq_latched` 完成标志、DMA active/data/read/write 计数器和 cycle counter。
   - 捕获数据可用于支撑矩阵任务完成、Burst 利用率和低功耗门控证据。

### 8.5 后续执行路线

主路线：寻找或接入合法的 non-obfuscated/parameterized Cortex-M0 RTL，使用 `SMUL=1` 或等价的小乘法器/可收敛乘法器配置替换当前混淆 fast-multiplier 实例，然后复跑 ARM RTL 回归和 KC705 200MHz implementation。

备选路线：若无法获得可参数化 Cortex-M0 RTL，则需要用户确认是否允许“CPU 低频域 + NPU/AXI Burst/ILA 200MHz 域”的双时钟方案。该方案必须增加 CDC/异步桥，并在报告中明确 200MHz 指标对应 NPU 数据面和上板验证域，而不是整个 ARM 单时钟 SoC。

不采用的路线：

- 不对 Cortex-M0 内部乘法路径加无依据的 false path 或 multicycle path。
- 不降低 `soc_clk_mmcm` 目标频率。
- 不移除 ILA。
- 不把 `WNS < 0` 的 bitstream 当作 200MHz 通过证据。

## 9. 本轮实现实验：Cortex-M0 乘法器禁用 DSP48

### 9.1 实验目的

前一轮最坏路径和 DRC 均指向 Cortex-M0 混淆逻辑内部 `Affpw60*` DSP48E1 乘法链。由于本地 `CORTEXM0INTEGRATION` 没有参数列表，也没有可直接传入 `SMUL=1` 的 non-obfuscated RTL，本轮先做一个可回退的综合实验：仅在显式开关启用时，对 `cortexm0ds_logic.v` 中唯一的 `Mifpw6 * Tgfpw6` 乘法结果线增加 `(* use_dsp = "no" *)`，避免 Vivado 将该乘法推成 DSP48E1。

相关改动：

- `doc/.../cortexm0ds_logic.v` 增加 `CORTEXM0DS_NO_DSP_MULT` 宏分支，默认关闭。
- `scripts/run_vivado_kc705.ps1` 增加 `-CortexM0NoDspMult` 开关。
- `fpga/vivado/tcl/setup_project.tcl` 在环境变量 `FPGA_CORTEXM0_NO_DSP_MULT=1` 时加入 `CORTEXM0DS_NO_DSP_MULT`。
- `fpga/vivado/tcl/run_kc705_200mhz_experiment.tcl` 新增 workspace 内 non-project 实验流，避免原 `E:\Program\Vivado\project_1.xpr` 被既有 Vivado 进程锁定时无法写入。

### 9.2 RTL 回归

默认关闭 no-DSP 宏后运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_all_checks.ps1
```

结果保持通过：

- `tb_npu_core_4x4` PASS
- `tb_axi_burst_dma` PASS
- `tb_hetero_soc` PASS
- `tb_npu_stress` PASS
- `tb_cortex_m0_cpu_npu` PASS
- `docs/metrics_report.md` 继续显示 200MHz RTL target、1.024 TOPS、DMA 85%、功能/路径覆盖 100%。

单独启用宏编译：

```powershell
iverilog -g2012 -Wall -Wno-timescale -DCORTEXM0DS_NO_DSP_MULT -I rtl -o sim/cortex_m0_npu_soc_nodsp_compile.vvp -s cortex_m0_npu_soc -f rtl/filelist_cortexm0.f
```

结果：编译通过，说明宏分支语法有效。

### 9.3 Vivado 实验结果

实验命令：

```powershell
& 'E:\Application\Xilinx\Vivado\2019.2\bin\vivado.bat' -mode batch -source fpga\vivado\tcl\run_kc705_200mhz_experiment.tcl
```

输出：

- bitstream: `fpga/vivado/bitstreams/kc705_200mhz_nodspcpu.bit`
- ltx: `fpga/vivado/bitstreams/kc705_200mhz_nodspcpu.ltx`
- reports: `fpga/vivado/experiments/kc705_200mhz_nodspcpu/reports`

关键结果：

- `soc_clk_mmcm` 仍为 `5.000ns / 200.000MHz`。
- DRC 中 `DPIP-1`、`DPOP-1`、`DPOP-2` 消失，说明 Cortex-M0 DSP48E1 乘法器已不再作为 DSP 实现。
- `impl_utilization.rpt` 显示 DSP 使用数为 `0`。
- implementation 仍未满足 200MHz：
  - WNS = `-3.704ns`
  - TNS = `-3103.673ns`
  - failing endpoints = `1698`
- 新最坏路径仍在 `u_soc/u_cpu/u_cortexm0integration/u_logic`：
  - Source: `O5ppw6_reg/C`
  - Destination: `Ydopw6_reg/D`
  - Data Path Delay = `8.787ns`
  - Logic Levels = `22`
  - 资源为 `CARRY4=6`、多级 LUT，无 DSP48E1。

### 9.4 实验结论

`CORTEXM0DS_NO_DSP_MULT` 能消除 Cortex-M0 内部 DSP48E1 未流水 DRC warning，并将 WNS 从 `-3.992ns` 小幅改善到 `-3.704ns`；但它没有让 KC705 `-2` 器件在单时钟 ARM SoC 200MHz 下收敛。瓶颈从“未流水 DSP 乘法链”转移为 Cortex-M0 混淆逻辑内部更长的 LUT/CARRY 控制/算术组合路径，且路由延迟占比约 75%。

下一步可尝试更激进但仍不改变功能的 pblock/placement 实验，压缩 Cortex-M0 逻辑的放置区域，降低路由延迟；若仍无法达到 `WNS >= 0`，则进一步证明需要合法可参数化 Cortex-M0 RTL 或双时钟域结构方案。

### 9.5 pblock 收紧实验

为验证路由延迟是否能靠更紧凑 placement 改善，使用同一 non-project 实验流运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_kc705_experiment.ps1 `
  -Jobs 4 `
  -ExperimentName kc705_200mhz_nodspcpu_pblock1 `
  -CortexM0PblockSliceRange "SLICE_X96Y56:SLICE_X119Y96" `
  -CortexM0PblockDspRange "DSP48_X2Y20:DSP48_X3Y36"
```

输出：

- bitstream: `fpga/vivado/bitstreams/kc705_200mhz_nodspcpu_pblock1.bit`
- ltx: `fpga/vivado/bitstreams/kc705_200mhz_nodspcpu_pblock1.ltx`
- reports: `fpga/vivado/experiments/kc705_200mhz_nodspcpu_pblock1/reports`

结果：

- `soc_clk_mmcm` 仍为 `5.000ns / 200.000MHz`。
- DRC 无 error，且仍无 Cortex-M0 DSP48E1 未流水警告。
- timing 变差：
  - WNS = `-4.092ns`
  - TNS = `-3548.508ns`
  - failing endpoints = `2070`
- 最坏路径仍在 `u_soc/u_cpu/u_cortexm0integration/u_logic`，Data Path Delay = `9.098ns`，Logic Levels = `22`。

结论：简单收紧 Cortex-M0 pblock 不能解决问题，反而增加拥塞/路由压力。当前证据进一步支持结构性结论：在不降低频率、不移除 ILA、不添加无依据 timing exception 的前提下，现有混淆版 Cortex-M0 单时钟 200MHz 很难通过普通综合实现策略收敛。

### 9.6 no-pblock 对照实验

为排除默认 Cortex-M0 pblock 约束本身引入额外拥塞的问题，又运行了关闭 Cortex-M0 pblock 的 no-DSP 实验：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_kc705_experiment.ps1 `
  -Jobs 4 `
  -ExperimentName kc705_200mhz_nodspcpu_nopblock `
  -DisableCortexM0Pblock
```

输出：

- bitstream: `fpga/vivado/bitstreams/kc705_200mhz_nodspcpu_nopblock.bit`
- ltx: `fpga/vivado/bitstreams/kc705_200mhz_nodspcpu_nopblock.ltx`
- reports: `fpga/vivado/experiments/kc705_200mhz_nodspcpu_nopblock/reports`

关键结果：

- `soc_clk_mmcm` 仍为 `5.000ns / 200.000MHz`。
- DRC 中无 Cortex-M0 DSP48E1 未流水警告。
- timing 是目前实验中最好的一版，但仍未达标：
  - WNS = `-3.488ns`
  - TNS = `-3069.142ns`
  - failing endpoints = `2099`
- 最坏路径仍在 `u_soc/u_cpu/u_cortexm0integration/u_logic`：
  - Source: `Ozvax6_reg/C`
  - Destination: `Ydopw6_reg/D`
  - Data Path Delay = `8.536ns`
  - Logic Levels = `21`
  - 资源为 `CARRY4=7`、多级 LUT，route delay 占比约 `73%`。

结论：关闭 pblock 比收紧 pblock 更好，但仍距离 `WNS >= 0` 约 `3.5ns`。这已经超出普通 directive、retiming、floorplan 微调通常能补回的余量范围，因此后续应进入结构性方案，而不是继续堆叠实现策略。

## 10. 外部资料与开源代码复核后的目标设定

### 10.1 资料复核结论

- AMD Vivado timing closure 资料强调以 post-route timing summary、critical path、methodology/DRC 和 QoR 建议作为收敛依据；因此当前 `WNS < 0` 的 bitstream 不能作为 200MHz FPGA 验收证据。
- AMD Vivado implementation/phys-opt 资料支持尝试 retiming、physical optimization、DSP register optimization 等实现策略；本工程已做过 retiming/DSP/no-DSP/pblock/no-pblock 实验，最好结果仍为 `WNS=-3.488ns`。
- AMD 7 Series DSP48E1 资料说明高频乘法路径依赖输入、乘法级和输出流水寄存器；当前混淆版 Cortex-M0 的 DSP 路径已通过 no-DSP 实验规避，但瓶颈转移到更长的 LUT/CARRY 组合路径。
- 本地 Arm Cortex-M0 DesignStart 示例系统存在 `SMUL` 参数，但当前工程实例化的是无参数的 `CORTEXM0INTEGRATION` 交付形态；在本 checkout 内不能通过 wrapper 可靠设置 `SMUL=1`。
- Gemmini、VTA、NVDLA 等开源/论文架构均支持“CPU 控制面 + 片上存储/DMA + 专用矩阵/张量计算阵列”的系统划分；这证明当前 CPU 控制 NPU、NPU 负责 INT8 矩阵计算和 Burst DMA 的比赛架构是合理的，真正阻塞点是 ARM 混淆核单时钟 200MHz 时序，而不是 NPU 架构方向。

### 10.2 当前目标

当前 active goal 保持为：

> 仅针对 ARM/Cortex-M0 的 KC705 CPU+自研 NPU 设计，在仿真和 Vivado 实现中达到真实 200MHz 验收：RTL 回归维持 1.024TOPS@INT8、AXI Burst/DMA 利用率不低于 80%、功能/路径覆盖指标通过；Vivado 实现保留 ILA 且 soc/验证时钟为 5.000ns，最终 WNS >= 0、DRC 无阻塞错误，并完成真实板卡 program + ILA 捕获与指标报告。

### 10.3 达标路线

首选路线：接入合法的 non-obfuscated/parameterized Cortex-M0 RTL，并使用 `SMUL=1` 或等价的小乘法器/可收敛乘法器配置，替换当前无参数 `CORTEXM0INTEGRATION` 路线。完成后必须重新跑：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_all_checks.ps1
powershell -ExecutionPolicy Bypass -File scripts\check_cpu_compile.ps1
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_kc705.ps1 -Action impl -Jobs 4
```

备选路线：如果无法取得合法可参数化 Cortex-M0 RTL，则需要用户确认是否允许双时钟方案：Cortex-M0 控制面运行在可收敛低频域，NPU/AXI Burst/ILA 数据面保持 200MHz，通过 CDC/异步桥连接。该路线可以让 NPU 200MHz 指标成立，但不能声称整个 ARM 单时钟 SoC 在 200MHz 下通过。

明确不采用：

- 不移除 ILA。
- 不降低 `soc_clk_mmcm` 目标频率。
- 不给 Cortex-M0 内部混淆逻辑添加无结构依据的 false path 或 multicycle path。
- 不把 `WNS < 0` 的 bitstream 当作 200MHz 通过证据。

## 11. 上板前 timing gate

为避免把已经生成但未通过 200MHz signoff 的 bitstream 误用于 program/ILA 验收，新增前置检查脚本：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check_vivado_timing_gate.ps1 `
  -TimingReport fpga\vivado\reports\impl_timing_summary.rpt
```

检查条件：

- timing report 中必须存在 `soc_clk_mmcm`。
- `soc_clk_mmcm` 必须为 `5.000ns / 200.000MHz`。
- overall `WNS >= 0.000ns`。

`scripts/run_vivado_kc705.ps1 -Action program` 和 `-Action capture` 已接入该 gate。默认会优先检查与 `-BitstreamName` 同名实验目录下的：

```text
fpga/vivado/experiments/<BitstreamName>/reports/impl_timing_summary.rpt
```

若不存在，则检查主工程报告：

```text
fpga/vivado/reports/impl_timing_summary.rpt
```

当前验证结果：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check_vivado_timing_gate.ps1 `
  -TimingReport fpga\vivado\experiments\kc705_200mhz_nodspcpu_nopblock\reports\impl_timing_summary.rpt
```

输出结论：

- `soc_clk_mmcm` = `5.000ns / 200.000MHz`
- overall WNS = `-3.488ns`
- gate 失败，拒绝把该 bitstream 作为 200MHz signoff image program。

主工程 timing report 同样被拒绝：

- `soc_clk_mmcm` = `5.000ns / 200.000MHz`
- overall WNS = `-3.992ns`
- gate 失败。

这一步不改变最终目标，只是把验收边界脚本化：后续只有当新的 Cortex-M0 配置或结构性实现真正达到 `WNS >= 0` 时，program + ILA 捕获流程才会继续执行。

## 12. 双时钟结构候选实验

由于本地 DesignStart 包和原始 `AT511-r2p0-00rel0-1.tar.gz` 中都没有 `module CORTEX_M0` 非混淆源码，也没有带参数列表的 `CORTEXM0INTEGRATION`，当前 checkout 内无法通过 `SMUL=1` 直接替换混淆版 Cortex-M0 乘法器配置。为了继续推进 200MHz 可行性验证，新增了一个不替换主线的候选结构实验：

- CPU/Cortex-M0 控制面运行在 `cpu_clk`。
- NPU、AXI Burst 数据面、共享 SRAM 和 ILA 观测域运行在 `data_clk = 200MHz`。
- CPU AHB-Lite 访问仍先经过 `ahb_lite_to_axil_bridge`。
- CPU AXI-Lite 控制访问通过 `axil_cdc_bridge` 跨到 200MHz 数据面。
- NPU DMA 仍在 200MHz 数据面直接访问共享 SRAM。

新增文件：

- `rtl/axil_cdc_bridge.v`
- `rtl/cortex_m0_npu_soc_dual_clock.v`
- `tb/tb_cortex_m0_cpu_npu_dual_clock.v`
- `rtl/filelist_cortexm0_dual_clock.f`
- `scripts/check_cpu_dual_clock_sim.ps1`

验证命令：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check_cpu_dual_clock_sim.ps1
```

结果：

- `PASS tb_cortex_m0_cpu_npu_dual_clock`
- `INFO dual_clock DMA data utilization percent=85`
- `INFO dual_clock peak mtops=1024`

随后复跑主线回归：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_all_checks.ps1
```

结果保持通过：

- `tb_npu_core_4x4` PASS
- `tb_axi_burst_dma` PASS
- `tb_hetero_soc` PASS
- `tb_npu_stress` PASS
- `tb_cortex_m0_cpu_npu` PASS
- Functional coverage score: `100%`
- Code path coverage score: `100%`
- `docs/metrics_report.md` 继续显示 200MHz RTL target、1.024 TOPS、DMA 85%。

边界说明：

- 该实验不能直接替代“ARM 单时钟 SoC 200MHz、WNS >= 0”的最终验收。
- 该实验的价值是隔离验证 NPU/AXI Burst/ILA 数据面 200MHz 方案，并为无法取得可参数化 Cortex-M0 RTL 时的备选结构提供 RTL 功能证据。
- 若后续采用该路线，文档和报告必须明确：200MHz 指标对应 NPU 数据面，不等同于 Cortex-M0 内核本身运行在 200MHz。
