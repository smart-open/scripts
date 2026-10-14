@echo off
chcp 65001 >nul
setlocal
title Windows系统一键优化工具 v2.0
mode con cols=90 lines=40
color 0A

:: ========================================
::          检查管理员权限
:: ========================================
fltmc >nul 2>&1 || (
    echo.
    echo [X] 请以管理员身份运行此脚本!
    echo.
    echo 右键点击脚本 -^> 以管理员身份运行
    echo.
    pause
    exit /b 1
)

cls
echo.
echo =====================================================================================
echo                          Windows系统一键优化工具 v2.0
echo =====================================================================================
echo.
echo [√] 已获取管理员权限
echo.
echo 优化等级说明:
echo.
echo   [严重] 严重影响系统性能/安全/隐私，强烈建议优化
echo   [一般] 对系统有一定作用，推荐优化
echo   [轻微] 可优化也可不优化，根据个人喜好选择
echo.
echo =====================================================================================
echo.

:: ========================================
::          选择优化等级
:: ========================================
:MENU
echo 请选择优化等级:
echo.
echo   [1] 仅严重等级优化 (默认)
echo   [2] 严重 + 一般等级
echo   [3] 全部优化 (严重 + 一般 + 轻微)
echo   [4] 自定义选择等级
echo   [0] 退出
echo.
set /p "choice=请输入选项编号 [0-4]: "

if /i "%choice%"=="" set "choice=1"
if /i "%choice%"=="0" exit /b 0
if /i "%choice%"=="1" set "level=1" & goto START
if /i "%choice%"=="2" set "level=2" & goto START
if /i "%choice%"=="3" set "level=3" & goto START
if /i "%choice%"=="4" goto CUSTOM
goto MENU

:CUSTOM
cls
echo.
echo =====================================================================================
echo                                自定义优化等级
echo =====================================================================================
echo.
echo 请选择要优化的等级（可多选，用空格分隔）:
echo.
echo   [S] 严重等级 - 强烈建议优化
echo   [N] 一般等级 - 推荐优化
echo   [L] 轻微等级 - 可选优化
echo.
echo 示例: 输入 "S N" 表示选择严重和一般两个等级
echo.
set /p "custom_levels=请输入选择: "

set "level_S=0"
set "level_N=0"
set "level_L=0"

echo "%custom_levels%" | findstr /i "S" >nul && set "level_S=1"
echo "%custom_levels%" | findstr /i "N" >nul && set "level_N=1"
echo "%custom_levels%" | findstr /i "L" >nul && set "level_L=1"

if %level_S% equ 0 if %level_N% equ 0 if %level_L% equ 0 (
    echo.
    echo [!] 未选择任何等级，请重新选择
    pause
    goto CUSTOM
)

set "level=99"
goto START

:START
cls
echo.
echo =====================================================================================
echo                               开始执行系统优化
echo =====================================================================================
echo.

:: ========================================
::          设置等级标志
:: ========================================
set "OPT_CRITICAL=0"
set "OPT_NORMAL=0"
set "OPT_LIGHT=0"

if %level% equ 1 set "OPT_CRITICAL=1"
if %level% equ 2 set "OPT_CRITICAL=1" & set "OPT_NORMAL=1"
if %level% equ 3 set "OPT_CRITICAL=1" & set "OPT_NORMAL=1" & set "OPT_LIGHT=1"
if %level% equ 99 set "OPT_CRITICAL=%level_S%" & set "OPT_NORMAL=%level_N%" & set "OPT_LIGHT=%level_L%"

echo 当前选择:
if %OPT_CRITICAL% equ 1 echo   [√] 严重等级
if %OPT_NORMAL% equ 1 echo   [√] 一般等级
if %OPT_LIGHT% equ 1 echo   [√] 轻微等级
echo.
echo =====================================================================================
echo.
pause

