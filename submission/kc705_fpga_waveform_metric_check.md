# KC705 FPGA 上板与 ILA 验证记录

## 1. 验证范围

本记录对应当前工程的 KC705-only Vivado 流程，目标器件为 `xc7k325tffg900-2`，板卡 part 为 `xilinx.com:kc705:part0:1.6`。本次验证使用 Vivado 2019.2 对 `fpga_kc705_top` 进行带 ILA 综合、实现、生成 bitstream，并通过 JTAG 下载到真实 KC705 板卡后导出 ILA CSV 波形。

需要特别说明：当前 KC705 FPGA wrapper 为稳妥上板调试，将板载 200 MHz 差分时钟经 MMCM 分频为 50 MHz SoC/ILA 调试时钟。200 MHz、1.024 TOPS@INT8、覆盖率和 MNIST 指标来自 RTL 回归与性能报告；本页的 FPGA 证据证明真实板卡上 CPU/NPU/DMA/ILA 链路可运行，并给出板上 ILA 计数器观测值。

## 2. 关键命令与产物

| 项目 | 命令/产物 | 结果 |
| --- | --- | --- |
| 环境检查 | `powershell -ExecutionPolicy Bypass -File scripts/check_kc705_env.ps1` | Vivado、KC705 board file、工程、MATLAB 目录检查通过 |
| RTL 回归 | `powershell -ExecutionPolicy Bypass -File scripts/run_all_checks.ps1` | 已通过，见 `docs/metrics_report.md` |
| 带 ILA 综合 | `powershell -ExecutionPolicy Bypass -File scripts/run_vivado_kc705.ps1 -Action synth` | `synth_1 status: synth_design Complete!` |
| 带 ILA 实现 | `powershell -ExecutionPolicy Bypass -File scripts/run_vivado_kc705.ps1 -Action impl` | `impl_1 status: write_bitstream Complete!` |
| 上板与捕获 | `powershell -ExecutionPolicy Bypass -File scripts/run_vivado_kc705.ps1 -Action capture` | `Programmed xc7k325t`，ILA 触发并导出 CSV |

主要 FPGA 产物：

| 文件 | 说明 |
| --- | --- |
| `fpga/vivado/bitstreams/kc705_cpu_npu.bit` | KC705 bitstream，含 ILA |
| `fpga/vivado/bitstreams/kc705_cpu_npu.ltx` | ILA probes 文件 |
| `fpga/vivado/captures/20260629_222851_hw_ila_1.csv` | 真实板卡 ILA 捕获 CSV |
| `fpga/vivado/captures/kc705_ila_capture_20260629_222851.txt` | 捕获摘要 |
| `fpga/vivado/reports/impl_timing_summary.rpt` | 实现后 timing summary |
| `fpga/vivado/reports/impl_drc.rpt` | 实现后 DRC |
| `fpga/vivado/reports/impl_utilization.rpt` | 资源利用率 |
| `fpga/vivado/reports/impl_power.rpt` | Vivado 向量缺省功耗估算 |

## 3. Vivado 实现结果

| 指标 | 结果 |
| --- | --- |
| 器件 | `xc7k325t` |
| bitstream | 生成成功 |
| ILA core | 1 个 ILA core，`u_ila_cpu_npu` |
| Timing | 通过，`All user specified timing constraints are met.` |
| WNS/TNS | WNS = `3.087 ns`，TNS = `0.000 ns` |
| WHS/THS | WHS = `0.043 ns`，THS = `0.000 ns` |
| DRC | 0 Error，0 Critical Warning，15 Warning |
| LUT | 16362 / 203800，8.03% |
| FF | 6429 / 407600，1.58% |
| BRAM tile | 6.5 / 445，1.46% |
| DSP | 3 / 840，0.36% |
| Vivado power estimate | Total On-Chip Power = `0.315 W`，Dynamic = `0.158 W`，Device Static = `0.158 W` |

DRC warning 分类如下：DSP pipeline 建议类 `DPIP-1/DPOP-1/DPOP-2`，KC705 输入差分终端属性 `PORTPROP-2`，以及 debug hub/ILA 内部无 routable loads `RTSTAT-10`。这些不是 bitstream 阻断项，本次实现和下载均成功。

## 4. ILA Probe 映射

| Probe | 信号 | 用途 |
| --- | --- | --- |
| probe0 | `npu_irq` | NPU 完成中断 |
| probe1 | `npu_irq_latched` | IRQ 锁存，便于 LED/ILA 观察 |
| probe2 | `npu_array_clk_en` | 4x4 脉动阵列时钟门控使能 |
| probe3 | `cpu_halted` | CPU halted 状态 |
| probe4 | `debug_resetn` | SoC 复位释放 |
| probe5 | `ram_write_beats[31:0]` | RAM/AXI 写 beat 计数 |
| probe6 | `ram_read_beats[31:0]` | RAM/AXI 读 beat 计数 |
| probe7 | `cycle_counter[31:0]` | 板上运行周期计数 |
| probe8 | `dma_active_cycles[31:0]` | DMA/Burst 活跃窗口周期 |
| probe9 | `dma_data_cycles[31:0]` | DMA/Burst 有效数据周期 |
| probe10 | `dma_read_beats[31:0]` | DMA 读 beat 计数 |
| probe11 | `dma_write_beats[31:0]` | DMA 写 beat 计数 |

