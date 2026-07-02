# 项目名称

基于CPU+NPU的异构处理器设计（AXI架构）

# 1. 项目背景与目标

## 1.1 任务背景

本项目面向“智核融合·低耗强算——基于CPU和NPU的异构处理器设计”赛题，目标是在低功耗32位处理器基础上集成专用NPU计算单元，通过标准AXI互连实现CPU控制与NPU矩阵计算的协同。赛题要求系统同时具备通用控制能力、专用AI计算能力、AXI-Lite单拍访问、AXI Burst数据搬运、基础低功耗机制以及可复现的RTL仿真验证流程。

传统低功耗CPU适合控制流、寄存器配置、任务调度和中断处理，但在INT8矩阵乘法等AI推理核心算子上能效不足。NPU适合并行矩阵运算，但不适合独立完成复杂控制。因此，本项目采用“CPU负责控制、NPU负责计算、AXI总线负责通信与数据共享”的异构方案。

## 1.2 设计目标

| 目标类别 | 项目目标 |
| --- | --- |
| 架构目标 | 集成真实Arm Cortex-M0 DesignStart CPU、AXI共享互连、NPU、DMA和共享SRAM |
| 通信目标 | CPU通过AHB-Lite到AXI-Lite桥访问NPU控制寄存器，NPU通过AXI Burst访问共享SRAM |
| 计算目标 | 实现4×4 INT8脉动阵列，输出INT32累加结果 |
| 性能目标 | RTL目标频率200 MHz，峰值指标达到1.024 TOPS@INT8 |
| 带宽目标 | Burst场景下DMA数据周期利用率达到85%，高于80%优化目标 |
| 功耗目标 | 支持阵列时钟门控、自动功耗状态建模和DFS等待周期建模 |
| 验证目标 | 使用VS Code + Icarus Verilog完成可重复RTL仿真、日志和VCD波形输出 |

# 2. 系统总体架构

## 2.1 CPU与NPU协同方式

系统采用主从协同模型：

- Cortex-M0执行Thumb固件，完成启动、NPU寄存器配置、状态轮询和结果校验。
- NPU暴露AXI-Lite控制寄存器，接收矩阵A/B/C基地址、PE掩码、DFS配置、功耗控制和启动命令。
- NPU内部DMA作为AXI主设备直接访问共享SRAM，实现矩阵输入读取和结果写回。
- CPU不搬运矩阵数据本体，只传递共享SRAM地址，实现零拷贝交互。

## 2.2 AXI总线设计

系统包含两类AXI访问路径：

| 通道 | 用途 | 特点 |
| --- | --- | --- |
| AHB-Lite到AXI-Lite | Cortex-M0访问NPU寄存器 | 单拍寄存器读写，用于控制和状态查询 |
| AXI Burst | NPU DMA访问共享SRAM | INCR Burst读写，用于矩阵数据搬运 |

CPU原生总线为AHB-Lite。本项目通过`ahb_lite_to_axil_bridge`将CPU侧访问转换为AXI-Lite，再由`axi_shared_interconnect`分发到NPU寄存器或共享SRAM。NPU DMA侧直接通过AXI Burst主端口访问共享SRAM，提高数据搬运效率。

## 2.3 模块划分

```text
Arm Cortex-M0 DesignStart
        |
        | AHB-Lite
        v
AHB-Lite to AXI-Lite Bridge
        |
        | AXI-Lite
        v
AXI Shared Interconnect
        |                         |
        |                         |
        v                         v
NPU AXI-Lite Registers      Shared AXI SRAM
        |                         ^
        |                         |
        v                         |
NPU DMA Master --------------- AXI Burst
        |
        v
4x4 INT8 Systolic Array
```

