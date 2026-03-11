. "C:\PotatoNet\scripts\common.ps1"

$ErrorActionPreference = 'Stop'
$WebhookUrl = $null
$LogFile = 'watchdog.log'

$now = Get-Date
$recordings = "C:\Users\nabro\SDRTrunk\recordings"
$sdrStateFile = "C:\PotatoNet\state\sdr_state.json"
$counterFile = "C:\PotatoNet\state\restart_counters.json"
$sqlite = "C:\Users\nabro\Desktop\rdio\sqlite3.exe"
$db = "C:\Users\nabro\Desktop\rdio\rdio-scanner.db"
$sdrLaunchTarget = "C:\Users\nabro\Desktop\sdr-trunk.bat - Shortcut.lnk"
$rdioLaunchTarget = "C:\Users\nabro\Desktop\rdio.bat"
$recordingStaleMinutes = 30
$restartThrottleHours = 1

function Get-MelbourneTimeZone {
    return [System.TimeZoneInfo]::FindSystemTimeZoneById('AUS Eastern Standard Time')
}

function Convert-ToMelbourneString {
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$DateTimeValue
    )

    $melbourneTz = Get-MelbourneTimeZone

    if ($DateTimeValue.Kind -eq [System.DateTimeKind]::Utc) {
        $local = [System.TimeZoneInfo]::ConvertTimeFromUtc($DateTimeValue, $melbourneTz)
    }
    else {
        $local = [System.TimeZoneInfo]::ConvertTime($DateTimeValue, $melbourneTz)
    }

    return $local.ToString('dd/MM/yyyy HH:mm:ss')
}

function Convert-RdioUtcToMelbourneString {
    param(
        [Parameter(Mandatory = $false)]
        [string]$RdioDateTime
    )

    if ([string]::IsNullOrWhiteSpace($RdioDateTime)) {
        return ''
    }

    # Example input:
    # 2026-03-05 22:37:21.8913309 +0000 UTC
    $normalized = $RdioDateTime.Trim()
    $normalized = $normalized -replace ' UTC$','Z'
    $normalized = $normalized -replace ' \+0000',''

    $utc = [datetime]::Parse(
        $normalized,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    )

    return Convert-ToMelbourneString -DateTimeValue $utc
}

function Initialize-StateFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [hashtable]$DefaultState,
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [int]$EventId
    )

    if (Test-Path -LiteralPath $Path) {
        return
    }

    $DefaultState | ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding UTF8
    Write-PotatoLog -LogFile $LogFile -Message "Created missing $Description at $Path" -EventId $EventId
}

function Restart-SdrTrunk {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$SdrState,
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Counters,
        [Parameter(Mandatory = $true)]
        [string]$Reason,
        [Parameter(Mandatory = $true)]
        [string]$DiscordTitle,
        [Parameter(Mandatory = $true)]
        [string[]]$DescriptionLines,
        [Parameter(Mandatory = $true)]
        [int]$Color,
        [switch]$StopExisting
    )

    Write-PotatoLog -LogFile $LogFile -Level 'WARN' -Message "SDRTrunk restart requested: $Reason" -EventId 2202

    if ($StopExisting -and $SdrState.pid) {
        Stop-Process -Id $SdrState.pid -Force -ErrorAction SilentlyContinue
    }

    $p = Start-Process $sdrLaunchTarget -PassThru
    $SdrState.pid = $p.Id
    $SdrState.last_restart = $now
    $SdrState | ConvertTo-Json | Set-Content -LiteralPath $sdrStateFile -Encoding UTF8

    $Counters.sdr_restarts++
    $Counters | ConvertTo-Json | Set-Content -LiteralPath $counterFile -Encoding UTF8

    $desc = @(
        $DescriptionLines
        "New PID: $($p.Id)"
    ) -join "`n"

    Send-DiscordEmbed -Url $WebhookUrl -Title $DiscordTitle -Description $desc -Color $Color
}

