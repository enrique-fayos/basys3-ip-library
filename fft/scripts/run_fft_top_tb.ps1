# Compile and run the serial-to-serial FFT regression with Vivado Simulator.
# Example:
#   .\fft\scripts\run_fft_top_tb.ps1 -VivadoBin 'C:\AMDDesignTools\2026.1\Vivado\bin'
param(
    [string]$VivadoBin = ''
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

if ($VivadoBin) {
    $compiler = Join-Path $VivadoBin 'xvlog.bat'
    $elaborator = Join-Path $VivadoBin 'xelab.bat'
    $simulator = Join-Path $VivadoBin 'xsim.bat'
} else {
    $compiler = (Get-Command xvlog.bat -ErrorAction Stop).Source
    $elaborator = (Get-Command xelab.bat -ErrorAction Stop).Source
    $simulator = (Get-Command xsim.bat -ErrorAction Stop).Source
}

$sources = @(
    'uart/rtl/uart_rx.sv',
    'uart/rtl/uart_tx.sv',
    'uart/rtl/uart.sv',
    'fft/rtl/sample_assembler.sv',
    'fft/rtl/fft_memory.sv',
    'fft/rtl/fft_twiddle_rom.sv',
    'fft/rtl/complex_butterfly.sv',
    'fft/rtl/fft_controller.sv',
    'fft/rtl/fft_core.sv',
    'fft/rtl/fft_top.sv',
    'fft/tb/fft_top_tb.sv'
) | ForEach-Object { Join-Path $repositoryRoot $_ }

# Keep simulator products outside the source tree and preserve logs for review.
$buildDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('basys3-fft-top-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $buildDirectory | Out-Null
Write-Output "Simulation files: $buildDirectory"

Push-Location $buildDirectory
try {
    & $compiler --sv @sources
    if ($LASTEXITCODE -ne 0) { throw 'SystemVerilog compilation failed.' }

    & $elaborator --debug typical --timescale 1ns/1ps work.fft_top_tb -s fft_top_tb_sim
    if ($LASTEXITCODE -ne 0) { throw 'Simulation elaboration failed.' }

    & $simulator fft_top_tb_sim --runall --onerror quit --onfinish quit --log simulation.log
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed.' }

    $log = Get-Content -LiteralPath 'simulation.log' -Raw
    if ($log -match '(?im)^\s*(Error:|Fatal:|ERROR:|FATAL:)' -or
        $log -notmatch 'PASS: All FFT top tests passed') {
        throw 'Simulation reported an error or did not reach the final PASS.'
    }
} finally {
    Pop-Location
}
