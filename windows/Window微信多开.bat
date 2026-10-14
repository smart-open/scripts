@echo off
chcp 65001 >nul
cls
setlocal enabledelayedexpansion

:: ============================================================================
:: 微信多开工具 v2.1
:: 功能：快速启动多个微信实例，支持微信运行中直接多开
:: 使用：直接运行，输入多开数量即可
:: ============================================================================

title 微信多开工具

echo ============================================
echo        微信多开工具 v2.1
echo ============================================
echo.
echo 【使用说明】
echo   1. 直接运行脚本即可启动多个微信
echo   2. 支持微信运行中直接多开（无需先关闭）
echo   3. 建议第一次登录后再启动第二个微信
echo   4. 最多支持同时启动10个微信实例
echo.
echo ============================================
echo.

:: 直接搜索微信安装路径
echo [1/3] 正在搜索微信安装路径...
set "wechat_path="
set "drives=C D"
set "archs=Program Files Program Files (x86)"

for %%d in (%drives%) do (
    for %%a in (%archs%) do (
        if not defined wechat_path (
            if exist "%%d:\%%a\Tencent\Weixin\Weixin.exe" (
                set "wechat_path=%%d:\%%a\Tencent\Weixin\Weixin.exe"
                echo 找到标准安装路径
            )
        )
    )
)

::: 搜索经典版微信（WeChat）
for %%d in (%drives%) do (
    for %%a in (%archs%) do (
        if not defined wechat_path (
            if exist "%%d:\%%a\Tencent\WeChat\WeChat.exe" (
                set "wechat_path=%%d:\%%a\Tencent\WeChat\WeChat.exe"
                echo 找到经典版微信安装路径
            )
        )
    )
)

:: 搜索根目录安装
for %%d in (%drives%) do (
    if not defined wechat_path (
        if exist "%%d:\Weixin\Weixin.exe" (
            set "wechat_path=%%d:\Weixin\Weixin.exe"
            echo 找到根目录安装路径
        )
    )
)

:: 从桌面快捷方式搜索
if not defined wechat_path (
    for %%d in ("%USERPROFILE%\Desktop" "%USERPROFILE%\OneDrive\Desktop" "C:\Users\Public\Desktop") do (
        if not defined wechat_path (
            for %%f in ("%%~d\微信*.lnk" "%%~d\WeChat*.lnk") do (
                for /f "usebackq delims=" %%p in (`powershell -Command "(New-Object -ComObject WScript.Shell).CreateShortcut('%%~ff').TargetPath" 2^>nul`) do (
                    if exist "%%p" (
                        set "wechat_path=%%p"
                        echo 从快捷方式找到安装路径
                        goto :path_found
                    )
                )
            )
        )
    )
)
:path_found

if not defined wechat_path (
    echo 错误：未找到微信安装路径！
    pause
    exit /b 1
)
echo 微信路径：!wechat_path!
echo.

:: 获取多开数量
echo [2/3] 设置多开数量
set "open_count=2"
set /p "open_count=请输入多开数量 (默认2): "

:: 验证输入
echo !open_count!|findstr /r "^[1-9][0-9]*$" >nul
if %errorlevel% neq 0 (
    echo 提示：输入无效，使用默认值 2
    set "open_count=2"
)

if !open_count! gtr 10 (
    echo 警告：数量过大，限制为 10 个
    set "open_count=10"
)
echo.

:: 启动微信
echo [3/3] 正在启动 !open_count! 个微信...
for /l %%i in (1,1,!open_count!) do (
    echo 启动第 %%i 个微信...
    start "微信%%i" "!wechat_path!"
    timeout /t 1 /nobreak >nul
)

echo.
echo ============================================
echo 成功：!open_count! 个微信已启动！
echo ============================================
echo.
echo 按任意键退出...
pause >nul
exit /b
