param(
    [Parameter(Mandatory=$true)]
    [string]$Script
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

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

& $pythonCmd $Script
