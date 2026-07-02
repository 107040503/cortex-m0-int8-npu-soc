param(
    [string]$TimingReport = "fpga\vivado\reports\impl_timing_summary.rpt",
    [string]$ClockName = "soc_clk_mmcm",
    [double]$ExpectedPeriodNs = 5.000,
    [double]$ExpectedFrequencyMhz = 200.000,
    [double]$MinWnsNs = 0.000,
    [double]$Tolerance = 0.001
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Test-Path $TimingReport)) {
    throw "Timing report not found: $TimingReport"
}

$lines = Get-Content -Path $TimingReport

$wns = $null
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*WNS\(ns\)\s+TNS\(ns\)') {
        for ($j = $i + 1; $j -lt [Math]::Min($i + 8, $lines.Count); $j++) {
            if ($lines[$j] -match '^\s*(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+(\d+)') {
                $wns = [double]$matches[1]
                break
            }
        }
        if ($null -ne $wns) {
            break
        }
    }
}

if ($null -eq $wns) {
    throw "Could not parse overall WNS from timing report: $TimingReport"
}

$clockPattern = '^\s*' + [Regex]::Escape($ClockName) + '\s+\{[^}]+\}\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s*$'
$clockPeriod = $null
$clockFrequency = $null
foreach ($line in $lines) {
    if ($line -match $clockPattern) {
        $clockPeriod = [double]$matches[1]
        $clockFrequency = [double]$matches[2]
        break
    }
}

if ($null -eq $clockPeriod) {
    throw "Could not find clock '$ClockName' in timing report: $TimingReport"
}

$periodOk = [Math]::Abs($clockPeriod - $ExpectedPeriodNs) -le $Tolerance
$frequencyOk = [Math]::Abs($clockFrequency - $ExpectedFrequencyMhz) -le $Tolerance
$wnsOk = $wns -ge $MinWnsNs

Write-Host ("Timing gate report: {0}" -f (Resolve-Path $TimingReport))
Write-Host ("Clock {0}: period={1:N3} ns, frequency={2:N3} MHz" -f $ClockName, $clockPeriod, $clockFrequency)
Write-Host ("Overall WNS: {0:N3} ns" -f $wns)

if (-not $periodOk) {
    throw "Timing gate failed: $ClockName period is $clockPeriod ns, expected $ExpectedPeriodNs ns."
}
if (-not $frequencyOk) {
    throw "Timing gate failed: $ClockName frequency is $clockFrequency MHz, expected $ExpectedFrequencyMhz MHz."
}
if (-not $wnsOk) {
    throw "Timing gate failed: WNS is $wns ns, required >= $MinWnsNs ns. Do not program this bitstream as a 200MHz signoff image."
}

Write-Host "Timing gate passed."
