param()

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$fallbackIverilogBin = "D:\Application\iverilog\bin"
if (-not (Get-Command iverilog -ErrorAction SilentlyContinue) -and
    (Test-Path (Join-Path $fallbackIverilogBin "iverilog.exe"))) {
    $env:PATH = "$fallbackIverilogBin;$env:PATH"
}

if (-not (Get-Command iverilog -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: iverilog was not found in PATH." -ForegroundColor Red
    exit 127
}

New-Item -ItemType Directory -Force sim | Out-Null
& iverilog -g2012 -Wall -Wno-timescale -I rtl -o sim/cortex_m0_npu_soc_compile.vvp -s cortex_m0_npu_soc -f rtl/filelist_cortexm0.f
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
Write-Host "Cortex-M0 + NPU SoC compile check passed." -ForegroundColor Green
