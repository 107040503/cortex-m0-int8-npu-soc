答辩/提交时重点看 tb_cortex_m0_cpu_npu.vcd 就够了，因为它覆盖了真实 Cortex-M0 + AHB-Lite + AXI-Lite 桥 + NPU + DMA + SRAM 的完整协同流程。
重点波形：
D:\Documents\Program\IC\sim\tb_cortex_m0_cpu_npu.vcd
它对应赛题最核心指标：
真实 Cortex-M0 集成
CPU/NPU 协同
AHB-Lite 到 AXI-Lite
NPU 寄存器配置
AXI Burst DMA
中断/轮询完成
DMA 利用率
低功耗时钟门控

其它波形是分模块证明用的：
sim\tb_npu_core_4x4.vcd
看 4x4 INT8 脉动阵列、PE mask、阵列时钟门控。
sim\tb_axi_burst_dma.vcd
专门看 AXI Burst 地址递增、wlast/rlast、读写 beat。
sim\tb_hetero_soc.vcd
不经过 Cortex-M0，用测试平台直接驱动 SoC，适合单独看 NPU AXI-Lite/DMA 性能指标。
sim\tb_npu_stress.vcd
看压力测试、DFS、重复启动、IRQ disable、异常寄存器访问等边界情况。
所以建议你这样用：
平时/答辩主讲：只打开 tb_cortex_m0_cpu_npu.vcd
证明 4x4 阵列细节：补充打开 tb_npu_core_4x4.vcd
证明 AXI Burst 正确性：补充打开 tb_axi_burst_dma.vcd
证明 DFS/压力测试：补充打开 tb_npu_stress.vcd
一句话：主波形看 tb_cortex_m0_cpu_npu.vcd，其它波形是专项证据。



右键信号可以改显示格式：地址/数据用 Hexadecimal，计数器用 Unsigned Decimal，矩阵结果可用 Signed Decimal。
波形怎么看指标
CPU 是否真实运行：看 u_cpu.haddr，会先访问 0x00000000/0x00000004 取向量表，然后访问 0x10000000 附近的 NPU 寄存器。
NPU 配置：CPU 会写 0x10000008/0c/10/14/2c/30/00，分别是 A/B/C 地址、PE mask、DFS、功耗、启动。
轮询完成：CPU 反复读 0x10000004，这是 NPU STATUS。
DMA 利用率：在结束时读 u_npu.dma_data_cycles 和 u_npu.dma_active_cycles，按 data * 100 / active 算，日志里是 85%。
算力：看 u_npu.peak_mtops 或 CPU 读取 NPU 0x34 寄存器，值为 1024。
Burst 搬运：结束时 dma_read_beats=8，dma_write_beats=16，表示 A/B 两个 4-beat Burst 读和 C 的 16-beat Burst 写。
低功耗：完成后 npu_array_clk_en 应该回到 0。