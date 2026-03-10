. "C:\PotatoNet\scripts\common.ps1"

$ErrorActionPreference = 'Stop'
$WebhookUrl = $null
$LogFile = 'startup.log'
$sdrState = "C:\PotatoNet\state\sdr_state.json"
$Blue = 3447003
$Yellow = 15105570
$Green = 3066993
$Red = 15158332

trap {
    Invoke-PotatoUnhandledError -ErrorRecord $_
    break
}

Start-PotatoScript -ScriptName 'startup.ps1' -LogFile $LogFile -WebhookUrl $WebhookUrl

try {

    if (!(Test-Path -LiteralPath $sdrState)) {
        $initialState = @{
            pid = ''
            last_restart = ''
        }

        $initialState | ConvertTo-Json | Set-Content -LiteralPath $sdrState -Encoding UTF8

        Write-PotatoLog -LogFile $LogFile -Message "Created missing SDR state file at $sdrState" -EventId 1100
    }

    Write-PotatoLog -LogFile $LogFile -Message 'Startup triggered' -EventId 1200

    # -----------------------------
    # Startup notification
    # -----------------------------
    $startupDesc = @(
        "Host: $env:COMPUTERNAME"
        "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    ) -join "`n"

    Send-DiscordEmbed `
        -Url $WebhookUrl `
        -Title "$(Get-PotatoEmoji -Name 'warning') SDR & RDIO Startup Commenced" `
        -Description $startupDesc `
        -Color $Blue

    # -----------------------------
    # Start SDRTrunk
    # -----------------------------
    $proc = Start-Process "C:\Users\nabro\Desktop\sdr-trunk.bat - Shortcut.lnk" -PassThru

    $sdr = Get-Content -LiteralPath $sdrState | ConvertFrom-Json
    $sdr.pid = $proc.Id
    $sdr.last_restart = Get-Date

    $sdr | ConvertTo-Json | Set-Content -LiteralPath $sdrState -Encoding UTF8

    Write-PotatoLog -LogFile $LogFile -Message "SDRTrunk started PID $($proc.Id)" -EventId 1201

    Start-Sleep -Seconds 5

    # -----------------------------
    # Start RDIO
    # -----------------------------
    Start-Process "C:\Users\nabro\Desktop\rdio.bat"

    Write-PotatoLog -LogFile $LogFile -Message 'RDIO started' -EventId 1202

    # -----------------------------
    # Completion notification
    # -----------------------------
    Send-DiscordEmbed `
        -Url $WebhookUrl `
        -Title "$(Get-PotatoEmoji -Name 'check') Startup Complete" `
        -Description "Host: $env:COMPUTERNAME" `
        -Color $Green

    Stop-PotatoScript -Status 'completed' -Level 'INFO'
}
catch {

    $err = $_.Exception.Message

    Write-PotatoLog -LogFile $LogFile -Level 'ERROR' -Message "Startup failed: $err" -EventId 2200

    try {
        $errorDesc = @(
            "Host: $env:COMPUTERNAME"
            "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            "Error: $err"
        ) -join "`n"

        Send-DiscordEmbed `
            -Url $WebhookUrl `
            -Title "$(Get-PotatoEmoji -Name 'cross') Startup Failed" `
            -Description $errorDesc `
            -Color $Red
    }
    catch {
    }

    Stop-PotatoScript -Status 'failed' -Level 'ERROR'
    throw
}