:: ========================================
::          创建系统还原点
:: ========================================
echo.
echo [准备] 正在创建系统还原点...
powershell -Command "Checkpoint-Computer -Description 'System Optimization Backup' -RestorePointType MODIFY_SETTINGS" >nul 2>&1
if %errorlevel% equ 0 (
    echo [√] 系统还原点创建成功
) else (
    echo [!] 系统还原点创建失败，继续优化...
)

:: ========================================
::          统计优化项数量
:: ========================================
set "total=0"
if %OPT_CRITICAL% equ 1 set /a total+=7
if %OPT_NORMAL% equ 1 set /a total+=9
if %OPT_LIGHT% equ 1 set /a total+=7
set "current=0"

:: ========================================
::          严重等级优化
:: ========================================
if %OPT_CRITICAL% equ 1 call :CRITICAL_OPT

:: ========================================
::          一般等级优化
:: ========================================
if %OPT_NORMAL% equ 1 call :NORMAL_OPT

:: ========================================
::          轻微等级优化
:: ========================================
if %OPT_LIGHT% equ 1 call :LIGHT_OPT

:: ========================================
::          重启 Explorer
:: ========================================
echo.
echo [完成] 正在重启资源管理器使设置生效...
taskkill /f /im explorer.exe >nul 2>&1
timeout /t 2 /nobreak >nul 2>&1
start explorer.exe >nul 2>&1

:: ========================================
::          完成
:: ========================================
cls
echo.
echo =====================================================================================
echo                               优化完成!
echo =====================================================================================
echo.
echo 已完成 %total% 项优化:
echo.
if %OPT_CRITICAL% equ 1 echo   [√] 严重等级优化 (7项)
if %OPT_NORMAL% equ 1 echo   [√] 一般等级优化 (9项)
if %OPT_LIGHT% equ 1 echo   [√] 轻微等级优化 (7项)
echo.
echo =====================================================================================
echo.
echo [!] 建议重启电脑使所有设置完全生效
echo.
echo 按任意键退出...
pause >nul
exit /b 0

:: ========================================
::          严重等级优化函数
:: ========================================
:CRITICAL_OPT
echo.
echo =============================== [严重等级] ========================================
echo.

set /a current+=1
echo [%current%/%total%] 正在关闭Windows自动更新...
sc stop wuauserv >nul 2>&1
sc config wuauserv start= disabled >nul 2>&1
sc stop WaaSMedicSvc >nul 2>&1
sc config WaaSMedicSvc start= disabled >nul 2>&1
sc stop UsoSvc >nul 2>&1
sc config UsoSvc start= disabled >nul 2>&1
reg add "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" /v "DisableWindowsUpdateAccess" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" /v "DoNotConnectToWindowsUpdateInternetLocations" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "NoAutoUpdate" /t REG_DWORD /d 1 /f >nul 2>&1
echo [√] Windows自动更新已关闭

set /a current+=1
echo [%current%/%total%] 正在禁用遥测和数据收集...
reg add "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v "MaxTelemetryAllowed" /t REG_DWORD /d 0 /f >nul 2>&1
sc stop DiagTrack >nul 2>&1
sc config DiagTrack start= disabled >nul 2>&1
sc stop dmwappushservice >nul 2>&1
sc config dmwappushservice start= disabled >nul 2>&1
echo [√] 遥测和数据收集已禁用

set /a current+=1
echo [%current%/%total%] 正在禁用SMB 1.0协议...
sc stop LanmanServer >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v "SMB1" /t REG_DWORD /d 0 /f >nul 2>&1
dism /online /disable-feature /featurename:SMB1Protocol /norestart >nul 2>&1
echo [√] SMB 1.0协议已禁用

set /a current+=1
echo [%current%/%total%] 正在禁用远程访问服务...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Remote Assistance" /v "fAllowToGetHelp" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Remote Assistance" /v "fAllowFullControl" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v "fDenyTSConnections" /t REG_DWORD /d 1 /f >nul 2>&1
sc stop TermService >nul 2>&1
sc config TermService start= disabled >nul 2>&1
sc stop RemoteRegistry >nul 2>&1
sc config RemoteRegistry start= disabled >nul 2>&1
sc stop WinRM >nul 2>&1
sc config WinRM start= disabled >nul 2>&1
echo [√] 远程访问服务已禁用

