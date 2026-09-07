<#
=============================================================================
 fix_encoding.ps1 — 乱码文本修复工具（GBK 误读类二次损坏 → UTF-8）
   * 背景：ref/CPU/（大三参考工程）注释原为 GBK 中文，曾被按错误代码页
     解读后以 UTF-8 保存 → 内容出现「鎸囦护閫氳矾」类乱码字符。
   * 修复链（每行启发式，已实测验证）：
       乱码行 → GBK 编码 → 严格 UTF-8 解码 = 原中文
     ASCII 行 / 已是合法 UTF-8 中文的行 / GBK 编码后非 UTF-8 的行 → 不动
   * 用法：
       .\fix_encoding.ps1              # 扫描报告（不改文件）
       .\fix_encoding.ps1 -Apply       # 实际修复（写回 UTF-8 无 BOM）
       .\fix_encoding.ps1 -Root <目录> # 指定扫描根（默认仓库根）
   * 产物为纯文本 UTF-8；不触碰 .git/out/vivado 等目录
=============================================================================
#>
param(
    [string]$Root = '',       # 扫描根（默认：本脚本所在仓库根）
    [switch]$Apply            # 缺省=仅报告
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent $scriptDir) }  # 仓库根
$gbk   = [Text.Encoding]::GetEncoding(936)
$utf8  = New-Object System.Text.UTF8Encoding($false)
$utf8S = New-Object System.Text.UTF8Encoding($false, $true)   # 严格解码用

$allowExt = '.v','.vh','.asm','.txt','.md','.tcl','.ps1','.py','.csv','.bat','.f','.s','.S'
$excludeDir = '\\.git$|\\out$|\\vivado$|\\.Xil$|\\xsim.dir$'

# ---- 收集文本文件 ----------------------------------------------------------
$files = @(Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $n = $_.Name.ToLower()
        ($allowExt -contains $_.Extension.ToLower() -or $n -eq 'makefile') -and
        $_.FullName -notmatch $excludeDir
    })

# ---- 单行修复：成功返回新行，否则返回 $null --------------------------------
function Test-FixLine([string]$line) {
    if ($line -eq '') { return $null }
    $nonAscii = $false
    foreach ($ch in $line.ToCharArray()) { if ([int]$ch -gt 127) { $nonAscii = $true; break } }
    if (-not $nonAscii) { return $null }                       # 纯 ASCII 行
    $bytes = $gbk.GetBytes($line)
    try { $dec = $utf8S.GetString($bytes) } catch { return $null }  # GBK 码非 UTF-8 → 已是正确文本
    if ($dec -eq $line) { return $null }                       # 无变化
    if ($dec -notmatch '[\u4e00-\u9fff]') { return $null }     # 结果无汉字 → 可疑，保守跳过
    return $dec
}

# ---- 逐文件处理 ------------------------------------------------------------
$changed = 0; $gbkFiles = 0
foreach ($f in $files) {
    try {
        $raw = [IO.File]::ReadAllBytes($f.FullName)
        $text = $utf8S.GetString($raw)                         # 严格 UTF-8
        $whole = $false
    } catch {
        $text = $gbk.GetString($raw)                           # 整文件 GBK（非 UTF-8）
        $whole = $true
    }
    $chunks = [regex]::Split($text, '(?<=\r?\n)')              # 保留行尾
    $newChunks = [System.Collections.Generic.List[string]]::new()
    $lineFix = 0
    foreach ($c in $chunks) {
        if ($whole) { $newChunks.Add($c); continue }
        $eol = ''
        $body = $c
        if ($body -match "\r?\n$") { $eol = $Matches[0]; $body = $body.Substring(0, $body.Length - $eol.Length) }
        $fix = Test-FixLine $body
        if ($null -ne $fix -and $fix -ne $body) { $newChunks.Add($fix + $eol); $lineFix++ }
        else { $newChunks.Add($c) }
    }
    $out = ($newChunks -join '')
    if ($lineFix -gt 0) {
        if ($Apply) { [IO.File]::WriteAllText($f.FullName, $out, $utf8) }
        Write-Host ('  [行修复 {0,-4}] {1}' -f $lineFix, $f.FullName.Substring($Root.Length))
        $changed++
    } elseif ($whole) {
        Write-Host ('  [整文件GBK  ] ' + $f.FullName.Substring($Root.Length))
        if ($Apply) { [IO.File]::WriteAllText($f.FullName, $text, $utf8) }
        $gbkFiles++
    }
}
Write-Host ''
Write-Host ('扫描根: ' + $Root)
Write-Host ('命中文件: 行修复 {0}  整文件GBK {1}' -f $changed, $gbkFiles)
if (-not $Apply) { Write-Host '（仅报告模式：加 -Apply 执行写回）' }
