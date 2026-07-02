param(
    [string]$VivadoRoot = "E:\Application\Xilinx\Vivado\2019.2",
    [string]$MatlabRoot = "E:\Application\MATLAB\R2024b",
    [string]$ProjectXpr = "E:\Program\Vivado\project_1\project_1.xpr"
)

$ErrorActionPreference = "Stop"

$checks = @(
    @{ Name = "Vivado 2019.2 launcher"; Path = Join-Path $VivadoRoot "bin\vivado.bat" },
    @{ Name = "Vivado hw_server"; Path = Join-Path $VivadoRoot "bin\hw_server.bat" },
    @{ Name = "KC705 board file"; Path = Join-Path $VivadoRoot "data\boards\board_files\kc705\1.6\board.xml" },
    @{ Name = "KC705 pin file"; Path = Join-Path $VivadoRoot "data\boards\board_files\kc705\1.6\part0_pins.xml" },
    @{ Name = "Xilinx cable driver installer"; Path = Join-Path $VivadoRoot "data\xicom\cable_drivers\nt64\install_drivers.cmd" },
    @{ Name = "Vivado project"; Path = $ProjectXpr },
    @{ Name = "MATLAB R2024b"; Path = Join-Path $MatlabRoot "bin\matlab.exe" },
    @{ Name = "MATLAB HDL Coder folder"; Path = Join-Path $MatlabRoot "toolbox\hdlcoder" },
    @{ Name = "MATLAB HDL Verifier folder"; Path = Join-Path $MatlabRoot "toolbox\hdlverifier" },
    @{ Name = "MATLAB Fixed-Point Designer folder"; Path = Join-Path $MatlabRoot "toolbox\fixedpoint" }
)

foreach ($check in $checks) {
    $ok = Test-Path $check.Path
    $status = if ($ok) { "OK" } else { "MISSING" }
    [pscustomobject]@{
        Status = $status
        Name = $check.Name
        Path = $check.Path
    }
}

Write-Host ""
Write-Host "If USB-JTAG is not detected in Vivado Hardware Manager, run the Xilinx cable driver installer as Administrator:"
Write-Host "  $((Join-Path $VivadoRoot 'data\xicom\cable_drivers\nt64\install_drivers.cmd'))"
