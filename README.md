### Run once with Admin Priviledges in PowerShell

```
New-EventLog -LogName Application -Source PotatoNetStartupScript
```

> [!NOTE]
> Startup using the Task Scheduler & PowerShell script results in RDIO and SDRTrunk running hidden in the background - no visible windows.
>
> Reverted to using CMD to trigger the PS job - place shortcut to the file into the startup folder [use the RUN window [WIN + R] to get to `shell:startup`], in combination with auto-logon [using SysInternals Suite]
