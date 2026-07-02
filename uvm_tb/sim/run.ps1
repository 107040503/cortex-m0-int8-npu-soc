param(
    [ValidateSet("smoke", "questa", "vcs", "all")]
    [string]$Mode = "smoke",
    [string]$Test = "npu_smoke_test",
    [string]$QuestaHome = "E:\Application\questasim64_10.7c",
    [string]$License = ""
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $root

$buildDir = Join-Path $root "uvm_tb\sim\build"
New-Item -ItemType Directory -Force $buildDir | Out-Null

if ($License) {
    $env:MGLS_LICENSE_FILE = $License
    $env:LM_LICENSE_FILE = $License
} else {
    foreach ($name in @("MGLS_LICENSE_FILE", "LM_LICENSE_FILE", "MENTOR_LICENSE_FILE")) {
        if (-not [Environment]::GetEnvironmentVariable($name, "Process")) {
            $value = [Environment]::GetEnvironmentVariable($name, "User")
            if (-not $value) {
                $value = [Environment]::GetEnvironmentVariable($name, "Machine")
            }
            if ($value) {
                [Environment]::SetEnvironmentVariable($name, $value, "Process")
            }
        }
    }
}

function Find-Tool {
    param([string[]]$Names)
    $extraBins = @(
        (Join-Path $QuestaHome "win64"),
        "D:\Application\questasim64_10.7c\win64"
    )

    foreach ($name in $Names) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) {
            return $cmd.Source
        }

        foreach ($bin in $extraBins) {
            $candidate = Join-Path $bin $name
            if (Test-Path $candidate) {
                return $candidate
            }
            $candidateExe = Join-Path $bin "$name.exe"
            if (Test-Path $candidateExe) {
                return $candidateExe
            }
        }
    }
    return $null
}

function Invoke-Logged {
    param(
        [string]$Exe,
        [string[]]$Arguments
    )

    Write-Host "==> $Exe $($Arguments -join ' ')"
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Exe failed with exit code $LASTEXITCODE"
    }
}

function Run-GoldenSelfTest {
    $gpp = Find-Tool @("g++")
    if (-not $gpp) {
        $fallback = "D:\Application\mingw64\bin\g++.exe"
        if (Test-Path $fallback) {
            $gpp = $fallback
        }
    }
    if (-not $gpp) {
        throw "g++ was not found; cannot build the C++ golden-model self-test."
    }

    $exe = Join-Path $buildDir "npu_golden_selftest.exe"
    Invoke-Logged $gpp @(
        "-std=c++17",
        "-Wall",
        "-Wextra",
        "-I", "uvm_tb/c_model",
        "uvm_tb/c_model/npu_golden_model.cpp",
        "uvm_tb/c_model/npu_golden_selftest.cpp",
        "-o", $exe
    )
    Invoke-Logged $exe @()
}

function Run-IcarusSmoke {
    $script = Join-Path $root "scripts\run_iverilog.ps1"
    if (-not (Test-Path $script)) {
        Write-Host "Skipping Icarus RTL smoke: scripts/run_iverilog.ps1 not found." -ForegroundColor Yellow
        return
    }

    Invoke-Logged "powershell" @("-ExecutionPolicy", "Bypass", "-File", $script, "-Top", "tb_npu_core_4x4")
    Invoke-Logged "powershell" @("-ExecutionPolicy", "Bypass", "-File", $script, "-Top", "tb_axi_burst_dma")
    Invoke-Logged "powershell" @("-ExecutionPolicy", "Bypass", "-File", $script, "-Top", "tb_hetero_soc")
    Invoke-Logged "powershell" @("-ExecutionPolicy", "Bypass", "-File", $script, "-Top", "tb_npu_stress")
}

function Run-Questa {
    $vlib = Find-Tool @("vlib")
    $vmap = Find-Tool @("vmap")
    $vlog = Find-Tool @("vlog")
    $vsim = Find-Tool @("vsim")
    if (-not ($vlib -and $vmap -and $vlog -and $vsim)) {
        throw "Questa commands vlib/vmap/vlog/vsim were not found."
    }

    $workLib = Join-Path $buildDir "work"
    $questaIni = Join-Path $buildDir "modelsim.ini"
    Push-Location $root
    try {
        Invoke-Logged $vlib @($workLib)
        Invoke-Logged $vmap @("-c")
        if (Test-Path "modelsim.ini") {
            Move-Item -Force "modelsim.ini" $questaIni
        }
        Invoke-Logged $vmap @("-modelsimini", $questaIni, "work", $workLib)
        Invoke-Logged $vlog @(
            "-modelsimini", $questaIni,
            "-work", "work",
            "-sv",
            "-mfcu",
            "+acc",
            "+define+DUMP_VCD",
            "-ccflags", "-std=c++17 -DNPU_DPI_BUILD -Iuvm_tb/c_model",
            "-f", "uvm_tb/sim/uvm_filelist.f",
            "uvm_tb/c_model/npu_golden_model.cpp"
        )
    } finally {
        Pop-Location
    }

    Push-Location $buildDir
    try {
        Invoke-Logged $vsim @(
            "-modelsimini", "modelsim.ini",
            "-c",
            "work.npu_uvm_top",
            "+UVM_TESTNAME=$Test",
            "+UVM_VERBOSITY=UVM_MEDIUM",
            "-do", "run -all; quit -f"
        )
    } finally {
        Pop-Location
    }
}

function Run-Vcs {
    $vcs = Find-Tool @("vcs")
    if (-not $vcs) {
        throw "VCS was not found."
    }

    Invoke-Logged $vcs @(
        "-full64",
        "-sverilog",
        "-ntb_opts", "uvm",
        "+define+DUMP_VCD",
        "-f", "uvm_tb/sim/uvm_filelist.f",
        "uvm_tb/c_model/npu_golden_model.cpp",
        "-CFLAGS", "-std=c++17 -DNPU_DPI_BUILD -Iuvm_tb/c_model",
        "-o", "uvm_tb/sim/build/simv"
    )
    Invoke-Logged "uvm_tb/sim/build/simv" @("+UVM_TESTNAME=$Test")
}

if ($Mode -eq "smoke" -or $Mode -eq "all") {
    Run-GoldenSelfTest
    Run-IcarusSmoke
}

if ($Mode -eq "questa" -or $Mode -eq "all") {
    Run-Questa
}

if ($Mode -eq "vcs" -or $Mode -eq "all") {
    Run-Vcs
}

Write-Host "Requested UVM verification flow completed." -ForegroundColor Green
