## PotatoNet SDR/RDIO Automation Suite

**Version: 1.01**

### Run once with Admin Privileges in PowerShell

```powershell
New-EventLog -LogName Application -Source PotatoNet
```

## Event ID ranges

The suite uses the following Event Viewer ID ranges:

- **1000-1999**: informational events
- **2000-2999**: warning events
- **3000-3999**: script-level error events
- **9000+**: unhandled/common framework errors

## Script start/end Event IDs

Each script now has a unique, similar start/end pair:

- `startup.ps1`: start **1010**, end **1011**
- `watchdog.ps1`: start **1020**, end **1021**
- `sdr-cleanlogs.ps1`: start **1030**, end **1031**
- `sdr-backup.ps1`: start **1040**, end **1041**
- `sdr-scheduledreboot.ps1`: start **1050**, end **1051**

> [!NOTE]
> Startup using Task Scheduler + PowerShell can result in RDIO and SDRTrunk running hidden in the background (no visible windows).
>
> If this occurs, use `Startup.cmd` from the Startup folder (`shell:startup`) together with auto-logon (for example via SysInternals Autologon).
