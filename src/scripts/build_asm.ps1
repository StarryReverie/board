<#
=============================================================================
 build_asm.ps1 — 汇编测试程序 → 机器码镜像（T31 前置工具）
   * 输入: test/*.asm
   * 输出: test/<名>_rom.hex（objcopy -O verilog 字节式，$readmemh 直读）
   * 副产品(scripts/out/asm/): .o 与 objdump 反汇编清单（供核对/报告）
   * 工具: riscv-none-elf-as（xPack GNU RISC-V，PATH 或默认安装目录）
   * 用法: .\scripts\build_asm.ps1 [-One <basename>]
=============================================================================
#>
param([string]$One = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# ---- 定位工具链 ----
$as = Get-Command riscv-none-elf-as -ErrorAction SilentlyContinue
if (-not $as) {
    $guess = 'E:\Homework\26-27-1\tools\xpack-riscv-none-elf-gcc-15.2.0-1\bin'
    if (Test-Path (Join-Path $guess 'riscv-none-elf-as.exe')) {
        $env:Path = $guess + ';' + $env:Path
    } else {
        Write-Error '找不到 riscv-none-elf-as（PATH 或默认安装目录）'; exit 1
    }
}

$asmDir = Join-Path $root 'test'
$outDir = Join-Path $PSScriptRoot 'out\asm'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$files = @(Get-ChildItem -Path $asmDir -Filter '*.asm' -File)
if ($One) { $files = @($files | Where-Object { $_.BaseName -eq $One }) }
if ($files.Count -eq 0) { Write-Host '[提示] 没有 .asm 可构建'; exit 0 }

foreach ($f in $files) {
    $base = $f.BaseName
    $o    = Join-Path $outDir "$base.o"
    $hex  = Join-Path $asmDir "${base}_rom.hex"
    $lst  = Join-Path $outDir "$base.lst"

    & riscv-none-elf-as -march=rv32i -mabi=ilp32 -o $o $f.FullName
    if ($LASTEXITCODE -ne 0) { Write-Host "[FAIL] as $base"; exit 1 }
    & riscv-none-elf-objcopy -O verilog $o $hex
    if ($LASTEXITCODE -ne 0) { Write-Host "[FAIL] objcopy $base"; exit 1 }
    & riscv-none-elf-objdump -d $o > $lst

    $words = ((Get-Content $hex | Where-Object { $_ -notmatch '^@' }) -join ' ').Split(' ',
             [System.StringSplitOptions]::RemoveEmptyEntries).Count / 4
    Write-Host ("[OK] {0,-12} -> {1}_rom.hex  ({2} 指令)" -f $base, $base, $words)
}
Write-Host 'build_asm done'
