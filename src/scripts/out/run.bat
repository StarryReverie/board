@echo off
call "C:\Xilinx\Vivado\2019.2\settings64.bat" >nul 2>&1
cd /d "E:\Homework\26-27-1\board\src\scripts\out"
if exist xvlog.pb del /q xvlog.pb
if exist xsim.dir  rmdir /s /q xsim.dir
call xvlog -i "E:\Homework\26-27-1\board\src" "E:\Homework\26-27-1\board\src\rtl\alu.v" "E:\Homework\26-27-1\board\src\rtl\decode.v" "E:\Homework\26-27-1\board\src\rtl\dmem.v" "E:\Homework\26-27-1\board\src\rtl\execute.v" "E:\Homework\26-27-1\board\src\rtl\ex_mem.v" "E:\Homework\26-27-1\board\src\rtl\hazard_unit.v" "E:\Homework\26-27-1\board\src\rtl\id_ex.v" "E:\Homework\26-27-1\board\src\rtl\if_id.v" "E:\Homework\26-27-1\board\src\rtl\imem.v" "E:\Homework\26-27-1\board\src\rtl\mem_wb.v" "E:\Homework\26-27-1\board\src\rtl\pc_reg.v" "E:\Homework\26-27-1\board\src\rtl\pipeline_top.v" "E:\Homework\26-27-1\board\src\rtl\regfile.v" "E:\Homework\26-27-1\board\src\rtl\wb.v" "E:\Homework\26-27-1\board\src\test\tb_alu.v" "E:\Homework\26-27-1\board\src\test\tb_decode.v" "E:\Homework\26-27-1\board\src\test\tb_dmem.v" "E:\Homework\26-27-1\board\src\test\tb_execute.v" "E:\Homework\26-27-1\board\src\test\tb_ex_mem.v" "E:\Homework\26-27-1\board\src\test\tb_hazard_unit.v" "E:\Homework\26-27-1\board\src\test\tb_id_ex.v" "E:\Homework\26-27-1\board\src\test\tb_if_id.v" "E:\Homework\26-27-1\board\src\test\tb_imem.v" "E:\Homework\26-27-1\board\src\test\tb_mem_wb.v" "E:\Homework\26-27-1\board\src\test\tb_pc_reg.v" "E:\Homework\26-27-1\board\src\test\tb_pipeline_top.v" "E:\Homework\26-27-1\board\src\test\tb_prog_cover.v" "E:\Homework\26-27-1\board\src\test\tb_prog_hazard.v" "E:\Homework\26-27-1\board\src\test\tb_prog_sort.v" "E:\Homework\26-27-1\board\src\test\tb_prog_test0.v" "E:\Homework\26-27-1\board\src\test\tb_prog_test1.v" "E:\Homework\26-27-1\board\src\test\tb_regfile.v" "E:\Homework\26-27-1\board\src\test\tb_wb.v"
if errorlevel 1 ( echo [COMPILE_FAIL] & exit /b 2 )
call xelab tb_alu -s tb_alu
if errorlevel 1 ( echo [XELAB_FAIL] tb_alu & exit /b 3 )
call xsim tb_alu -runall -log "E:\Homework\26-27-1\board\src\scripts\out\tb_alu.log"
if errorlevel 1 ( echo [XSIM_FAIL] tb_alu & exit /b 4 )
call xelab tb_decode -s tb_decode
if errorlevel 1 ( echo [XELAB_FAIL] tb_decode & exit /b 3 )
call xsim tb_decode -runall -log "E:\Homework\26-27-1\board\src\scripts\out\tb_decode.log"
if errorlevel 1 ( echo [XSIM_FAIL] tb_decode & exit /b 4 )
call xelab tb_dmem -s tb_dmem
if errorlevel 1 ( echo [XELAB_FAIL] tb_dmem & exit /b 3 )
call xsim tb_dmem -runall -log "E:\Homework\26-27-1\board\src\scripts\out\tb_dmem.log"
if errorlevel 1 ( echo [XSIM_FAIL] tb_dmem & exit /b 4 )
call xelab tb_execute -s tb_execute
if errorlevel 1 ( echo [XELAB_FAIL] tb_execute & exit /b 3 )
call xsim tb_execute -runall -log "E:\Homework\26-27-1\board\src\scripts\out\tb_execute.log"
if errorlevel 1 ( echo [XSIM_FAIL] tb_execute & exit /b 4 )
call xelab tb_ex_mem -s tb_ex_mem
if errorlevel 1 ( echo [XELAB_FAIL] tb_ex_mem & exit /b 3 )
call xsim tb_ex_mem -runall -log "E:\Homework\26-27-1\board\src\scripts\out\tb_ex_mem.log"
if errorlevel 1 ( echo [XSIM_FAIL] tb_ex_mem & exit /b 4 )
call xelab tb_hazard_unit -s tb_hazard_unit
if errorlevel 1 ( echo [XELAB_FAIL] tb_hazard_unit & exit /b 3 )
call xsim tb_hazard_unit -runall -log "E:\Homework\26-27-1\board\src\scripts\out\tb_hazard_unit.log"
if errorlevel 1 ( echo [XSIM_FAIL] tb_hazard_unit & exit /b 4 )
call xelab tb_id_ex -s tb_id_ex
if errorlevel 1 ( echo [XELAB_FAIL] tb_id_ex & exit /b 3 )
call xsim tb_id_ex -runall -log "E:\Homework\26-27-1\board\src\scripts\out\tb_id_ex.log"
if errorlevel 1 ( echo [XSIM_FAIL] tb_id_ex & exit /b 4 )
call xelab tb_if_id -s tb_if_id
if errorlevel 1 ( echo [XELAB_FAIL] tb_if_id & exit /b 3 )
call xsim tb_if_id -runall -log "E:\Homework\26-27-1\board\src\scripts\out\tb_if_id.log"
if errorlevel 1 ( echo [XSIM_FAIL] tb_if_id & exit /b 4 )
call xelab tb_imem -s tb_imem
if errorlevel 1 ( echo [XELAB_FAIL] tb_imem & exit /b 3 )
call xsim tb_imem -runall -log "E:\Homework\26-27-1\board\src\scripts\out\tb_imem.log"
if errorlevel 1 ( echo [XSIM_FAIL] tb_imem & exit /b 4 )
call xelab tb_mem_wb -s tb_mem_wb
if errorlevel 1 ( echo [XELAB_FAIL] tb_mem_wb & exit /b 3 )
call xsim tb_mem_wb -runall -log "E:\Homework\26-27-1\board\src\scripts\out\tb_mem_wb.log"
if errorlevel 1 ( echo [XSIM_FAIL] tb_mem_wb & exit /b 4 )
call xelab tb_pc_reg -s tb_pc_reg
if errorlevel 1 ( echo [XELAB_FAIL] tb_pc_reg & exit /b 3 )
call xsim tb_pc_reg -runall -log "E:\Homework\26-27-1\board\src\scripts\out\tb_pc_reg.log"
if errorlevel 1 ( echo [XSIM_FAIL] tb_pc_reg & exit /b 4 )
call xelab tb_pipeline_top -s tb_pipeline_top
if errorlevel 1 ( echo [XELAB_FAIL] tb_pipeline_top & exit /b 3 )
call xsim tb_pipeline_top -runall -log "E:\Homework\26-27-1\board\src\scripts\out\tb_pipeline_top.log"
if errorlevel 1 ( echo [XSIM_FAIL] tb_pipeline_top & exit /b 4 )
call xelab tb_prog_cover -s tb_prog_cover
if errorlevel 1 ( echo [XELAB_FAIL] tb_prog_cover & exit /b 3 )
call xsim tb_prog_cover -runall -log "E:\Homework\26-27-1\board\src\scripts\out\tb_prog_cover.log"
if errorlevel 1 ( echo [XSIM_FAIL] tb_prog_cover & exit /b 4 )
call xelab tb_prog_hazard -s tb_prog_hazard
if errorlevel 1 ( echo [XELAB_FAIL] tb_prog_hazard & exit /b 3 )
call xsim tb_prog_hazard -runall -log "E:\Homework\26-27-1\board\src\scripts\out\tb_prog_hazard.log"
if errorlevel 1 ( echo [XSIM_FAIL] tb_prog_hazard & exit /b 4 )
call xelab tb_prog_sort -s tb_prog_sort
if errorlevel 1 ( echo [XELAB_FAIL] tb_prog_sort & exit /b 3 )
call xsim tb_prog_sort -runall -log "E:\Homework\26-27-1\board\src\scripts\out\tb_prog_sort.log"
if errorlevel 1 ( echo [XSIM_FAIL] tb_prog_sort & exit /b 4 )
call xelab tb_prog_test0 -s tb_prog_test0
if errorlevel 1 ( echo [XELAB_FAIL] tb_prog_test0 & exit /b 3 )
call xsim tb_prog_test0 -runall -log "E:\Homework\26-27-1\board\src\scripts\out\tb_prog_test0.log"
if errorlevel 1 ( echo [XSIM_FAIL] tb_prog_test0 & exit /b 4 )
call xelab tb_prog_test1 -s tb_prog_test1
if errorlevel 1 ( echo [XELAB_FAIL] tb_prog_test1 & exit /b 3 )
call xsim tb_prog_test1 -runall -log "E:\Homework\26-27-1\board\src\scripts\out\tb_prog_test1.log"
if errorlevel 1 ( echo [XSIM_FAIL] tb_prog_test1 & exit /b 4 )
call xelab tb_regfile -s tb_regfile
if errorlevel 1 ( echo [XELAB_FAIL] tb_regfile & exit /b 3 )
call xsim tb_regfile -runall -log "E:\Homework\26-27-1\board\src\scripts\out\tb_regfile.log"
if errorlevel 1 ( echo [XSIM_FAIL] tb_regfile & exit /b 4 )
call xelab tb_wb -s tb_wb
if errorlevel 1 ( echo [XELAB_FAIL] tb_wb & exit /b 3 )
call xsim tb_wb -runall -log "E:\Homework\26-27-1\board\src\scripts\out\tb_wb.log"
if errorlevel 1 ( echo [XSIM_FAIL] tb_wb & exit /b 4 )
exit /b 0

