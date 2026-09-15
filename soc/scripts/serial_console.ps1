# serial_console.ps1 — 最小串口控制台（实验二 SoC 视频演示 / 终端验收用，仓库自带）
#   用途：EES-338 上跑 soc_top 时，用它当串口终端看 banner 与键盘回显。
#         它的关键性质：**只显示串口读回的字节**，键盘那一路只往串口写、绝不本地画字
#         （等价于 Tera Term 的 "Local echo 关闭"）——所以屏幕上出现的每个字符都只能来自 FPGA。
#   用法：powershell -File soc/scripts/serial_console.ps1                     # COM8 @115200，无本地回显
#         powershell -File soc/scripts/serial_console.ps1 -Port COM8 -Baud 115200 -Log my.log
#         powershell -File soc/scripts/serial_console.ps1 -LocalEcho          # 调试：每个发出的键显示 [TX:x]
#         powershell -File soc/scripts/serial_console.ps1 -RawDisplay         # 严格逐字节显示（不做换行归一）
#   行为：
#     * 默认：只显示 FPGA 发来的内容（无本地回显）；收到的内容**原样**追加写入日志文件
#     * 显示层的换行归一：FPGA 发来裸 CR 时按 CRLF 显示、并吞掉紧接其后的那个 LF
#       （等价 PuTTY/Tera Term 的 "Implicit LF in every CR" 接收端约定）。这是**显示约定**，
#       不是本地回显：换行仍然由 FPGA 回显的那个 CR 触发。要逐字节原样显示用 -RawDisplay。
#     * -LocalEcho：额外把"真正捕获并发出的键"显示成 [TX:<字符>]（**排错用；录制时必须关**，
#       否则屏幕上就分不清"是 FPGA 回显还是本地画的"）
#     * 键入即发送（Enter 只发 CR、Backspace 发 BS，都不本地画字符），Ctrl+C 退出（日志已 AutoFlush，不丢）
#   默认日志：<repo>/build/uart_log_<时间戳>.txt（build/ 不入库；也可用 -Log 指定路径）
param(
    [string]$Port = 'COM8',
    [int]   $Baud = 115200,
    [string]$Log  = '',
    [switch]$LocalEcho,
    [switch]$RawDisplay
)
# 默认日志放 <repo>/build/（gitignore 内），避免把日志写进仓库脚本目录
if (-not $Log) {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $logDir   = Join-Path $repoRoot 'build'
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $Log = Join-Path $logDir ("uart_log_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".txt")
}

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, 'None', 8, 'One'
$sp.Handshake    = 'None'
$sp.ReadTimeout  = 100
$sp.NewLine      = "`r`n"
try { $sp.Open() } catch { Write-Host ("[ERR] cannot open {0}: {1}" -f $Port, $_.Exception.Message); exit 1 }

$writer = New-Object System.IO.StreamWriter($Log, $true, [Text.Encoding]::ASCII)
$writer.AutoFlush = $true

Write-Host ("[OK] {0} @ {1} 8-N-1 opened.  Log: {2}" -f $Port, $Baud, $Log)
Write-Host ("[OK] type to send (Enter = CR). Ctrl+C to quit.  LocalEcho={0}  RawDisplay={1}" -f [bool]$LocalEcho, [bool]$RawDisplay)
if ($LocalEcho) { Write-Host "[DBG] every captured key will be shown as [TX:c] - if nothing shows up, the key never reached this window." }
$lastWasCr = $false
try {
    while ($true) {
        $n = $sp.BytesToRead
        if ($n -gt 0) {
            $buf = New-Object byte[] $n
            [void]$sp.Read($buf, 0, $n)
            $s = [Text.Encoding]::ASCII.GetString($buf)
            if ($RawDisplay) {
                Write-Host -NoNewline $s
            } else {
                # 显示层换行归一：裸 CR → CRLF；紧随 CR 的 LF 不再重复显示
                $shown = ''
                foreach ($ch in $s.ToCharArray()) {
                    if ($ch -eq "`r") { $shown += "`r`n"; $lastWasCr = $true }
                    elseif ($ch -eq "`n" -and $lastWasCr) { $lastWasCr = $false }
                    else { $shown += $ch; $lastWasCr = $false }
                }
                Write-Host -NoNewline $shown
            }
            $writer.Write($s)
        }
        if ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            switch ($k.Key) {
                'Enter'     { $sp.Write("`r"); if ($LocalEcho) { Write-Host -NoNewline "[TX:CR]" } }
                'Backspace' { $sp.Write([char]8); if ($LocalEcho) { Write-Host -NoNewline "[TX:BS]" } }
                default     {
                    if ($k.KeyChar -ne [char]0) {
                        $sp.Write([string]$k.KeyChar)
                        if ($LocalEcho) { Write-Host -NoNewline ("[TX:{0}]" -f $k.KeyChar) }
                    }
                }
            }
        }
        Start-Sleep -Milliseconds 5
    }
} finally {
    $sp.Close()
    $writer.Close()
    Write-Host ("`r`n[OK] closed. Log saved: {0}" -f $Log)
}