| 模块 | RTL文件 | 作用 |
| --- | --- | --- |
| SoC顶层 | `rtl/cortex_m0_npu_soc.v` | 连接CPU、桥接器、共享互连、NPU和SRAM |
| CPU封装 | `rtl/cortex_m0_designstart_ahb.v` | 封装官方Cortex-M0 DesignStart核，输出AHB-Lite主口 |
| Cortex-M0 RTL | `doc/AT511-r2p0-00rel0-1/.../CORTEXM0INTEGRATION.v` | 真实Arm Cortex-M0集成层 |
| AHB到AXI-Lite桥 | `rtl/ahb_lite_to_axil_bridge.v` | 将CPU AHB-Lite访问转换为AXI-Lite |
| AXI共享互连 | `rtl/axi_shared_interconnect.v` | CPU寄存器访问与NPU DMA访问仲裁/路由 |
| NPU加速器 | `rtl/npu_accel_axi.v` | 寄存器、DMA FSM、性能计数、功耗状态 |
| NPU核心 | `rtl/npu_core_4x4.v` | 控制4×4脉动阵列、DFS和PE掩码 |
| 脉动阵列 | `rtl/systolic_array_4x4.v` | 4×4 INT8 MAC阵列 |
| PE单元 | `rtl/int8_mac_pe.v` | 单个INT8乘加处理单元 |
| AXI SRAM | `rtl/axi_ram.v` | 支持AXI INCR Burst的共享SRAM模型 |

# 3. 关键模块设计

## 3.1 CPU侧设计

### 功能

CPU侧采用真实Arm Cortex-M0 DesignStart RTL，负责系统控制流：

- 复位后从共享SRAM读取向量表和Thumb固件。
- 通过AHB-Lite发起寄存器访问。
- 配置NPU输入/输出地址、PE掩码、DFS和低功耗控制。
- 启动NPU并轮询STATUS寄存器。
- 读取NPU性能计数并写入共享SRAM结果区。

### 输入输出

| 方向 | 信号/接口 | 说明 |
| --- | --- | --- |
| 输入 | `hclk`, `hresetn` | CPU时钟和复位 |
| 输出 | `haddr`, `htrans`, `hwrite`, `hsize`, `hwdata` | AHB-Lite地址、控制和写数据 |
| 输入 | `hrdata`, `hready`, `hresp` | AHB-Lite读数据、完成和响应 |
| 输入 | `irq` | NPU完成中断输入 |
| 输出 | `halted` | 调试停止或异常锁定状态指示 |

### 关键设计思路

- CPU封装模块将DesignStart核的调试、低功耗保持、SysTick等非本题主路径信号进行合理tie-off，仅暴露本项目需要的AHB-Lite主口和IRQ。
- 测试平台在SRAM中预加载向量表和Thumb程序，避免依赖行为级CPU模型。
- CPU只传递矩阵地址，不搬运矩阵内容，降低CPU参与数据搬运的开销。

## 3.2 NPU（4×4脉动阵列）

### 功能

NPU核心实现4×4 INT8矩阵乘法，输入矩阵A和B各为4×4 INT8，输出矩阵C为4×4 INT32累加结果。NPU支持PE掩码控制，可在运行时关闭部分输出PE，实现动态可配置阵列的基础能力。

### 输入输出

| 方向 | 信号/接口 | 说明 |
| --- | --- | --- |
| 输入 | `clk`, `rst_n` | 时钟和复位 |
| 输入 | `start` | 启动一次矩阵计算 |
| 输入 | `dfs_divider` | DFS分频/等待配置 |
| 输入 | `a_matrix`, `b_matrix` | 4×4 INT8矩阵输入 |
| 输入 | `pe_mask` | 16位PE输出使能掩码 |
| 输出 | `busy`, `done` | 计算忙和完成标志 |
| 输出 | `array_clk_en` | 阵列时钟使能，用于门控 |
| 输出 | `active_cycles`, `dfs_wait_cycles` | 活跃周期和DFS等待周期 |
| 输出 | `c_matrix` | 4×4 INT32结果矩阵 |

### 关键设计思路

