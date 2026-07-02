param(
    [ValidateSet("setup", "synth", "impl", "program", "capture", "gui")]
    [string]$Action = "setup",
    [string]$VivadoBat = "E:\Application\Xilinx\Vivado\2019.2\bin\vivado.bat",
    [string]$ProjectXpr = "E:\Program\Vivado\project_1\project_1.xpr",
    [int]$Jobs = 4,
    [int]$MaxDsp = -1,
    [string]$BitstreamName = "kc705_cpu_npu",
    [string]$SynthDirective = "",
    [string]$OptDirective = "",
    [string]$PlaceDirective = "",
    [string]$PhysOptDirective = "",
    [string]$RouteDirective = "",
    [string]$PostRoutePhysOptDirective = "",
    [string]$TimingClockName = "soc_clk_mmcm",
    [switch]$CortexM0NoDspMult,
    [switch]$NoIla
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Test-Path $VivadoBat)) {
    throw "Vivado launcher not found: $VivadoBat"
}
if (-not (Test-Path $ProjectXpr)) {
    throw "Vivado project not found: $ProjectXpr"
}

$bitFile = Join-Path $root "fpga\vivado\bitstreams\$BitstreamName.bit"
$ltxFile = Join-Path $root "fpga\vivado\bitstreams\$BitstreamName.ltx"
$mainTimingReport = Join-Path $root "fpga\vivado\reports\impl_timing_summary.rpt"
$experimentTimingReport = Join-Path $root "fpga\vivado\experiments\$BitstreamName\reports\impl_timing_summary.rpt"

$env:VIVADO_PROJECT_XPR = $ProjectXpr
$env:VIVADO_JOBS = [string]$Jobs
$env:FPGA_BOARD = "kc705"
$env:FPGA_PART = "xc7k325tffg900-2"
$env:FPGA_BOARD_PART = "xilinx.com:kc705:part0:1.6"
$env:FPGA_XDC = "fpga/vivado/constraints/kc705_cpu_npu.xdc"
$env:FPGA_BITSTREAM_NAME = $BitstreamName
$env:FPGA_EXPECTED_DEVICE = "xc7k325t"
$env:FPGA_START_DELAY_CYCLES = "32'hEE6B2800"
$env:BIT_FILE = $bitFile
$env:LTX_FILE = $ltxFile

if ($MaxDsp -ge 0) {
    $env:FPGA_MAX_DSP = [string]$MaxDsp
} else {
    Remove-Item Env:\FPGA_MAX_DSP -ErrorAction SilentlyContinue
}

if ($SynthDirective) { $env:FPGA_SYNTH_DIRECTIVE = $SynthDirective } else { Remove-Item Env:\FPGA_SYNTH_DIRECTIVE -ErrorAction SilentlyContinue }
if ($OptDirective) { $env:FPGA_OPT_DIRECTIVE = $OptDirective } else { Remove-Item Env:\FPGA_OPT_DIRECTIVE -ErrorAction SilentlyContinue }
if ($PlaceDirective) { $env:FPGA_PLACE_DIRECTIVE = $PlaceDirective } else { Remove-Item Env:\FPGA_PLACE_DIRECTIVE -ErrorAction SilentlyContinue }
if ($PhysOptDirective) { $env:FPGA_PHYS_OPT_DIRECTIVE = $PhysOptDirective } else { Remove-Item Env:\FPGA_PHYS_OPT_DIRECTIVE -ErrorAction SilentlyContinue }
if ($RouteDirective) { $env:FPGA_ROUTE_DIRECTIVE = $RouteDirective } else { Remove-Item Env:\FPGA_ROUTE_DIRECTIVE -ErrorAction SilentlyContinue }
if ($PostRoutePhysOptDirective) { $env:FPGA_POST_ROUTE_PHYS_OPT_DIRECTIVE = $PostRoutePhysOptDirective } else { Remove-Item Env:\FPGA_POST_ROUTE_PHYS_OPT_DIRECTIVE -ErrorAction SilentlyContinue }
if ($CortexM0NoDspMult) { $env:FPGA_CORTEXM0_NO_DSP_MULT = "1" } else { Remove-Item Env:\FPGA_CORTEXM0_NO_DSP_MULT -ErrorAction SilentlyContinue }

if ($NoIla) {
    $env:FPGA_ENABLE_ILA = "0"
} else {
    $env:FPGA_ENABLE_ILA = "1"
}

$scriptMap = @{
    setup   = "fpga/vivado/tcl/setup_project.tcl"
    synth   = "fpga/vivado/tcl/run_synth.tcl"
    impl    = "fpga/vivado/tcl/run_impl.tcl"
    program = "fpga/vivado/tcl/program_hw.tcl"
    capture = "fpga/vivado/tcl/capture_ila.tcl"
    gui     = "fpga/vivado/tcl/open_gui.tcl"
}

$tcl = Join-Path $root $scriptMap[$Action]
if (-not (Test-Path $tcl)) {
    throw "Tcl script not found: $tcl"
}

if ($Action -eq "program" -or $Action -eq "capture") {
    $timingReport = $mainTimingReport
    if (Test-Path $experimentTimingReport) {
        $timingReport = $experimentTimingReport
    }
    powershell -ExecutionPolicy Bypass -File (Join-Path $root "scripts\check_vivado_timing_gate.ps1") -TimingReport $timingReport -ClockName $TimingClockName
}

if ($Action -eq "gui") {
    & $VivadoBat -mode gui -source $tcl
} else {
    & $VivadoBat -mode batch -source $tcl
}
exit $LASTEXITCODE
