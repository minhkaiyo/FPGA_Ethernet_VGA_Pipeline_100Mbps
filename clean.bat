@echo off
echo ===================================================
echo   DON DEP THU MUC DU AN - FPGA ETHERNET VGA PIPELINE
echo ===================================================
echo.

echo Dang xoa cac tep tin rac tu simulation...
if exist vsim.wlf (
    del /f /q vsim.wlf
    echo   [x] Da xoa vsim.wlf
)
if exist transcript (
    del /f /q transcript
    echo   [x] Da xoa transcript
)
if exist modelsim.ini (
    del /f /q modelsim.ini
    echo   [x] Da xoa modelsim.ini
)

:: Xoa cac tep wlft* (tep tam cua ModelSim)
for %%f in (wlft*) do (
    del /f /q "%%f"
    echo   [x] Da xoa tep tam %%f
)

:: Xoa thu muc work (thu muc bien dich cu)
if exist work (
    rd /s /q work
    echo   [x] Da xoa thu muc work/
)

echo.
echo ===================================================
echo   Da don dep folder gon gang, sach se!
echo ===================================================
pause
