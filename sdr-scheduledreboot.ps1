# =========================
# Schedule reboot + Discord notify
# =========================
. "$PSScriptRoot\common.ps1"

$ErrorActionPreference = 'Stop'
$WebhookUrl = $null
$LogFile = 'reboot.log'
$Blue = 3447003
$Yellow = 15105570

$hostName = $env:COMPUTERNAME
$timeNow = Get-Date
$rebootAt = $timeNow.AddSeconds(30)

trap {
    Invoke-PotatoUnhandledError -ErrorRecord $_
    break
}

Start-PotatoScript -ScriptName 'sdr-scheduledreboot.ps1' -LogFile $LogFile -WebhookUrl $WebhookUrl

try {
    $msg = @(
        "Host: $hostName"
        "Reboot in: 30 seconds"
        "Scheduled at: $($timeNow.ToString('yyyy-MM-dd HH:mm:ss'))"
        "Reboot at: $($rebootAt.ToString('yyyy-MM-dd HH:mm:ss'))"
    ) -join "`n"

    Send-DiscordEmbed -Url $WebhookUrl -Title "$(Get-PotatoEmoji -Name 'warning') Scheduled reboot initiated" -Description $msg -Color $Yellow -LogFile $LogFile
    Write-PotatoLog -LogFile $LogFile -Message 'Reboot notification sent.' -EventId 1200

    Write-PotatoLog -LogFile $LogFile -Message 'Scheduling reboot in 30 seconds...' -EventId 1201
    shutdown.exe /r /t 30 /c "Scheduled reboot triggered by PowerShell script" | Out-Null

    Stop-PotatoScript -Status 'completed' -Level 'INFO'
    exit 0
}
catch {
    Write-PotatoLog -LogFile $LogFile -Level 'ERROR' -Message "Failed to send Discord notification. Reboot aborted. Error: $($_.Exception.Message)" -EventId 2200
    Stop-PotatoScript -Status 'failed' -Level 'ERROR'
    exit 1
}
