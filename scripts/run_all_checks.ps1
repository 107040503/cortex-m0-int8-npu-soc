param()

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

powershell -ExecutionPolicy Bypass -File scripts/run_iverilog.ps1 -Top all
powershell -ExecutionPolicy Bypass -File scripts/check_cpu_compile.ps1
powershell -ExecutionPolicy Bypass -File scripts/gen_metrics_report.ps1
powershell -ExecutionPolicy Bypass -File scripts/check_coverage_tools.ps1

$pythonCmd = $null
foreach ($candidate in @("python", "py", "python3")) {
    if (Get-Command $candidate -ErrorAction SilentlyContinue) {
        $pythonCmd = $candidate
        break
    }
}
if (-not $pythonCmd) {
    throw "No Python launcher found. Install Python or add it to PATH."
}

& $pythonCmd scripts/gen_ai_perf_report.py
& $pythonCmd scripts/mnist_int8_eval.py

Write-Host "All RTL checks and reports completed." -ForegroundColor Green
