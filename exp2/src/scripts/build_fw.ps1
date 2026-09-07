<#
=============================================================================
 build_fw.ps1 — exp2 固件构建（U40）：console.S → console_rom.hex + console_init.vh
   * 输入: exp2/src/test/<Name>.S
   * 输出:
       exp2/src/test/<Name>_rom.hex    objcopy -O verilog 字节式（$readmemh 直读）
       exp2/src/test/<Name>_init.vh    imem 综合固化镜像（默认按 -PadBytes 补零到 512 字节=下板 IMEM_BYTES；4KB 口径传 -PadBytes 4096；
                                       供 imem.v 的 `ifdef IMEM_INIT_VH 装载）
       src/scripts/out/asm/            .o/.lst（objdump 反汇编清单）
   * 校验（U40 验收）:
       1) 反汇编指令助记符 ⊆ 26 条冻结集（doc/isa.md §1）
       2) .hex 字节数 = 指令数×4
   * 工具: riscv-none-elf-as/objcopy/objdump（xPack，PATH 或默认目录）
   * 用法: .\build_fw.ps1 [-Name console] [-PadBytes 512]
=============================================================================
#>
param(
    [string]$Name = 'console',
    [int]$PadBytes = 512      # .vh 补零字节数（对齐下板 IMEM_BYTES=512；4KB 口径传 4096）
)

$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $PSScriptRoot          # exp2/src
$exp2    = Split-Path -Parent $root                  # exp2
$testDir = Join-Path $root 'test'
$outDir  = Join-Path $PSScriptRoot 'out\asm'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

# ---- 定位工具链 ----
$as = Get-Command riscv-none-elf-as -ErrorAction SilentlyContinue
if (-not $as) {
    $guess = 'E:\Homework\26-27-1\tools\xpack-riscv-none-elf-gcc-15.2.0-1\bin'
    if (Test-Path (Join-Path $guess 'riscv-none-elf-as.exe')) { $env:Path = $guess + ';' + $env:Path }
    else { Write-Error '找不到 riscv-none-elf-as'; exit 1 }
}

$src  = Join-Path $testDir "$Name.S"
if (-not (Test-Path $src)) { Write-Error "找不到 $src"; exit 1 }
$o    = Join-Path $outDir "$Name.o"
$lst  = Join-Path $outDir "$Name.lst"
$hex  = Join-Path $testDir "${Name}_rom.hex"
$vh   = Join-Path $testDir "${Name}_init.vh"

# ---- 汇编 + 反汇编清单 ----
& riscv-none-elf-as -march=rv32i -mabi=ilp32 -o $o $src
if ($LASTEXITCODE -ne 0) { Write-Host "[FAIL] as $Name"; exit 1 }
& riscv-none-elf-objcopy -O verilog $o $hex
if ($LASTEXITCODE -ne 0) { Write-Host "[FAIL] objcopy $Name"; exit 1 }
& riscv-none-elf-objdump -d -M no-aliases $o > $lst

# ---- 校验 1：指令子集（26 条冻结集，doc/isa.md §1）----
$allowed = @('add','sub','sll','slt','sltu','xor','srl','sra','or','and',
             'addi','slli','slti','sltiu','xori','srli','srai','ori','andi',
             'lui','lw','sw','beq','bne','jal','jalr')
$bad = @()
$instrCnt = 0
foreach ($line in (Get-Content $lst)) {
    if ($line -match '^\s*[0-9a-f]+:\s+[0-9a-f]{8}\s+([a-z0-9]+)') {
        $m = $Matches[1]
        $instrCnt++
        if ($allowed -notcontains $m) { $bad += $m }
    }
}
if ($bad.Count -gt 0) { Write-Host ("[FAIL] 越界指令: {0}" -f ($bad -join ',')); exit 1 }

# ---- 校验 2：hex 字节数 ----
$bytes = ((Get-Content $hex | Where-Object { $_ -notmatch '^@' }) -join ' ').Split(' ',
         [System.StringSplitOptions]::RemoveEmptyEntries).Count
if ($bytes -ne $instrCnt * 4) {
    Write-Host "[FAIL] hex 字节数 $bytes != 指令数×4（$instrCnt×4）"; exit 1
}


# ---- 校验 3：-PadBytes 合法性（4 字节对齐且不小于固件长度，防越界/截断 .vh）----
if (($PadBytes % 4) -ne 0) {
    Write-Host ("[FAIL] -PadBytes 必须 4 字节对齐（当前 {0}）" -f $PadBytes); exit 1
}
if ($bytes -gt $PadBytes) {
    Write-Host ("[FAIL] 固件 {0} B 超过 -PadBytes={1}，请增大 PadBytes" -f $bytes, $PadBytes); exit 1
}
# ---- 生成综合固化 .vh（补零到 -PadBytes，默认 512=下板 IMEM_BYTES）----
$sb = New-Object System.Text.StringBuilder
$idx = 0
foreach ($line in (Get-Content $hex)) {
    if ($line -match '^@') { continue }
    foreach ($b in ($line -split ' ' | Where-Object { $_ })) {
        [void]$sb.AppendLine(('mem[{0}] = 8''h{1};' -f $idx, $b))
        $idx++
    }
}
while ($idx -lt $PadBytes) {
    [void]$sb.AppendLine('mem[' + $idx + "] = 8'h00;")
    $idx++
}
Set-Content -Path $vh -Value $sb.ToString() -Encoding ASCII

Write-Host ("[OK] {0}: {1} 指令（冻结集校验通过，hex={2}B, vh={3} 行）" -f
            $Name, $instrCnt, $bytes, (Get-Content $vh).Count)
Write-Host 'build_fw done'