- `systolic_array_4x4`由16个`int8_mac_pe`组成，按4行4列连接。
- A矩阵从西侧输入，B矩阵从北侧输入，数据按周期错位送入阵列。
- 每个PE完成INT8有符号乘法和INT32累加。
- `pe_mask`对16个输出结果逐项屏蔽，支持全阵列和部分阵列模式。
- `array_clk_en`只在清零和运行有效周期拉高，空闲时关闭阵列更新。
- `dfs_divider`通过插入等待周期模拟动态频率调整效果。

## 3.3 AXI接口模块

### 功能

AXI接口模块由两部分组成：

- `ahb_lite_to_axil_bridge`：将Cortex-M0 AHB-Lite访问转换为AXI-Lite单拍读写。
- `axi_shared_interconnect`：根据地址将CPU访问路由到NPU寄存器或共享SRAM，并仲裁NPU DMA访问SRAM。

### 输入输出

| 模块 | 输入 | 输出 |
| --- | --- | --- |
| AHB到AXI-Lite桥 | AHB-Lite地址、控制、写数据、AXI-Lite响应 | AHB-Lite读数据/ready/resp、AXI-Lite读写通道 |
| AXI共享互连 | CPU AXI-Lite通道、NPU AXI主通道、SRAM响应 | NPU从端通道、SRAM AXI通道、CPU响应 |

### 关键设计思路

- AHB-Lite写操作存在地址相位和数据相位流水关系，桥接器在接受地址控制后，于下一阶段捕获`HWDATA`，保证真实Cortex-M0写时序正确。
- AXI-Lite写通道同时处理AW和W握手，完成后等待B响应；读通道发起AR后等待R响应。
- 互连模块通过地址高位识别NPU寄存器空间，NPU基地址为`0x1000_0000`。
- 当NPU DMA请求SRAM时，互连优先授予DMA通路；CPU访问SRAM在DMA空闲时执行。

## 3.4 DMA

### 功能

DMA集成在`npu_accel_axi`内部，用于NPU与共享SRAM之间的数据搬运：

- 使用AXI Burst读取矩阵A。
- 使用AXI Burst读取矩阵B。
- 计算完成后使用AXI Burst写回矩阵C。
- 统计DMA活跃周期、有效数据周期、读beat数和写beat数。

### 输入输出

| 方向 | 信号/接口 | 说明 |
| --- | --- | --- |
| 输入 | NPU寄存器中的A/B/C基地址 | DMA访问共享SRAM的地址 |
| 输出 | `m_axi_araddr`, `m_axi_arlen`, `m_axi_arvalid` | AXI读地址通道 |
| 输入 | `m_axi_rdata`, `m_axi_rvalid`, `m_axi_rlast` | AXI读数据通道 |
| 输出 | `m_axi_awaddr`, `m_axi_awlen`, `m_axi_awvalid` | AXI写地址通道 |
| 输出 | `m_axi_wdata`, `m_axi_wvalid`, `m_axi_wlast` | AXI写数据通道 |
| 输入 | `m_axi_bvalid`, `m_axi_bresp` | AXI写响应通道 |
| 输出 | DMA计数器 | 活跃周期、有效周期、读写beat |

### 关键设计思路

- 矩阵A和B各为4个32位word，因此分别使用4-beat INCR Burst读取。
- 矩阵C为16个INT32结果，因此使用16-beat INCR Burst写回。
- DMA FSM分为读A、读B、启动核心、等待核心完成、写C、等待写响应等阶段。
- CPU只写入地址寄存器，DMA直接访问共享SRAM，形成零拷贝数据路径。

## 3.5 时钟/低功耗模块

### 功能

低功耗设计主要体现在NPU核心和状态寄存器：

- 阵列时钟门控：NPU阵列仅在清零和运行有效周期更新。
- 自动功耗状态：`POWER_CTRL`寄存器支持auto power gate状态建模。
- DFS建模：`DFS_CTRL`控制等待周期插入，`DFS_WAIT`记录等待周期数。

### 输入输出

