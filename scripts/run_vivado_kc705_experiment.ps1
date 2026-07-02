param(
    [string]$VivadoBat = "E:\Application\Xilinx\Vivado\2019.2\bin\vivado.bat",
    [int]$Jobs = 4,
    [string]$ExperimentName = "kc705_200mhz_nodspcpu",
    [string]$CortexM0PblockSliceRange = "",
    [string]$CortexM0PblockDspRange = "",
    [string]$SynthDirective = "",
    [string]$OptDirective = "",
    [string]$PlaceDirective = "",
    [string]$PhysOptDirective = "",
    [string]$RouteDirective = "",
    [string]$PostRoutePhysOptDirective = "",
    [switch]$DisableCortexM0Pblock
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Test-Path $VivadoBat)) {
    throw "Vivado launcher not found: $VivadoBat"
}

$experimentRoot = Join-Path $root "fpga\vivado\experiments\$ExperimentName"
New-Item -ItemType Directory -Force -Path $experimentRoot | Out-Null

$env:VIVADO_JOBS = [string]$Jobs
$env:FPGA_EXPERIMENT_NAME = $ExperimentName
if ($CortexM0PblockSliceRange) {
    $env:FPGA_CORTEXM0_PBLOCK_SLICE_RANGE = $CortexM0PblockSliceRange
} else {
    Remove-Item Env:\FPGA_CORTEXM0_PBLOCK_SLICE_RANGE -ErrorAction SilentlyContinue
}
if ($CortexM0PblockDspRange) {
    $env:FPGA_CORTEXM0_PBLOCK_DSP_RANGE = $CortexM0PblockDspRange
} else {
    Remove-Item Env:\FPGA_CORTEXM0_PBLOCK_DSP_RANGE -ErrorAction SilentlyContinue
}
if ($DisableCortexM0Pblock) {
    $env:FPGA_CORTEXM0_PBLOCK_DISABLE = "1"
} else {
    Remove-Item Env:\FPGA_CORTEXM0_PBLOCK_DISABLE -ErrorAction SilentlyContinue
}
if ($SynthDirective) {
    $env:FPGA_SYNTH_DIRECTIVE = $SynthDirective
} else {
    Remove-Item Env:\FPGA_SYNTH_DIRECTIVE -ErrorAction SilentlyContinue
}
if ($OptDirective) {
    $env:FPGA_OPT_DIRECTIVE = $OptDirective
} else {
    Remove-Item Env:\FPGA_OPT_DIRECTIVE -ErrorAction SilentlyContinue
}
if ($PlaceDirective) {
    $env:FPGA_PLACE_DIRECTIVE = $PlaceDirective
} else {
    Remove-Item Env:\FPGA_PLACE_DIRECTIVE -ErrorAction SilentlyContinue
}
if ($PhysOptDirective) {
    $env:FPGA_PHYS_OPT_DIRECTIVE = $PhysOptDirective
} else {
    Remove-Item Env:\FPGA_PHYS_OPT_DIRECTIVE -ErrorAction SilentlyContinue
}
if ($RouteDirective) {
    $env:FPGA_ROUTE_DIRECTIVE = $RouteDirective
} else {
    Remove-Item Env:\FPGA_ROUTE_DIRECTIVE -ErrorAction SilentlyContinue
}
if ($PostRoutePhysOptDirective) {
    $env:FPGA_POST_ROUTE_PHYS_OPT_DIRECTIVE = $PostRoutePhysOptDirective
} else {
    Remove-Item Env:\FPGA_POST_ROUTE_PHYS_OPT_DIRECTIVE -ErrorAction SilentlyContinue
}

& $VivadoBat -mode batch -log (Join-Path $experimentRoot "vivado.log") -journal (Join-Path $experimentRoot "vivado.jou") -source fpga\vivado\tcl\run_kc705_200mhz_experiment.tcl
exit $LASTEXITCODE