trap {
    Invoke-PotatoUnhandledError -ErrorRecord $_
    break
}

Start-PotatoScript -ScriptName 'watchdog.ps1' -LogFile $LogFile -WebhookUrl $WebhookUrl

try {
    $nowLocal = Convert-ToMelbourneString -DateTimeValue $now

    Initialize-StateFile -Path $sdrStateFile -DefaultState @{ pid = ''; last_restart = '' } -Description 'SDR state file' -EventId 1100
    Initialize-StateFile -Path $counterFile -DefaultState @{ rdio_errors = 0; sdr_restarts = 0; last_report = '' } -Description 'counter file' -EventId 1101

    $sdr = Get-Content -LiteralPath $sdrStateFile | ConvertFrom-Json
    $counters = Get-Content -LiteralPath $counterFile | ConvertFrom-Json

    # --------------------------------------------------
    # SDRTrunk process running check
    # --------------------------------------------------
    $procRunning = $false
    if ($sdr.pid) {
        $proc = Get-Process -Id $sdr.pid -ErrorAction SilentlyContinue
        if ($proc) {
            $procRunning = $true
        }
    }

    if (-not $procRunning) {
        Restart-SdrTrunk -SdrState $sdr -Counters $counters -Reason 'Process was not running' -DiscordTitle 'SDRTrunk Restarted (Process Missing)' -DescriptionLines @(
            'Process was not running'
            "Restart time: $nowLocal"
        ) -Color 15158332

        Stop-PotatoScript -Status 'completed' -Level 'INFO'
        return
    }

    # --------------------------------------------------
    # SDRTrunk recordings freshness check
    # --------------------------------------------------
    if (-not (Test-Path -LiteralPath $recordings)) {
        Write-PotatoLog -LogFile $LogFile -Level 'WARN' -Message "Recordings folder missing: $recordings" -EventId 2206
    }
    else {
        $latest = Get-ChildItem -LiteralPath $recordings -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if ($latest) {
            $lastRecording = $latest.LastWriteTime
            $lastRecordingLocal = Convert-ToMelbourneString -DateTimeValue $lastRecording

            if ($lastRecording -lt $now.AddMinutes(-$recordingStaleMinutes)) {
                $restartAllowed = $true

                if ($sdr.last_restart) {
                    $lastRestart = [datetime]$sdr.last_restart
                    if ($lastRestart -gt $now.AddHours(-$restartThrottleHours)) {
                        $restartAllowed = $false
                        Write-PotatoLog -LogFile $LogFile -Level 'WARN' -Message "SDRTrunk appears hung but restart was skipped due to one-per-$restartThrottleHours-hour throttle. Last restart: $lastRestart" -EventId 2204
                    }
                }

                if ($restartAllowed) {
                    Restart-SdrTrunk -SdrState $sdr -Counters $counters -Reason 'No recent recordings' -DiscordTitle 'SDRTrunk Restarted (No Recordings)' -DescriptionLines @(
                        "Check time: $nowLocal"
                        "Last recording: $lastRecordingLocal"
                        "Restart performed: $nowLocal"
                    ) -Color 15105570 -StopExisting
                }
            }
        }
        else {
            Write-PotatoLog -LogFile $LogFile -Level 'WARN' -Message "No recordings found in $recordings" -EventId 2205
        }
    }

    # --------------------------------------------------
    # RDIO process running check
    # --------------------------------------------------
    $rdioRunning = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "*rdio*" }
    if (-not $rdioRunning) {
        Write-PotatoLog -LogFile $LogFile -Level 'WARN' -Message 'RDIO process missing - restarting' -EventId 2203
        Start-Process $rdioLaunchTarget

        $desc = @(
            "Process was not running"
            "Restart time: $nowLocal"
        ) -join "`n"

        Send-DiscordEmbed -Url $WebhookUrl -Title 'RDIO Restarted' -Description $desc -Color 15158332
    }

    # --------------------------------------------------
    # RDIO SQLite error check
    # --------------------------------------------------
    if ((Test-Path -LiteralPath $sqlite) -and (Test-Path -LiteralPath $db)) {
        $sqlFile = Join-Path $env:TEMP "potatonet_rdio_query.sql"

@'
SELECT
    COUNT(*),
    MIN(replace(dateTime, ' +0000 UTC', '')),
    MAX(replace(dateTime, ' +0000 UTC', ''))
FROM (
    SELECT dateTime, message
    FROM rdioScannerLogs
    WHERE level = 'error'
      AND message LIKE '%Post "https://Rdio.tehintartubes.net/api/call-upload"%'
      AND datetime(replace(dateTime, ' +0000 UTC', 'Z')) >= datetime('now','-30 minutes')
);
'@ | Set-Content -LiteralPath $sqlFile -Encoding UTF8

        try {
            $res = ((& $sqlite $db ".read $sqlFile" 2>&1) | Out-String).Trim()
            Write-PotatoLog -LogFile $LogFile -Message "RDIO sqlite query result: $res" -EventId 1300

            if ($res) {
                $parts = $res -split '\|', 4

                if ($parts.Count -ge 3) {
                    $count = [int]$parts[0]

                    if ($count -gt 0) {
                        $minUtc = $parts[1]
                        $maxUtc = $parts[2]

                        $minLocal = Convert-RdioUtcToMelbourneString -RdioDateTime $minUtc
                        $maxLocal = Convert-RdioUtcToMelbourneString -RdioDateTime $maxUtc

                        $counters.rdio_errors += $count
                        $counters | ConvertTo-Json | Set-Content -LiteralPath $counterFile -Encoding UTF8

                        $desc = @(
                            "Check time: $nowLocal"
                            "Error window: $minLocal -> $maxLocal"
                            "Total errors: $count"
                        ) -join "`n"

                        Send-DiscordEmbed -Url $WebhookUrl -Title "RDIO Upload Errors" -Description $desc -Color 15158332
                    }
                }
                else {
                    Write-PotatoLog -LogFile $LogFile -Level 'WARN' -Message "RDIO sqlite result could not be parsed: $res" -EventId 2301
                }
            }
        }
        finally {
            if (Test-Path -LiteralPath $sqlFile) {
                Remove-Item -LiteralPath $sqlFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        Write-PotatoLog -LogFile $LogFile -Level 'WARN' -Message "RDIO sqlite check skipped because sqlite3.exe or database file was not found." -EventId 2300
    }

    # --------------------------------------------------
    # Daily health summary
    # --------------------------------------------------
    if ($now.Hour -eq 18 -and $counters.last_report -ne $now.ToString("yyyy-MM-dd")) {
        $desc = @(
            "Report time: $nowLocal"
            "SDRTrunk restarts (24h): $($counters.sdr_restarts)"
            "RDIO errors (24h): $($counters.rdio_errors)"
        ) -join "`n"

        Send-DiscordEmbed -Url $WebhookUrl -Title 'PotatoNet Daily Health' -Description $desc -Color 3066993

        $counters.last_report = $now.ToString("yyyy-MM-dd")
        $counters.sdr_restarts = 0
        $counters.rdio_errors = 0
        $counters | ConvertTo-Json | Set-Content -LiteralPath $counterFile -Encoding UTF8
    }

    Stop-PotatoScript -Status 'completed' -Level 'INFO'
}
catch {
    $err = $_.Exception.Message
    Write-PotatoLog -LogFile $LogFile -Level 'ERROR' -Message "Watchdog failed: $err" -EventId 3200

    try {
        $desc = @(
            "Host: $env:COMPUTERNAME"
            "Time: $nowLocal"
            "Error: $err"
        ) -join "`n"

        Send-DiscordEmbed -Url $WebhookUrl -Title "$(Get-PotatoEmoji -Name 'cross') Watchdog Failed" -Description $desc -Color 15158332
    }
    catch {
    }

    Stop-PotatoScript -Status 'failed' -Level 'ERROR'
    return
}