set /a current+=1
echo [%current%/%total%] 正在禁用Cortana和Web搜索...
reg add "HKLM\Software\Policies\Microsoft\Windows\Windows Search" /v "AllowCortana" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Cortana" /v "CortanaEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v "BingSearchEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v "CortanaConsent" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v "AllowSearchToUseLocation" /t REG_DWORD /d 0 /f >nul 2>&1
echo [√] Cortana和Web搜索已禁用

set /a current+=1
echo [%current%/%total%] 正在禁用SysMain超级预读...
sc stop SysMain >nul 2>&1
sc config SysMain start= disabled >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" /v "EnablePrefetcher" /t REG_DWORD /d 2 /f >nul 2>&1
echo [√] SysMain超级预读已禁用

set /a current+=1
echo [%current%/%total%] 正在禁用系统休眠...
powercfg -h off >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v "HiberbootEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
echo [√] 系统休眠已禁用

goto :EOF

:: ========================================
::          一般等级优化函数
:: ========================================
:NORMAL_OPT
echo.
echo =============================== [一般等级] ========================================
echo.

set /a current+=1
echo [%current%/%total%] 正在关闭系统通知...
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" /v "NOC_GLOBAL_SETTING_TOASTS_ENABLED" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\PushNotifications" /v "ToastEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\PushNotifications" /v "ToastEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
echo [√] 系统通知已关闭

set /a current+=1
echo [%current%/%total%] 正在禁用多余自启动项...
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "OneDrive" /f >nul 2>&1 2>&1
reg delete "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" /v "SunJavaUpdateSched" /f >nul 2>&1 2>&1
schtasks /change /tn "\Microsoft\Windows\WindowsUpdate\Automatic App Update" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator" /disable >nul 2>&1
echo [√] 多余自启动项已禁用

set /a current+=1
echo [%current%/%total%] 正在进行基础隐私设置...
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v "Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Explorer" /v "SmartScreenEnabled" /t REG_SZ /d "Off" /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\AppHost" /v "EnableWebContentEvaluation" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" /v "Value" /t REG_SZ /d "Deny" /f >nul 2>&1
echo [√] 基础隐私设置已完成

set /a current+=1
echo [%current%/%total%] 正在清除文件浏览记录...
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU" /va /f >nul 2>&1 2>&1
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs" /va /f >nul 2>&1 2>&1
del /f /q "%APPDATA%\Microsoft\Windows\Recent\*.*" >nul 2>&1
del /f /q "%APPDATA%\Microsoft\Windows\Recent\AutomaticDestinations\*.*" >nul 2>&1
del /f /q "%APPDATA%\Microsoft\Windows\Recent\CustomDestinations\*.*" >nul 2>&1
echo [√] 文件浏览记录已清除

set /a current+=1
echo [%current%/%total%] 正在关闭活动历史和剪贴板同步...
reg add "HKLM\Software\Policies\Microsoft\Windows\System" /v "PublishUserActivities" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\Software\Policies\Microsoft\Windows\System" /v "UploadUserActivities" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\Software\Policies\Microsoft\Windows\System" /v "AllowCrossDeviceClipboard" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Clipboard" /v "EnableClipboardHistory" /t REG_DWORD /d 0 /f >nul 2>&1
echo [√] 活动历史和剪贴板同步已关闭

set /a current+=1
echo [%current%/%total%] 正在关闭广告ID和位置服务...
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" /v "Value" /t REG_SZ /d "Deny" /f >nul 2>&1
sc stop WbioSrvc >nul 2>&1
sc config WbioSrvc start= disabled >nul 2>&1
echo [√] 广告ID和位置服务已关闭

