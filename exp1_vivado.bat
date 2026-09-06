@echo off
rem =====================================================================
rem  exp1 Vivado 工程入口（计组实验一：流水线 CPU core）
rem  双击运行：打开 board/vivado/exp1/board.xpr（缺失则先自动重建）
rem  与 exp2 工程相互独立（各自目录、各自重建，互不影响）
rem  可用环境变量 XVIVADO_ROOT 覆盖 Vivado 安装目录
rem =====================================================================
setlocal
set REPO=%~dp0
set XV=%XVIVADO_ROOT%
if "%XV%"=="" set XV=C:\Xilinx\Vivado\2019.2
if not exist "%XV%\bin\vivado.bat" (
    echo [ERR] Vivado not found at "%XV%" - set XVIVADO_ROOT first
    pause
    exit /b 1
)
set XPR=%REPO%vivado\exp1\board.xpr
if not exist "%XPR%" (
    echo [info] exp1 xpr missing - generating ...
    call "%XV%\bin\vivado.bat" -mode batch -source "%REPO%src\scripts\create_vivado_proj.tcl"
    if errorlevel 1 (
        echo [ERR] exp1 project generation FAILED
        pause
        exit /b 1
    )
)
echo [info] opening exp1 project: %XPR%
start "" cmd /c call "%XV%\bin\vivado.bat" "%XPR%"
endlocal
