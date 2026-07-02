param(
    [string]$Top = "all"
)

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
    Write-Host "Install Icarus Verilog, then reopen VS Code or refresh PATH."
    exit 127
}

if (-not (Get-Command vvp -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: vvp was not found in PATH." -ForegroundColor Red
    Write-Host "Install Icarus Verilog, then reopen VS Code or refresh PATH."
    exit 127
}

New-Item -ItemType Directory -Force sim | Out-Null

function Invoke-ToolCapture {
    param(
        [string]$Exe,
        [string[]]$Arguments,
        [string]$StdoutPath,
        [string]$StderrPath
    )

    if (Test-Path $StdoutPath) {
        Remove-Item -Force $StdoutPath
    }
    if (Test-Path $StderrPath) {
        Remove-Item -Force $StderrPath
    }

    $escapedArgs = @()
    foreach ($arg in $Arguments) {
        if ($arg -match '[\s"]') {
            $escapedArgs += '"' + ($arg -replace '"', '\"') + '"'
        } else {
            $escapedArgs += $arg
        }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = ($escapedArgs -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    return @{ Code = $proc.ExitCode; Text = ($stdout + $stderr) }
}

$tests = @()
if ($Top -eq "all") {
    $tests = @("tb_npu_core_4x4", "tb_axi_burst_dma", "tb_hetero_soc", "tb_npu_stress", "tb_cortex_m0_cpu_npu")
} else {
    $tests = @($Top)
}

$failed = 0
foreach ($test in $tests) {
    $out = "sim/$test.vvp"
    $log = "sim/$test.log"
    $compileOutTmp = "sim/$test.compile.out.tmp"
    $compileErrTmp = "sim/$test.compile.err.tmp"
    $runOutTmp = "sim/$test.run.out.tmp"
    $runErrTmp = "sim/$test.run.err.tmp"
    $filelist = "rtl/filelist.f"
    if ($test -eq "tb_picorv32_cpu_npu") {
        $filelist = "rtl/filelist_with_cpu.f"
    } elseif ($test -eq "tb_cortex_m0_cpu_npu") {
        $filelist = "rtl/filelist_cortexm0.f"
    }
    if (Test-Path $log) {
        Remove-Item -Force $log
    }
    Write-Host "==> Compile $test"
    $compileResult = Invoke-ToolCapture -Exe "iverilog" `
        -Arguments @("-g2012", "-Wall", "-Wno-timescale", "-I", "rtl", "-o", $out, "-s", $test, "-f", $filelist, "tb/$test.v") `
        -StdoutPath $compileOutTmp -StderrPath $compileErrTmp
    $compileCode = $compileResult.Code
    $compileText = $compileResult.Text
    if ($compileText) {
        Write-Host $compileText -NoNewline
        [System.IO.File]::AppendAllText((Join-Path $root $log), $compileText, [System.Text.Encoding]::UTF8)
    }
    if ($compileCode -ne 0) {
        $failed = 1
        continue
    }

    Write-Host "==> Run $test"
    $runResult = Invoke-ToolCapture -Exe "vvp" -Arguments @($out) -StdoutPath $runOutTmp -StderrPath $runErrTmp
    $runCode = $runResult.Code
    $runText = $runResult.Text
    if ($runText) {
        Write-Host $runText -NoNewline
        [System.IO.File]::AppendAllText((Join-Path $root $log), $runText, [System.Text.Encoding]::UTF8)
    }
    if ($compileCode -ne 0 -or $runCode -ne 0) {
        $failed = 1
    }
}

if ($failed -ne 0) {
    Write-Host "Simulation failed. Check sim/*.log." -ForegroundColor Red
    exit 1
}

Write-Host "All requested simulations passed." -ForegroundColor Green
