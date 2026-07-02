param(
    [string]$VivadoBat = "E:\Application\Xilinx\Vivado\2019.2\bin\vivado.bat",
    [int]$Jobs = 4,
    [string]$ExperimentName = "kc705_200mhz_dual_clock"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Test-Path $VivadoBat)) {
    throw "Vivado launcher not found: $VivadoBat"
}

$env:VIVADO_JOBS = [string]$Jobs
$env:FPGA_EXPERIMENT_NAME = $ExperimentName

& $VivadoBat -mode batch -source fpga\vivado\tcl\run_kc705_dual_clock_experiment.tcl
exit $LASTEXITCODE