| 信号/寄存器 | 说明 |
| --- | --- |
| `array_clk_en` | 阵列时钟使能，空闲时为0 |
| `DFS_CTRL` | 控制DFS等待周期 |
| `DFS_WAIT` | 记录DFS插入等待周期 |
| `POWER_CTRL` | 反映自动功耗门控、NPU power-on状态和阵列时钟状态 |

### 关键设计思路

- RTL层面不进行真实门级功耗估计，而是建立可验证的低功耗行为模型。
- 当NPU处于空闲状态且自动门控开启时，power-on状态拉低。
- `tb_npu_stress`覆盖慢速DFS模式，观测到`dfs_wait_cycles=20`。
- `tb_cortex_m0_cpu_npu`验证任务完成后`npu_array_clk_en=0`。

# 4. 数据流与执行流程

## 4.1 一次完整推理/计算流程

一次4×4矩阵计算流程如下：

1. 测试平台在共享SRAM中加载Cortex-M0向量表、Thumb固件、矩阵A和矩阵B。
2. Cortex-M0复位释放后，从SRAM地址`0x0000_0000`读取初始MSP，从`0x0000_0004`读取复位入口。
3. Cortex-M0执行Thumb固件，通过AHB-Lite发起NPU寄存器写操作。
4. AHB-Lite访问经`ahb_lite_to_axil_bridge`转换为AXI-Lite访问。
5. CPU配置NPU寄存器：
   - `A_ADDR = 0x0000_0100`
   - `B_ADDR = 0x0000_0200`
   - `C_ADDR = 0x0000_0300`
   - `PE_MASK = 0x0000_FFFF`
   - `DFS_CTRL = 0`
   - `POWER_CTRL = 1`
   - `CTRL = start + irq_enable`
6. NPU DMA通过AXI Burst读取矩阵A和B。
7. NPU核心执行4×4 INT8矩阵乘法。
8. NPU DMA通过AXI Burst将16个INT32结果写回共享SRAM的C区域。
9. NPU置位完成状态并产生IRQ。
10. Cortex-M0轮询`STATUS`寄存器，检测done位后读取性能计数。
11. Cortex-M0将`PEAK_MTOPS`、DMA计数和功耗状态写入SRAM结果区，并写入完成标记`0xCAFE0001`。
12. 测试平台检查C矩阵、IRQ、低功耗状态、DMA计数和性能指标。

## 4.2 CPU与NPU零拷贝交互

系统采用共享SRAM作为数据交换区。CPU不逐字节或逐word搬运矩阵，而是仅向NPU写入共享SRAM地址。NPU内部DMA根据这些地址直接读取输入矩阵并写回输出矩阵。

| 数据 | 存储地址 | 访问方 |
| --- | --- | --- |
| 矩阵A | `0x0000_0100` | 测试平台初始化，NPU DMA读取 |
| 矩阵B | `0x0000_0200` | 测试平台初始化，NPU DMA读取 |
| 矩阵C | `0x0000_0300` | NPU DMA写回，测试平台校验 |
| CPU结果区 | `0x0000_0400` | Cortex-M0写入完成标记和性能数据 |

这种方式减少CPU数据搬运开销，保留CPU控制优势，同时发挥NPU在矩阵运算和Burst搬运上的效率。

# 5. 仿真与验证

## 5.1 仿真工具

| 项目 | 内容 |
| --- | --- |
| 编辑环境 | VS Code |
| RTL仿真器 | Icarus Verilog |
| Icarus路径 | `D:\Application\iverilog\bin` |
| 波形格式 | VCD |
| 波形查看 | GTKWave |
| 主回归脚本 | `scripts/run_all_checks.ps1` |

