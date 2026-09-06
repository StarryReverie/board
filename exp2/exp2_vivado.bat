@echo off
rem =====================================================================
rem  exp2 Vivado 工程入口（汇编与接口：UART SoC console）
rem  双击运行：打开 ../vivado/exp2.xpr（exp2 工程目录 = exp2/vivado；
rem  缺失则先自动重建；与 exp1 的 vivado 互不影响）
rem  可用环境变量 XVIVADO_ROOT 覆盖 Vivado 安装目录
rem =====================================================================
setlocal
set EXP2ROOT=%~dp0
set REPO=%EXP2ROOT%..
set XV=%XVIVADO_ROOT%
if "%XV%"=="" set XV=C:\Xilinx\Vivado\2019.2
if not exist "%XV%\bin\vivado.bat" (
    echo [ERR] Vivado not found at "%XV%" - set XVIVADO_ROOT first
    pause
    exit /b 1
)
set XPR=%REPO%vivado\exp2.xpr
if not exist "%XPR%" (
    echo [info] exp2 xpr missing - generating ...
    call "%XV%\bin\vivado.bat" -mode batch -source "%EXP2ROOT%src\scripts\create_vivado_proj.tcl"
    if errorlevel 1 (
        echo [ERR] exp2 project generation FAILED
        pause
        exit /b 1
    )
)
echo [info] opening exp2 project: %XPR%
start "" cmd /c call "%XV%\bin\vivado.bat" "%XPR%"
endlocal
