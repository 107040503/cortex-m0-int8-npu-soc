# KC705 RISC-V 200MHz 仿真与 Vivado 实现验收记录

日期：2026-07-03

## 结论

当前已切换到 RISC-V/PicoRV32 + 自研 NPU 路线，并完成 KC705 真实 200MHz 仿真与 Vivado 实现验收。该阶段未执行真实板卡 program，符合当前“不需要实现真实板卡 program”的要求。

## 设计范围

- CPU：PicoRV32 RV32I 软核。
- NPU：现有 4x4 INT8 脉动阵列 NPU。
- SoC 集成：PicoRV32 从共享 SRAM 取指，通过 AXI-Lite MMIO 配置 NPU，NPU 通过 AXI Burst/DMA 访问共享 SRAM。
- FPGA 顶层：`fpga/rtl/fpga_kc705_riscv_top.v`。
- Vivado 目标：KC705 / `xc7k325tffg900-2`，SoC 与 ILA 采样时钟为 `soc_clk_mmcm = 5.000 ns / 200.000 MHz`。

## RTL 仿真验收

已执行命令：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_iverilog.ps1 -Top all
powershell -ExecutionPolicy Bypass -File scripts\run_iverilog.ps1 -Top tb_picorv32_cpu_npu
powershell -ExecutionPolicy Bypass -File scripts\gen_riscv_metrics_report.ps1
```

验收结果：

- `tb_picorv32_cpu_npu`：PASS。
- RTL 仿真时钟：`always #2.5 clk = ~clk;`，对应 5ns 周期 / 200MHz。
- PicoRV32 + NPU 协同：PicoRV32 执行 RV32I 固件，配置 A/B/C 零拷贝地址，启动 NPU，轮询 done/IRQ。
- NPU 峰值算力指标：`1024 MTOPS = 1.024 TOPS@INT8`。
- AXI Burst/DMA 数据利用率：`85%`，高于 80% 验收线。
- 功能覆盖模型：`27/27 = 100%`。
- 代码路径覆盖模型：`55/55 = 100%`。

主要证据文件：

- `sim/tb_picorv32_cpu_npu.log`
- `docs/riscv_metrics_report.md`
- `sim/tb_picorv32_cpu_npu.vcd`

## Vivado 200MHz 实现验收

已执行命令：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_kc705_riscv_experiment.ps1 -Jobs 4 -ExperimentName kc705_riscv_200mhz
powershell -ExecutionPolicy Bypass -File scripts\check_vivado_timing_gate.ps1 -TimingReport fpga\vivado\experiments\kc705_riscv_200mhz\reports\impl_timing_summary.rpt -ClockName soc_clk_mmcm
```

验收结果：

- Vivado 实现完成，并成功生成 bitstream。
- `soc_clk_mmcm` 时钟周期：`5.000 ns`。
- `soc_clk_mmcm` 时钟频率：`200.000 MHz`。
- Overall WNS：`0.137 ns`，满足 `WNS >= 0`。
- DRC：无 `ERROR`，无 `CRITICAL WARNING`。
- DRC 剩余非阻塞 Warning：24 条，类别为 `CHECK-3`、`PORTPROP-2`、`REQP-1839`、`RTSTAT-10`。

主要证据文件：

- `fpga/vivado/experiments/kc705_riscv_200mhz/reports/impl_timing_summary.rpt`
- `fpga/vivado/experiments/kc705_riscv_200mhz/reports/impl_drc.rpt`
- `fpga/vivado/experiments/kc705_riscv_200mhz/reports/impl_utilization.rpt`
- `fpga/vivado/bitstreams/kc705_riscv_200mhz.bit`

## ILA 保留确认

Vivado 直接流保留 `KC705_ENABLE_ILA`，并生成调试探针文件：

- `fpga/vivado/bitstreams/kc705_riscv_200mhz.ltx`

LTX 中已确认包含关键探针：

- `npu_irq`
- `npu_irq_latched`
- `npu_array_clk_en`
- `trap`
- `cycle_counter`
- `dma_read_beats`
- `dma_write_beats`

## 资源概况

实现后资源报告摘要：

- Slice LUTs：5705 / 203800，约 2.80%。
- Slice Registers：6293 / 407600，约 1.54%。
- Block RAM Tile：10.5 / 445，约 2.36%。
- DSPs：0 / 840。
- MMCME2_ADV：1 / 10。
- BUFG/BUFGCTRL：3。

## 复现入口

RISC-V 仿真指标：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_iverilog.ps1 -Top tb_picorv32_cpu_npu
powershell -ExecutionPolicy Bypass -File scripts\gen_riscv_metrics_report.ps1
```

KC705 RISC-V 200MHz Vivado 实现：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_kc705_riscv_experiment.ps1 -Jobs 4 -ExperimentName kc705_riscv_200mhz
powershell -ExecutionPolicy Bypass -File scripts\check_vivado_timing_gate.ps1 -TimingReport fpga\vivado\experiments\kc705_riscv_200mhz\reports\impl_timing_summary.rpt -ClockName soc_clk_mmcm
```

## 当前边界

- 本记录只覆盖 RISC-V/PicoRV32 路线；ARM/Cortex-M0 严格 200MHz 收敛仍属于独立路线。
- 本阶段未进行真实板卡 program 和 ILA 在线捕获；只确认 bitstream 与 LTX 已生成，ILA 未被移除。
