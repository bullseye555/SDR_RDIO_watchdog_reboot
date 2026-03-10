# =========================
# Config
# =========================
. "$PSScriptRoot\common.ps1"

$ErrorActionPreference = 'Stop'
$WebhookUrl = $null

$TargetPaths = @(
    "C:\Users\nabro\sdrtrunk\logs",
    "C:\Users\nabro\sdrtrunk\event_logs",
    "C:\Users\nabro\sdrtrunk\recordings"
)

$DaysOld = 2
$LogFile = 'cleanlogs.log'

$Blue = 3447003
$Green = 3066993
$Red = 15158332

trap {
    Invoke-PotatoUnhandledError -ErrorRecord $_
    break
}

# =========================
# Main
# =========================
Start-PotatoScript -ScriptName 'sdr-cleanlogs.ps1' -LogFile $LogFile -WebhookUrl $WebhookUrl
$cutoff = (Get-Date).AddDays(-$DaysOld)

try {
    foreach ($TargetPath in $TargetPaths) {

        if (-not (Test-Path -LiteralPath $TargetPath)) {
            $skipDesc = @(
                "Path not found: $TargetPath"
                "Host: $env:COMPUTERNAME"
                "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            ) -join "`n"

            Send-DiscordEmbed `
                -Url $WebhookUrl `
                -Title "$(Get-PotatoEmoji -Name 'cross') SDRTrunk log cleanup skipped" `
                -Description $skipDesc `
                -Color $Red

            Write-PotatoLog -LogFile $LogFile -Level 'WARN' -Message "Cleanup skipped because path was not found: $TargetPath" -EventId 2101
            continue
        }

        $files = @(Get-ChildItem -LiteralPath $TargetPath -File -Recurse -ErrorAction Stop |
            Where-Object { $_.LastWriteTime -lt $cutoff })

        $count = $files.Count
        $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
        if ($null -eq $totalBytes) { $totalBytes = 0 }
        $totalMB = [Math]::Round($totalBytes / 1MB, 2)

        $beforeDesc = @(
            "Host: $env:COMPUTERNAME"
            "Path: $TargetPath"
            "Cutoff: > $DaysOld days old (before $($cutoff.ToString('yyyy-MM-dd HH:mm:ss')))"
            "Candidates: $count file(s), approx $totalMB MB"
            "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        ) -join "`n"

        Send-DiscordEmbed `
            -Url $WebhookUrl `
            -Title "$(Get-PotatoEmoji -Name 'broom') SDRTrunk log cleanup starting" `
            -Description $beforeDesc `
            -Color $Blue

        Write-PotatoLog -LogFile $LogFile -Message "Cleanup starting for $TargetPath with $count candidate files ($totalMB MB)" -EventId 1200

        $deletedCount = 0
        $deletedBytes = 0

        foreach ($f in $files) {
            try {
                $len = $f.Length
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                $deletedCount++
                $deletedBytes += $len
            }
            catch {
                Write-PotatoLog -LogFile $LogFile -Level 'WARN' -Message "Failed to delete $($f.FullName): $($_.Exception.Message)" -EventId 2102
            }
        }

        $deletedMB = [Math]::Round($deletedBytes / 1MB, 2)

        $afterDesc = @(
            "Host: $env:COMPUTERNAME"
            "Path: $TargetPath"
            "Deleted: $deletedCount of $count file(s)"
            "Freed: approx $deletedMB MB"
            "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        ) -join "`n"

        Send-DiscordEmbed `
            -Url $WebhookUrl `
            -Title "$(Get-PotatoEmoji -Name 'check') SDRTrunk log cleanup completed" `
            -Description $afterDesc `
            -Color $Green

        Write-PotatoLog -LogFile $LogFile -Message "Cleanup completed for ${TargetPath}: deleted $deletedCount of $count file(s), freed $deletedMB MB" -EventId 1201
    }

    Stop-PotatoScript -Status 'completed' -Level 'INFO'
}
catch {
    $err = $_.Exception.Message
    Write-PotatoLog -LogFile $LogFile -Level 'ERROR' -Message "Cleanup failed: $err" -EventId 2200

    $errorDesc = @(
        "Host: $env:COMPUTERNAME"
        "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "Error: $err"
    ) -join "`n"

    try {
        Send-DiscordEmbed `
            -Url $WebhookUrl `
            -Title "$(Get-PotatoEmoji -Name 'cross') SDRTrunk log cleanup FAILED" `
            -Description $errorDesc `
            -Color $Red
    }
    catch {
    }

    Stop-PotatoScript -Status 'failed' -Level 'ERROR'
    return
}