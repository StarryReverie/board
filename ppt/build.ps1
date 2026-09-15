# build.ps1 - regenerate all figures and the defense PPTX.
# Usage: powershell -File ppt/build.ps1
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$python = '3.13.13'
$deps = @('--with', 'matplotlib', '--with', 'python-pptx')

function Invoke-Step {
    param([string]$Script)
    Write-Host "== $Script"
    & uv run --no-project --python $python @deps python (Join-Path $here $Script)
    if ($LASTEXITCODE -ne 0) { throw "step failed: $Script" }
}

Invoke-Step 'make_figs.py'
Invoke-Step 'make_waves.py'
Invoke-Step 'make_diagrams.py'
Invoke-Step 'build_ppt.py'

Write-Host 'done'
