param()

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$verilator = Get-Command verilator -ErrorAction SilentlyContinue
$covered = Get-Command covered -ErrorAction SilentlyContinue

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Code Coverage Tool Check")
$lines.Add("")
$lines.Add("This check records whether line/branch/toggle Verilog coverage tools are available on this machine.")
$lines.Add("")
$lines.Add("| Tool | Status | Path |")
$lines.Add("| --- | --- | --- |")
if ($verilator) {
    $lines.Add("| Verilator | available | $($verilator.Source) |")
} else {
    $lines.Add("| Verilator | not found | n/a |")
}
if ($covered) {
    $lines.Add("| covered | available | $($covered.Source) |")
} else {
    $lines.Add("| covered | not found | n/a |")
}
$lines.Add("")
$lines.Add("The current project therefore reports Icarus self-checking functional coverage in `docs/metrics_report.md`.")
$lines.Add("For strict line/branch/toggle code coverage, install Verilator or covered and reuse the same testbench set.")

[System.IO.File]::WriteAllText((Join-Path $root "docs/code_coverage_tool_check.md"), ($lines -join [Environment]::NewLine), [System.Text.Encoding]::UTF8)
Write-Host "Generated docs/code_coverage_tool_check.md"
if (-not $verilator -and -not $covered) {
    Write-Host "No Verilog code coverage tool found; functional coverage report remains the active evidence."
}
