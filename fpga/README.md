# KC705 FPGA Automation

This directory contains the Vivado 2019.2 and MATLAB R2024b automation layer
for the KC705 board flow. It keeps the original Icarus/GTKWave regression path
intact and adds a board-oriented path around the existing Cortex-M0 + NPU RTL.

## Files

- `rtl/fpga_kc705_top.v`: KC705 top wrapper using the 200 MHz differential
  system clock, an MMCM-generated 200 MHz RISC-V/PicoRV32 SoC/ILA clock,
  active-high reset button, LEDs, and optional ILA probes.
- `vivado/constraints/kc705_cpu_npu.xdc`: KC705 pins from the Vivado 2019.2
  board file.
- `vivado/tcl/*.tcl`: setup, synthesis, implementation, programming, GUI, and
  ILA capture scripts.
- `vivado/mem/cortex_m0_npu_demo.mem`: SRAM preload for the Cortex-M0 demo
  firmware and matrix inputs.
- `matlab/*.m`: MATLAB helpers for memory generation, tool checks, Vivado
  invocation, and report summaries.

## Commands

Check local tool paths:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check_kc705_env.ps1
```

Update the existing Vivado project file sets:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_vivado_kc705.ps1 -Action setup
```

Run synthesis:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_vivado_kc705.ps1 -Action synth
```

Run implementation and bitstream generation:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_vivado_kc705.ps1 -Action impl
```

Program the connected KC705:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_vivado_kc705.ps1 -Action program
```

Open the GUI with the same scripted project setup:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_vivado_kc705.ps1 -Action gui
```

Use MATLAB as the driver:

```powershell
& "E:\Application\MATLAB\R2024b\bin\matlab.exe" -batch "addpath('fpga/matlab'); kc705_vivado_flow('check')"
& "E:\Application\MATLAB\R2024b\bin\matlab.exe" -batch "addpath('fpga/matlab'); kc705_vivado_flow('gen_mem')"
& "E:\Application\MATLAB\R2024b\bin\matlab.exe" -batch "addpath('fpga/matlab'); kc705_vivado_flow('summarize_reports')"
```

## Notes

- The default project is `E:\Program\Vivado\project_1\project_1.xpr`.
- The default Vivado launcher is
  `E:\Application\Xilinx\Vivado\2019.2\bin\vivado.bat`.
- The board input clock is constrained at 200 MHz; the CPU+NPU SoC and ILA
  now target a 200 MHz implementation clock.
- Set `FPGA_ENABLE_ILA=0` or pass `-NoIla` to build without the generated ILA
  IP.
- If Hardware Manager cannot see the board, run the Xilinx cable driver
  installer as Administrator:
  `E:\Application\Xilinx\Vivado\2019.2\data\xicom\cable_drivers\nt64\install_drivers.cmd`.