触发条件为 `debug_resetn == 1`。KC705 wrapper 设置了 `FPGA_START_DELAY_CYCLES=1000000000`，在 50 MHz 调试时钟下约为 20 秒，便于先 arm ILA，再释放 SoC。

## 5. ILA 波形分析

ILA 捕获文件共有 1024 个有效采样点。关键事件如下：

| 事件 | ILA sample | 说明 |
| --- | ---: | --- |
| `debug_resetn` 拉高 | 16 | 20 秒启动延迟结束，SoC 复位释放 |
| `ram_read_beats` 首次非零 | 22 | CPU/总线开始从 RAM 读数据 |
| `dma_active_cycles` 首次非零 | 98 | NPU DMA/Burst 窗口开始 |
| `dma_data_cycles` 首次非零 | 99 | Burst 数据有效传输开始 |
| `dma_read_beats` 首次非零 | 99 | DMA 读 beat 到达 |
| `npu_array_clk_en` 首次为 1 | 109 | 脉动阵列时钟门控打开，NPU 进入计算窗口 |
| `dma_write_beats` 首次非零 | 124 | DMA 写回结果开始 |
| `ram_write_beats` 首次非零 | 124 | RAM 写 beat 出现 |
| `npu_irq` 拉高 | 141 | NPU 完成并发出 IRQ |
| `npu_irq_latched` 拉高 | 142 | IRQ 被板级逻辑锁存 |

捕获窗口末尾的关键计数：

| 信号 | 末值 | 十进制 |
| --- | --- | ---: |
| `cycle_counter[31:0]` | `000003ef` | 1007 |
| `ram_write_beats[31:0]` | `00000015` | 21 |
| `ram_read_beats[31:0]` | `0000010d` | 269 |
| `dma_active_cycles[31:0]` | `0000001c` | 28 |
| `dma_data_cycles[31:0]` | `00000018` | 24 |
| `dma_read_beats[31:0]` | `00000008` | 8 |
| `dma_write_beats[31:0]` | `00000010` | 16 |

板上 ILA 观测到的 Burst/DMA 数据周期利用率：

```text
DMA/Burst utilization = dma_data_cycles / dma_active_cycles
                      = 24 / 28
                      = 85.71%
```

结论：真实 KC705 上，CPU/NPU SoC 能够完成复位释放、存储器访问、DMA/Burst 数据搬运、NPU 计算、结果写回和 IRQ 完成路径；`npu_array_clk_en` 只在计算窗口拉高，之后回到 0，证明阵列空闲时钟门控在板上可观察。

## 6. 指标对照

| 指标 | 证据 | 状态 |
| --- | --- | --- |
| Cortex-M0 + 32 位 NPU 集成 | RTL 回归报告记录 Cortex-M0 DesignStart AHB 配置、AHB-to-AXI-Lite bridge、CPU/NPU poll/IRQ 路径；KC705 ILA 看到 IRQ 完成 | 达成 |
| 4x4 脉动阵列 | Vivado 层级和综合日志包含 `npu_core_4x4`、`systolic_array_4x4`、16 个 `int8_mac_pe` 实例 | 达成 |
| AXI-Lite 控制 | RTL 回归覆盖 `soc_axil_control`、`axil_write_ctrl_start_irq`、`axil_read_status_busy_done` | 达成 |
| AXI Burst 地址递增 | RTL 回归覆盖 `axi_incr_write_burst`、`axi_incr_read_burst`、`axi_ram_incr_address` | 达成 |
| CPU/NPU 协同 | RTL 回归通过 `tb_cortex_m0_cpu_npu`；KC705 ILA 看到读 RAM、DMA、阵列使能、IRQ 顺序 | 达成 |
| RTL 95%+ 路径覆盖 | `docs/metrics_report.md` 中功能覆盖 28/28，路径覆盖 52/52，均为 100% | 达成 |
| 200 MHz RTL 频率设定 | RTL 指标报告按 200 MHz 计算；Vivado KC705 bring-up wrapper 当前使用 50 MHz SoC/ILA 调试时钟 | RTL 达成，FPGA 当前为 50 MHz bring-up |
| NPU 峰值算力 >= 0.5 TOPS@INT8 | `docs/metrics_report.md` 记录 peak = 1024 MTOPS = 1.024 TOPS | 达成 |
| Burst 利用率 >= 60% / 优化目标 >=80% | RTL 报告 85%；KC705 ILA 实测窗口 85.71% | 达成 |
| 时钟门控低功耗 | RTL 覆盖 `core_clock_gate_idle`、`soc_power_gate_idle`；KC705 ILA 看到 `npu_array_clk_en` 计算窗口拉高，完成后回到 0 | 达成 |
| FPGA 验证加分项 | KC705 `xc7k325t` 真实板卡 program 成功并导出 ILA CSV | 达成 |

## 7. 剩余风险与建议

1. 当前 FPGA wrapper 为 50 MHz 调试上板频率；若要宣称 FPGA 200 MHz 运行，需要将 SoC 时钟提高到 200 MHz，并重新完成 timing、program、ILA 捕获。
2. Vivado power report 是向量缺省估算，尚不是外部电源仪表实测功耗；如果评分要求功耗实测，需要用 KC705 电源监控/外部功率计记录不同负载功耗。
3. 当前 FPGA ILA 捕获窗口较短，已覆盖一次启动到完成路径；若要做压力测试，建议增加 ILA depth 或加入 VIO/重启控制，连续触发多组任务。
4. RISC-V CPU 路径如需同等上板证据，需要替换/并列 RISC-V SoC 顶层并重复本流程。