完整回归命令：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_all_checks.ps1
```

推荐查看主波形：

```powershell
& "D:\Application\iverilog\gtkwave\bin\gtkwave.exe" "D:\Documents\Program\IC\sim\tb_cortex_m0_cpu_npu.vcd"
```

## 5.2 测试方法

| 测试用例 | 验证目标 | 输出 |
| --- | --- | --- |
| `tb_npu_core_4x4` | 4×4有符号INT8矩阵乘法、PE掩码、空闲时钟门控 | `sim/tb_npu_core_4x4.log`, `.vcd` |
| `tb_axi_burst_dma` | AXI INCR Burst读写、地址递增、`wlast/rlast` | `sim/tb_axi_burst_dma.log`, `.vcd` |
| `tb_hetero_soc` | 不经过CPU的SoC级NPU寄存器、DMA和性能计数验证 | `sim/tb_hetero_soc.log`, `.vcd` |
| `tb_npu_stress` | DFS、重复启动、IRQ关闭、非法寄存器读、边界行为 | `sim/tb_npu_stress.log`, `.vcd` |
| `tb_cortex_m0_cpu_npu` | 真实Cortex-M0固件、AHB-Lite、AXI-Lite桥、NPU协同 | `sim/tb_cortex_m0_cpu_npu.log`, `.vcd` |

主测试`tb_cortex_m0_cpu_npu`是项目集成验证重点。该测试使用真实Cortex-M0执行预加载Thumb固件，完成NPU配置、轮询、DMA计算、指标读取和SRAM完成标记写入。

## 5.3 覆盖率说明

当前工程使用Icarus Verilog自检测试和显式功能覆盖点进行统计，覆盖结果由`docs/metrics_report.md`生成。该覆盖属于功能覆盖和路径覆盖模型，不等同于Verilator或商用工具的行/分支/翻转覆盖率。

| 覆盖类别 | 结果 |
| --- | --- |
| 功能覆盖点 | 28/28 |
| 功能覆盖率 | 100% |
| 路径覆盖点 | 52/52 |
| 路径覆盖率 | 100% |

覆盖点包括：

- 4×4 INT8矩阵乘法。
- AXI INCR Burst读写。
- CPU经AHB-Lite访问NPU寄存器。
- AHB到AXI-Lite桥接路径。
- NPU DMA读写共享SRAM。
- IRQ/done状态。
- DFS慢速模式。
- 自动功耗门控状态。
- 真实Cortex-M0 DesignStart固件执行路径。

## 5.4 AXI Burst测试方法

AXI Burst通过两类测试验证：

1. `tb_axi_burst_dma`直接驱动`axi_ram`：
   - 发起4-beat INCR写Burst。
   - 发起4-beat INCR读Burst。
   - 检查读回数据、`write_beat_count`、`read_beat_count`、`wlast`和`rlast`。

2. `tb_cortex_m0_cpu_npu`和`tb_hetero_soc`验证系统级DMA：
   - NPU DMA读取A矩阵：4 beat。
   - NPU DMA读取B矩阵：4 beat。
   - NPU DMA写回C矩阵：16 beat。
   - 检查`dma_read_beats=8`、`dma_write_beats=16`。

# 6. 性能结果

## 6.1 频率

RTL仿真和性能估算采用200 MHz目标频率。测试平台时钟周期为5 ns，与200 MHz设置一致。

## 6.2 算力

NPU通过`PEAK_MTOPS`寄存器给出峰值INT8性能指标：

```text
PEAK_MTOPS = 1024
```

换算结果：

```text
1024 MTOPS = 1.024 TOPS@INT8
```

该指标高于赛题基础要求的0.5 TOPS，并达到进一步优化目标中“接近或超过1 TOPS”的要求。

## 6.3 带宽利用率

仿真日志中记录：

```text
INFO cortex_m0 DMA data utilization percent=85
```

含义为：

```text
DMA数据有效传输周期 / DMA总活跃周期 × 100% = 85%
```

该结果高于赛题进一步优化指标中的80%目标。

## 6.4 功耗优化

本项目在RTL层面验证了以下低功耗机制：

| 机制 | 说明 | 验证结果 |
| --- | --- | --- |
| 阵列时钟门控 | `array_clk_en`仅在阵列有效运行时拉高 | 任务完成后为0 |
| 自动功耗状态 | `POWER_CTRL`反映auto power gate和NPU power状态 | 空闲状态覆盖 |
| DFS | 通过`DFS_CTRL`插入等待周期 | 压力测试观测`dfs_wait_cycles=20` |

说明：当前功耗结果为RTL状态级和行为级验证，未进行门级网表功耗仿真或FPGA板级功耗测量。

## 6.5 AI推理相关结果

项目包含MNIST INT8软件侧评估，用于说明NPU矩阵乘法数据路径可映射到标准AI推理任务。

| 指标 | 结果 |
| --- | --- |
| MNIST INT8准确率 | 82.01% |
| 正确样本数 | 8201/10000 |
| RTL估算吞吐率 | 8721.4 FPS |
| MLP估算单次推理时间 | 620.88 us |
| MLP估算吞吐率 | 1610.6 FPS |

# 7. 优化点与扩展

## 7.1 已做优化

| 优化项 | 设计体现 |
| --- | --- |
| 真实CPU集成 | 默认使用Arm Cortex-M0 DesignStart RTL，不依赖行为级stub |
| AXI标准化 | 控制面使用AXI-Lite，数据面使用AXI Burst |
| 零拷贝 | CPU传递SRAM地址，NPU DMA直接访问共享数据 |
| DMA加速 | NPU内部DMA负责矩阵输入读取和结果写回 |
| 高带宽利用率 | Burst场景DMA数据利用率达到85% |
| 动态阵列基础 | `PE_MASK`支持运行时屏蔽部分PE输出 |
| DFS建模 | `DFS_CTRL`和`DFS_WAIT`支持频率调整行为验证 |
| 低功耗建模 | 阵列时钟门控和自动功耗状态可观测 |
| 自检验证 | 5个默认testbench全部通过，生成日志和VCD |

## 7.2 可进一步优化方向

| 方向 | 说明 |
| --- | --- |
| 更完整的动态阵列 | 从输出屏蔽扩展为可重构PE连接、分块复用和稀疏计算调度 |
| 更强DMA | 增加多通道DMA、双缓冲、未对齐访问支持和更深命令队列 |
| 更高并行度 | 扩展为8×8或更大阵列，或多tile并行结构 |
| 更完善AXI互连 | 支持多主设备、多从设备、独立读写仲裁和QoS策略 |
| 真实功耗评估 | 进行综合、门级仿真、SAIF/VCD功耗分析或FPGA板级功耗测试 |
| 软件生态 | 增加C启动代码、编译链、驱动库和模型部署工具 |
| 标准AI模型 | 使用训练后的INT8 MLP/CNN权重，提高MNIST或CIFAR-10准确率 |
| FPGA验证 | 将`axi_ram`替换为片上BRAM，增加UART/调试接口，完成板级演示 |

# 8. 结论

本项目实现了一个基于真实Arm Cortex-M0 DesignStart CPU和4×4 INT8 NPU的异构处理器原型。系统采用CPU负责控制、NPU负责矩阵计算、DMA负责数据搬运、AXI负责标准化互连的架构，满足赛题对异构集成、AXI-Lite通信、AXI Burst传输、CPU/NPU协同、低功耗设计和RTL仿真的核心要求。

从验证结果看，项目完成了5个默认RTL测试用例，功能覆盖点达到28/28，路径覆盖点达到52/52。NPU峰值指标达到1.024 TOPS@INT8，DMA Burst数据利用率达到85%，并验证了阵列时钟门控、DFS等待周期和自动功耗状态。真实Cortex-M0固件能够完成NPU配置、状态轮询、结果读取和完成标记写回，证明系统具备完整的CPU+NPU协同执行能力。

该设计适用于边缘AI场景中的低功耗矩阵计算任务，可作为智能家居、工业检测、可穿戴设备等应用中本地化推理加速器的RTL原型基础。后续结合FPGA验证、真实功耗测量和更完善的软件工具链，可进一步提升工程完整性和竞赛展示效果。
