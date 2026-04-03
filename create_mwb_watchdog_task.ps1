# create_mwb_watchdog_task.ps1 -- Register MWB watchdog scheduled task
# Must run from an elevated PowerShell

$ErrorActionPreference = "Stop"
$TaskName = "MWB Connection Watchdog"
$ScriptPath = "C:\Program Files (x86)\Microsoft Garage\Mouse without Borders\mwb_watchdog.ps1"

# Check elevation
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: Must run as Administrator." -ForegroundColor Red
    exit 1
}

# Remove existing task if present
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Removing existing task '$TaskName'..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Runs as SYSTEM so it can restart the MWB service without UAC prompts
Write-Host "Task will run as: SYSTEM (required for service control)" -ForegroundColor Cyan

# Create the task
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`"" `
    -WorkingDirectory "C:\Program Files (x86)\Microsoft Garage\Mouse without Borders"

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 1) `
    -RepetitionDuration (New-TimeSpan -Days 9999)

$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 30) `
    -MultipleInstances IgnoreNew

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "Monitors Mouse without Borders connection to partner machine. Auto-restarts MWB service if connection drops. Disable: Task Scheduler -> right-click task -> Disable. Remove: Unregister-ScheduledTask -TaskName 'MWB Connection Watchdog'" `
    | Out-Null

# Verify
$task = Get-ScheduledTask -TaskName $TaskName
Write-Host ""
Write-Host "=== Scheduled Task Created ===" -ForegroundColor Green
Write-Host "  Name: $($task.TaskName)" -ForegroundColor Cyan
Write-Host "  State: $($task.State)" -ForegroundColor Cyan
Write-Host "  Runs as: SYSTEM (for UAC-free service restart)" -ForegroundColor Cyan
Write-Host "  Interval: Every 60 seconds" -ForegroundColor Cyan
Write-Host "  Script: $ScriptPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "=== How to Disable ===" -ForegroundColor Yellow
Write-Host '  Quick: Open Task Scheduler -> "MWB Connection Watchdog" -> right-click -> Disable' -ForegroundColor White
Write-Host '  PowerShell: Disable-ScheduledTask -TaskName "MWB Connection Watchdog"' -ForegroundColor White
Write-Host '  Remove entirely: Unregister-ScheduledTask -TaskName "MWB Connection Watchdog" -Confirm:$false' -ForegroundColor White
Write-Host ""
