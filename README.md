# Mouse without Borders Connection Watchdog

Auto-reconnect watchdog for [Microsoft Mouse without Borders](https://www.microsoft.com/en-us/garage/wall-of-fame/mouse-without-borders/) (MWB) on Windows.

MWB allows seamless mouse and keyboard sharing between Windows machines, but it has no built-in auto-reconnect capability. Network interruptions -- even brief ones -- drop the MWB connection, requiring manual intervention (Ctrl+Alt+R or application restart) to restore it.

This watchdog monitors the MWB TCP connection and automatically restarts MWB via its Windows service when the connection drops. No UAC prompts, no manual intervention.

## How It Works

Every 60 seconds, the watchdog:

1. Checks if MWB is running (skips if intentionally closed)
2. Pings the partner machine (skips if off/asleep)
3. Checks for an ESTABLISHED TCP connection on port 15100
4. If the connection is down but the partner is reachable, restarts MWB via the `MouseWithoutBordersSvc` Windows service

Safety features:
- **Cooldown**: After 3 consecutive failed restarts, pauses for 10 minutes before retrying
- **No UAC prompts**: Uses the MWB Windows service (runs as SYSTEM) instead of launching the exe directly
- **Logs everything**: Restart events, failures, and cooldowns logged to `mwb-watchdog.log`

## Requirements

- Windows 10 or 11
- Microsoft Garage Mouse without Borders 2.2.1.x (standalone version)
- Both machines on the same subnet
- MWB already paired and working between the two machines
- Administrator access for installation

## Installation

1. Copy `mwb_watchdog.ps1` and `create_mwb_watchdog_task.ps1` to your MWB installation directory:
   ```
   C:\Program Files (x86)\Microsoft Garage\Mouse without Borders\
   ```

2. Edit `mwb_watchdog.ps1` and set `$PartnerIP` to your partner machine's IP address:
   ```powershell
   $PartnerIP = "192.0.2.100"  # Change to your partner's IP
   ```

3. Open PowerShell **as Administrator** and run:
   ```powershell
   & "C:\Program Files (x86)\Microsoft Garage\Mouse without Borders\create_mwb_watchdog_task.ps1"
   ```

4. Verify:
   ```powershell
   Get-ScheduledTask -TaskName "MWB Connection Watchdog" | Format-List TaskName, State
   ```

## Disabling / Removing

| Action | Method |
|--------|--------|
| **Disable temporarily** | Task Scheduler: right-click "MWB Connection Watchdog" -> Disable |
| **Disable via PowerShell** | `Disable-ScheduledTask -TaskName "MWB Connection Watchdog"` |
| **Re-enable** | `Enable-ScheduledTask -TaskName "MWB Connection Watchdog"` |
| **Remove entirely** | `Unregister-ScheduledTask -TaskName "MWB Connection Watchdog" -Confirm:$false` |
| **Check log** | `Get-Content "C:\Program Files (x86)\Microsoft Garage\Mouse without Borders\mwb-watchdog.log"` |
| **Reset state** | Delete `mwb-watchdog-state.json` from the MWB directory |

## Configuration

All settings are at the top of `mwb_watchdog.ps1`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `$PartnerIP` | `CHANGE_ME` | IP address of the partner machine |
| `$MWBPort` | `15100` | MWB communication port |
| `$MaxConsecutiveRestarts` | `3` | Failed restarts before cooldown |
| `$CooldownMinutes` | `10` | Cooldown duration after max failures |
| `$MaxLogSizeMB` | `2` | Log file rotation threshold |

## PowerToys Version

This watchdog was built for the **standalone Microsoft Garage** version of Mouse without Borders (v2.2.x). If you're using the **PowerToys** integrated version, you'll need to update:

- Process name: `MouseWithoutBorders` -> `PowerToys.MouseWithoutBorders`
- Helper process: `MouseWithoutBordersHelper` -> `PowerToys.MouseWithoutBordersHelper`
- Service name: check with `Get-Service | Where-Object { $_.DisplayName -match "Mouse" }`
- Installation path: update `$MWBExePath` to the PowerToys path

The standalone and PowerToys versions are **incompatible** -- they cannot pair with each other. Both machines must use the same version.

## Known Limitations

- **One-directional**: Only restarts MWB on the machine where the watchdog is installed. Deploy on both machines for bidirectional coverage.
- **60-second detection delay**: The polling interval. Adjustable by modifying the scheduled task's repetition interval.
- **No API**: MWB has no programmatic reconnect command. Recovery is done by restarting the service.

## Background

MWB has no published API, no CLI, and no auto-reconnect feature. Multiple feature requests exist on the [PowerToys GitHub](https://github.com/microsoft/PowerToys) (#26718, #40336, #40286, #27389) but none have been implemented. This watchdog fills that gap using indirect methods: TCP connection monitoring and service-based process lifecycle management.

## License

MIT
