@echo off
chcp 65001 >nul
cls
setlocal enabledelayedexpansion

:: ============================================================================
:: Beyond Compare 重置试用工具 v2.1
:: 功能：重置 Beyond Compare 4.x/5.x 试用期限
:: 使用：以管理员权限运行
:: ============================================================================

title Beyond Compare 试用重置工具

echo ============================================
echo    Beyond Compare 试用重置工具 v2.1
echo ============================================
echo.
echo 【使用说明】
echo   1. 右键以管理员身份运行本脚本
echo   2. 脚本自动清除注册表中的试用标记
echo   3. 自动搜索并启动 Beyond Compare 程序
echo   4. 支持版本：Beyond Compare 4.x / 5.x
echo   5. 重置后试用期重新计算为30天
echo.
echo ============================================
echo.

:: 检查管理员权限
NET SESSION >nul 2>&1
if %errorLevel% NEQ 0 (
    echo [提示] 正在请求管理员权限...
    powershell -Command "Start-Process '%~f0' -Verb RunAs" >nul 2>&1
    echo [提示] 若未弹出 UAC 确认窗口或已点"否"，请右键本脚本选择"以管理员身份运行"
    pause
    exit /b
)

:: 删除注册表中的试用标记
echo [1/3] 正在清除试用标记...
echo [提示] 如 Beyond Compare 正在运行，将尝试结束进程（否则退出时会回写试用标记）
taskkill /f /im BCompare.exe >nul 2>&1
reg delete "HKEY_CURRENT_USER\Software\Scooter Software\Beyond Compare 5" /v CacheID /f >nul 2>&1
reg delete "HKEY_CURRENT_USER\Software\Scooter Software\Beyond Compare 4" /v CacheID /f >nul 2>&1
echo 注册表清理完成

:: 自动搜索安装路径
echo [2/3] 正在搜索安装路径...
set "bc_path="
set "bc_versions=5 4"
set "drives=C D"
set "archs=Program Files Program Files (x86)"

for %%v in (%bc_versions%) do (
    for %%d in (%drives%) do (
        for %%a in (%archs%) do (
            if not defined bc_path (
                if exist "%%d:\%%a\Beyond Compare %%v\BCompare.exe" (
                    set "bc_path=%%d:\%%a\Beyond Compare %%v\BCompare.exe"
                    echo 找到 Beyond Compare %%v 安装路径
                )
            )
        )
    )
)

:: 从桌面快捷方式搜索（如果未找到）
if not defined bc_path (
    for %%d in ("%USERPROFILE%\Desktop" "%USERPROFILE%\OneDrive\Desktop" "C:\Users\Public\Desktop") do (
        if not defined bc_path (
            for %%f in ("%%~d\Beyond Compare*.lnk") do (
                for /f "usebackq delims=" %%p in (`powershell -Command "(New-Object -ComObject WScript.Shell).CreateShortcut('%%~ff').TargetPath" 2^>nul`) do (
                    if exist "%%p" (
                        set "bc_path=%%p"
                        echo 从快捷方式找到安装路径
                        goto :found
                    )
                )
            )
        )
    )
)
:found

:: 启动程序
echo [3/3] 正在启动程序...
if defined bc_path (
    echo.
    echo ============================================
    echo 成功：试用期已重置为30天！
    echo 路径：!bc_path!
    echo ============================================
    start "" "!bc_path!"
) else (
    echo.
    echo ============================================
    echo 警告：未找到 Beyond Compare 安装路径
    echo 提示：注册表已清理，请手动启动程序
    echo ============================================
)

echo.
echo 按任意键退出...
pause >nul
exit /b
