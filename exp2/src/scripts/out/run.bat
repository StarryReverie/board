@echo off
call "C:\Xilinx\Vivado\2019.2\settings64.bat" >nul 2>&1
cd /d "E:\Homework\26-27-1\board\exp2\src\scripts\out"
if exist xvlog.pb del /q xvlog.pb
if exist xsim.dir  rmdir /s /q xsim.dir
call xvlog -i "E:\Homework\26-27-1\board\exp2\src" "E:\Homework\26-27-1\board\exp2\src\rtl\uart_tx.v" "E:\Homework\26-27-1\board\exp2\src\test\tb_uart_tx.v"
if errorlevel 1 ( echo [COMPILE_FAIL] & exit /b 2 )
call xelab tb_uart_tx -s tb_uart_tx
if errorlevel 1 ( echo [XELAB_FAIL] tb_uart_tx & exit /b 3 )
call xsim tb_uart_tx -runall -log "E:\Homework\26-27-1\board\exp2\src\scripts\out\tb_uart_tx.log"
if errorlevel 1 ( echo [XSIM_FAIL] tb_uart_tx & exit /b 4 )
exit /b 0

