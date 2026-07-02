$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$iverilog = Get-Command iverilog -ErrorAction SilentlyContinue
if (-not $iverilog) {
    $fallback = "D:\Application\iverilog\bin\iverilog.exe"
    if (Test-Path $fallback) {
        $iverilog = $fallback
        $env:PATH = (Split-Path -Parent $fallback) + ";" + $env:PATH
    } else {
        throw "iverilog not found. Install Icarus Verilog or add it to PATH."
    }
}

New-Item -ItemType Directory -Force -Path sim | Out-Null

$vvpOut = "sim\tb_cortex_m0_cpu_npu_dual_clock.vvp"
$logOut = "sim\tb_cortex_m0_cpu_npu_dual_clock.log"

& iverilog -g2012 -Wall -Wno-timescale -I rtl -o $vvpOut -s tb_cortex_m0_cpu_npu_dual_clock -f rtl\filelist_cortexm0_dual_clock.f tb\tb_cortex_m0_cpu_npu_dual_clock.v
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& vvp $vvpOut | Tee-Object -FilePath $logOut
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$log = Get-Content -Path $logOut -Raw
if ($log -notmatch "PASS tb_cortex_m0_cpu_npu_dual_clock") {
    throw "Dual-clock Cortex-M0/NPU simulation did not report PASS. See $logOut."
}

Write-Host "Dual-clock Cortex-M0 + 200MHz NPU data-plane simulation passed."