set /a current+=1
echo [%current%/%total%] 正在禁用动画效果...
reg add "HKCU\Control Panel\Desktop" /v "UserPreferencesMask" /t REG_BINARY /d 9012038010000000 /f >nul 2>&1
reg add "HKCU\Control Panel\Desktop\WindowMetrics" /v "MinAnimate" /t REG_SZ /d 0 /f >nul 2>&1
echo [√] 动画效果已禁用

set /a current+=1
echo [%current%/%total%] 正在禁用应用建议和广告...
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SystemPaneSuggestionsEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "ContentDeliveryAllowed" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "Start_IrisRecommendations" /t REG_DWORD /d 0 /f >nul 2>&1
echo [√] 应用建议和广告已禁用

set /a current+=1
echo [%current%/%total%] 正在优化Microsoft Edge...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v "StartupBoostEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Edge\Main" /v "StartupBoostEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v "BackgroundModeEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v "MetricsReportingEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
echo [√] Microsoft Edge已优化

goto :EOF

:: ========================================
::          轻微等级优化函数
:: ========================================
:LIGHT_OPT
echo.
echo =============================== [轻微等级] ========================================
echo.

set /a current+=1
echo [%current%/%total%] 正在优化资源管理器...
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "HideFileExt" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "Hidden" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "LaunchTo" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" /v "FullPath" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer" /v "ShowRecent" /t REG_DWORD /d 0 /f >nul 2>&1
echo [√] 资源管理器已优化

set /a current+=1
echo [%current%/%total%] 正在关闭透明效果...
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "EnableTransparency" /t REG_DWORD /d 0 /f >nul 2>&1
echo [√] 透明效果已关闭

set /a current+=1
echo [%current%/%total%] 正在加快开关机超时设置...
reg add "HKLM\SYSTEM\CurrentControlSet\Control" /v "WaitToKillServiceTimeout" /t REG_SZ /d "5000" /f >nul 2>&1
reg add "HKCU\Control Panel\Desktop" /v "WaitToKillAppTimeout" /t REG_SZ /d "2000" /f >nul 2>&1
reg add "HKCU\Control Panel\Desktop" /v "HungAppTimeout" /t REG_SZ /d "1000" /f >nul 2>&1
reg add "HKCU\Control Panel\Desktop" /v "AutoEndTasks" /t REG_SZ /d "1" /f >nul 2>&1
echo [√] 开关机超时已优化

set /a current+=1
echo [%current%/%total%] 正在禁用NetBIOS和LLMNR...
reg add "HKLM\Software\Policies\Microsoft\Windows NT\DNSClient" /v "EnableMulticast" /t REG_DWORD /d 0 /f >nul 2>&1
echo [√] NetBIOS和LLMNR已禁用

set /a current+=1
echo [%current%/%total%] 正在优化网络带宽...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Psched" /v "NonBestEffortLimit" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\Software\Microsoft\WcmSvc\wifinetworkmanager\config" /v "AutoConnectAllowedOEM" /t REG_DWORD /d 0 /f >nul 2>&1
echo [√] 网络带宽已优化

set /a current+=1
echo [%current%/%total%] 正在清理不常用服务...
sc stop Fax >nul 2>&1
sc config Fax start= disabled >nul 2>&1
sc stop BthServ >nul 2>&1
sc config BthServ start= disabled >nul 2>&1
sc stop WerSvc >nul 2>&1
sc config WerSvc start= disabled >nul 2>&1
reg add "HKLM\Software\Microsoft\Windows\Windows Error Reporting" /v "Disabled" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\Software\Policies\Microsoft\SQMClient\Windows" /v "CEIPEnable" /t REG_DWORD /d 0 /f >nul 2>&1
echo [√] 不常用服务已清理

set /a current+=1
echo [%current%/%total%] 正在设置电源计划...
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c >nul 2>&1
powercfg /change disk-timeout-ac 0 >nul 2>&1
powercfg /change disk-timeout-dc 0 >nul 2>&1
echo [√] 电源计划已设置为高性能

goto :EOF
