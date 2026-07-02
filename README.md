# CPU + NPU Heterogeneous Processor Verification Showcase

> Verification-focused project for a CPU + NPU heterogeneous processor.
> This repository is intended for portfolio / application review. The RTL here
> is the verified snapshot used to demonstrate the verification flow; it is not
> claimed to be the newest design branch.

## Highlights

- Built a block-level UVM verification environment for `npu_core_4x4` and
  `npu_accel_axi`.
- Integrated a DPI-C C++ golden model for signed INT8 4x4 matrix multiplication
  with INT32 accumulation and runtime `PE_MASK` output masking.
- Verified AXI-Lite register control plus AXI4 master DMA read/write traffic
  with a reusable AXI memory slave BFM.
- Preserved the original VS Code + Icarus Verilog regression flow for fast RTL
  smoke testing.
- Ran the final UVM smoke test on QuestaSim 10.7c with `UVM_ERROR : 0`.

## What This Project Demonstrates

This project focuses on verification architecture and execution:

| Area | Evidence |
| --- | --- |
| UVM architecture | `uvm_tb/` environment, agents, sequences, scoreboard |
| DPI-C co-simulation | `uvm_tb/c_model/npu_golden_model.cpp` |
| AXI verification | AXI-Lite config agent and AXI memory slave BFM |
| Algorithm checking | Scoreboard compares RTL output against C++ golden model |
| Regression automation | `uvm_tb/sim/run.ps1`, `scripts/run_all_checks.ps1` |
| Reports | `docs/uvm_verification_plan.md`, `docs/simulation_report.md`, `docs/metrics_report.md` |

## Architecture Under Test

```text
CPU / AXI-Lite Control
        |
        v
 npu_accel_axi
   |        |
   |        +-- AXI4 master DMA reads A/B matrices and writes C matrix
   v
 npu_core_4x4
   |
   +-- 4x4 signed INT8 systolic array, INT32 accumulation
```

The UVM platform verifies two layers:

1. **Core direct verification**: drives `start`, `a_matrix`, `b_matrix`,
   `pe_mask`, and `dfs_divider` directly into `npu_core_4x4`.
2. **Accelerator verification**: configures `npu_accel_axi` through AXI-Lite,
   serves A/B matrix data through an AXI memory BFM, captures C writeback, and
   checks the result with the same DPI-C golden model.

## Repository Layout

```text
rtl/                 RTL snapshot used by the verification showcase
tb/                  Lightweight self-checking Verilog testbenches
uvm_tb/
  agent/             UVM core, AXI-Lite, and AXI memory agents
  env/               Environment, scoreboard, tests
  seq/               Core corner sequences and accelerator sequences
  c_model/           DPI-C C++ golden model and self-test
  sim/               Questa/Icarus run script and UVM filelist
docs/                Verification plan, simulation report, metrics
scripts/             Icarus regression and report generation scripts
submission/          Competition-style design/RTL/simulation documents
```

## Quick Start

### 1. Run Questa UVM Smoke Test

Default Questa path used by the script:

```text
E:\Application\questasim64_10.7c
```

Command:

```powershell
powershell -ExecutionPolicy Bypass -File uvm_tb\sim\run.ps1 -Mode questa -Test npu_smoke_test
```

Expected key result:

```text
[CORE_PASS] 7
[ACCEL_PASS] 1
UVM_ERROR : 0
```

### 2. Run Open-Source Smoke Test

Requires Icarus Verilog and MinGW `g++`:

```powershell
powershell -ExecutionPolicy Bypass -File uvm_tb\sim\run.ps1 -Mode smoke
```

This runs:

- C++ golden model self-test
- `tb_npu_core_4x4`
- `tb_axi_burst_dma`
- `tb_hetero_soc`
- `tb_npu_stress`

### 3. Run Full Local Regression

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_all_checks.ps1
```

The full Cortex-M0 test path requires a local Arm Cortex-M0 DesignStart
evaluation package. That licensed package is intentionally not part of the
public showcase repository.

## Verified Results

Last local validation:

```text
Questa UVM:
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

## Key Verification Files

- UVM top: `uvm_tb/tb/npu_uvm_top.sv`
- UVM package: `uvm_tb/npu_uvm_pkg.sv`
- AXI memory BFM: `uvm_tb/agent/axi_mem_slave_agent.svh`
- Scoreboard: `uvm_tb/env/npu_scoreboard.svh`
- Accelerator sequence: `uvm_tb/seq/npu_accel_sequences.svh`
- DPI-C golden model: `uvm_tb/c_model/npu_golden_model.cpp`
- Run script: `uvm_tb/sim/run.ps1`
- Verification plan: `docs/uvm_verification_plan.md`

## Notes For Reviewers

- The repository is a verification showcase, not the newest RTL design branch.
- Generated simulation outputs, waveform files, Questa work libraries, datasets,
  and licensed Arm package files are excluded from version control.
- The UVM smoke test does not depend on the licensed Cortex-M0 package; the full
  local SoC regression does.
