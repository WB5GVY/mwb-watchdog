# mwb_watchdog.ps1 -- Mouse without Borders Connection Watchdog
# Monitors the MWB connection to a partner machine
# Automatically restarts MWB if the connection drops
# Runs as a scheduled task every 60 seconds under SYSTEM
#
# TO DISABLE: Open Task Scheduler -> find "MWB Connection Watchdog" -> right-click -> Disable
# TO RE-ENABLE: Same path -> right-click -> Enable
# TO REMOVE ENTIRELY: Run in elevated PowerShell:
#   Unregister-ScheduledTask -TaskName "MWB Connection Watchdog" -Confirm:$false

$ErrorActionPreference = "SilentlyContinue"

# --- Configuration ---
$PartnerIP = "CHANGE_ME"  # Set to the IP address of the partner machine
$MWBPort = 15100
$MWBExePath = "C:\Program Files (x86)\Microsoft Garage\Mouse without Borders\MouseWithoutBorders.exe"
$LogFile = "C:\Program Files (x86)\Microsoft Garage\Mouse without Borders\mwb-watchdog.log"
$StateFile = "C:\Program Files (x86)\Microsoft Garage\Mouse without Borders\mwb-watchdog-state.json"
$MaxLogSizeMB = 2
$MaxConsecutiveRestarts = 3  # Stop retrying after this many back-to-back restarts
$CooldownMinutes = 10       # After max restarts, wait this long before trying again

# --- Load state ---
$state = @{
    consecutive_restarts = 0
    last_restart = ""
    total_restarts = 0
    last_cooldown_start = ""
}
if (Test-Path $StateFile) {
    try {
        $loaded = Get-Content $StateFile -Raw | ConvertFrom-Json
        foreach ($key in @($state.Keys)) {
            if ($loaded.PSObject.Properties[$key]) {
                $state[$key] = $loaded.$key
            }
        }
    } catch {}
}

# --- Logging ---
function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$ts  $Message" -ErrorAction SilentlyContinue
    if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length / 1MB) -gt $MaxLogSizeMB) {
        $bak = "$LogFile.bak"
        if (Test-Path $bak) { Remove-Item $bak -Force }
        Rename-Item $LogFile $bak -Force
    }
}

# --- Cooldown check ---
if ($state["consecutive_restarts"] -ge $MaxConsecutiveRestarts -and $state["last_cooldown_start"]) {
    try {
        $cooldownStart = [DateTime]::Parse($state["last_cooldown_start"])
        $elapsed = (Get-Date) - $cooldownStart
        if ($elapsed.TotalMinutes -lt $CooldownMinutes) {
            # Still in cooldown -- skip this cycle silently
            exit 0
        } else {
            # Cooldown expired -- reset and try again
            $state["consecutive_restarts"] = 0
            $state["last_cooldown_start"] = ""
            Write-Log "Cooldown expired, resuming monitoring"
        }
    } catch {
        $state["consecutive_restarts"] = 0
        $state["last_cooldown_start"] = ""
    }
}

# --- Check 1: Is MWB running at all? ---
$mwbProcs = Get-Process -Name "MouseWithoutBorders" -ErrorAction SilentlyContinue
if (-not $mwbProcs) {
    Write-Log "MWB not running -- skipping (may be intentionally closed)"
    $state["consecutive_restarts"] = 0
    [PSCustomObject]$state | ConvertTo-Json | Set-Content $StateFile -Encoding UTF8 -ErrorAction SilentlyContinue
    exit 0
}

# --- Check 2: Is partner machine reachable? ---
$ping = Test-Connection -ComputerName $PartnerIP -Count 1 -Quiet -ErrorAction SilentlyContinue
if (-not $ping) {
    # Partner is offline/unreachable -- nothing we can do, don't restart MWB
    $state["consecutive_restarts"] = 0
    [PSCustomObject]$state | ConvertTo-Json | Set-Content $StateFile -Encoding UTF8 -ErrorAction SilentlyContinue
    exit 0
}

# --- Check 3: Is there an ESTABLISHED TCP connection to the partner on port 15100? ---
$connections = netstat -an | Select-String "ESTABLISHED" | Select-String $PartnerIP | Select-String "$MWBPort"
if ($connections) {
    # Connection is healthy
    if ($state["consecutive_restarts"] -gt 0) {
        Write-Log "Connection restored after $($state['consecutive_restarts']) restart(s)"
    }
    $state["consecutive_restarts"] = 0
    [PSCustomObject]$state | ConvertTo-Json | Set-Content $StateFile -Encoding UTF8 -ErrorAction SilentlyContinue
    exit 0
}

# --- Connection is down but partner is reachable -- attempt recovery ---
$state["consecutive_restarts"]++
$state["total_restarts"]++
$state["last_restart"] = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

if ($state["consecutive_restarts"] -gt $MaxConsecutiveRestarts) {
    Write-Log "COOLDOWN: $MaxConsecutiveRestarts restarts failed, pausing for $CooldownMinutes min"
    $state["last_cooldown_start"] = (Get-Date).ToString("o")
    [PSCustomObject]$state | ConvertTo-Json | Set-Content $StateFile -Encoding UTF8 -ErrorAction SilentlyContinue
    exit 0
}

Write-Log "Connection to $PartnerIP lost -- restart attempt $($state['consecutive_restarts'])/$MaxConsecutiveRestarts (total: $($state['total_restarts']))"

# Restart via the MWB Windows service (avoids UAC prompts)
# The service runs as SYSTEM and can relaunch MWB with proper privileges
$svc = Get-Service -Name "MouseWithoutBordersSvc" -ErrorAction SilentlyContinue
if ($svc) {
    # Stop the service (this also kills MWB processes)
    if ($svc.Status -eq "Running") {
        Stop-Service -Name "MouseWithoutBordersSvc" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    # Kill any remaining MWB processes
    Get-Process -Name "MouseWithoutBorders" -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Process -Name "MouseWithoutBordersHelper" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    # Start the service (relaunches MWB in user session with proper privileges)
    Start-Service -Name "MouseWithoutBordersSvc" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
} else {
    # Fallback: no service available, try direct process restart
    Get-Process -Name "MouseWithoutBorders" -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Process -Name "MouseWithoutBordersHelper" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    Start-Process -FilePath $MWBExePath -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
}

# Verify it restarted
$newProcs = Get-Process -Name "MouseWithoutBorders" -ErrorAction SilentlyContinue
if ($newProcs) {
    Write-Log "MWB restarted via service (PID: $(($newProcs | ForEach-Object { $_.Id }) -join ','))"
} else {
    Write-Log "WARNING: MWB failed to restart"
}

# --- Save state ---
[PSCustomObject]$state | ConvertTo-Json | Set-Content $StateFile -Encoding UTF8 -ErrorAction SilentlyContinue
