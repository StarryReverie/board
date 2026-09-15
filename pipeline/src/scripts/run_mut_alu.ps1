#=============================================================================
# run_mut_alu.ps1 — ALU 级故障变异矩阵（自检链对"ALU 单点故障"的防护证据）
#   用途：把 ALU 的**单个 opcode 强制返回 0**（源码见 test/mut/alu_fault_<op>.v），
#         分别跑"旧固件（or 累加）"与"当前固件"，读 dmem[0] 签名：
#           旧固件：ALU_OR / ALU_SUB / ALU_SLTU 故障会写出 0x0F（**假 PASS**）
#           当前固件：5/5 全部检出（签名 ≠ 0x0F）
#         这是 board_runbook §5.1 的实测矩阵来源。
#   用法：powershell -File pipeline/src/scripts/run_mut_alu.ps1 [-OldCommit f88bff6]
#         -OldCommit 指向"or 累加版固件"所在提交（默认 PR #11 的 f88bff6；
#         该提交不可达时跳过"旧固件"列并提示）
#   产物：<repo>/build/mut_alu_out/<op>/（日志）——build/ 不入库
#=============================================================================
param([string]$OldCommit = 'f88bff6')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$viv  = if ($env:XVIVADO_ROOT) { $env:XVIVADO_ROOT } else { 'C:\Xilinx\Vivado\2019.2' }
$outRoot = Join-Path $root 'build\mut_alu_out'
if (Test-Path $outRoot) { Remove-Item $outRoot -Recurse -Force }
New-Item -ItemType Directory -Path $outRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $root 'build\tmp') -Force | Out-Null

$ops = @('or', 'xor', 'sub', 'add', 'sltu')
$rtl = @(Get-ChildItem (Join-Path $root 'pipeline\src\rtl') -Filter '*.v' -File |
         Where-Object { $_.Name -ne 'alu.v' } | ForEach-Object { $_.FullName })
$tb  = Join-Path $root 'pipeline\src\test\mut\tb_mut_alu.v'
$curHex = Join-Path $root 'pipeline\src\test\exp1_board_demo_rom.hex'

foreach ($op in $ops) {
    $wDir = Join-Path $outRoot $op
    New-Item -ItemType Directory -Path $wDir -Force | Out-Null
    # 当前固件（新）+ 历史固件（旧，or 累加版）——TB 按这两个文件名读取
    Copy-Item $curHex (Join-Path $wDir 'exp1_board_demo_rom.hex') -Force
    $old = & git -C $root show ("{0}:pipeline/src/test/exp1_board_demo_rom.hex" -f $OldCommit) 2>$null
    if ($LASTEXITCODE -eq 0 -and $old) {
        $old | Set-Content -Path (Join-Path $wDir 'or_accum_rom.hex') -Encoding ASCII
    } else {
        Set-Content -Path (Join-Path $wDir 'or_accum_rom.hex') -Encoding ASCII -Value "@00000000`n00 00 00 00"
        Write-Host ("  [warn] {0}: 取不到历史固件（{1}），'旧固件'一列将无意义" -f $op, $OldCommit)
    }
    $alu = Join-Path $root ('pipeline\src\test\mut\alu_fault_{0}.v' -f $op)
    $srcList = ((@($rtl | ForEach-Object { '"' + $_ + '"' }) + ('"' + $alu + '"') + ('"' + $tb + '"')) -join ' ')
    $bat = @(
        '@echo off',
        ('call "' + $viv + '\settings64.bat" >nul 2>&1'),
        ('set TEMP=' + $root + '\build\tmp'),
        ('set TMP=' + $root + '\build\tmp'),
        ('cd /d "' + $wDir + '"'),
        ('call xvlog -i "' + $root + '\pipeline\src" ' + $srcList),
        'if errorlevel 1 ( echo [XVLOG_FAIL] & exit /b 2 )',
        'call xelab tb_mut_alu -s tb_mut_alu',
        'if errorlevel 1 ( echo [XELAB_FAIL] & exit /b 3 )',
        'call xsim tb_mut_alu -runall',
        'exit /b 0'
    )
    $batFile = Join-Path $wDir 'run.bat'
    Set-Content -Path $batFile -Value $bat -Encoding ASCII

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'cmd.exe'; $psi.Arguments = '/c "' + $batFile + '"'
    $psi.WorkingDirectory = $wDir; $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $o = $proc.StandardOutput.ReadToEnd(); $null = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $o | Set-Content -Path (Join-Path $wDir 'sim.log') -Encoding ASCII
    Write-Host ("--- ALU_{0} 强制 0 ---" -f $op.ToUpper())
    foreach ($ln in ($o -split "`r?`n")) {
        if ($ln -match 'ALUFAULT') { Write-Host ('  ' + $ln.Trim()) }
    }
}
Write-Host ''
Write-Host ("  日志根目录: {0}" -f $outRoot)
