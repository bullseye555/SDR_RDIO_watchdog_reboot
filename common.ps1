# ==========================================================
# PotatoNet Common Functions
# Shared logging, rotation, script header/footer, Discord helper,
# global error trap, script locking, and launch diagnostics
# ==========================================================

$Global:PotatoNetRoot = "C:\PotatoNet"
$Global:LogDir = Join-Path $Global:PotatoNetRoot "Logs"
$Global:LockDir = Join-Path $Global:PotatoNetRoot "Locks"
$Global:EventSource = "PotatoNet"
$Global:DefaultWebhookUrl = "REPLACE_ME"

if (!(Test-Path -LiteralPath $Global:PotatoNetRoot)) {
    New-Item -ItemType Directory -Path $Global:PotatoNetRoot -Force | Out-Null
}
if (!(Test-Path -LiteralPath $Global:LogDir)) {
    New-Item -ItemType Directory -Path $Global:LogDir -Force | Out-Null
}
if (!(Test-Path -LiteralPath $Global:LockDir)) {
    New-Item -ItemType Directory -Path $Global:LockDir -Force | Out-Null
}

try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($Global:EventSource)) {
        New-EventLog -LogName Application -Source $Global:EventSource
    }
}
catch {
    # Source creation may require elevation; do not break the script here.
}

function Resolve-PotatoWebhookUrl {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Url
    )

    if (-not [string]::IsNullOrWhiteSpace($Url)) {
        return $Url
    }

    if (-not [string]::IsNullOrWhiteSpace($script:__PotatoWebhookUrl)) {
        return $script:__PotatoWebhookUrl
    }

    return $Global:DefaultWebhookUrl
}

function Rotate-PotatoLogs {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFileName
    )

    $path = Join-Path $Global:LogDir $LogFileName
    if (!(Test-Path -LiteralPath $path)) { return }

    $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
    if ($null -eq $item) { return }

    if ($item.Length -le 10MB) { return }

    $old5 = "$path.5"
    if (Test-Path -LiteralPath $old5) {
        Remove-Item -LiteralPath $old5 -Force -ErrorAction SilentlyContinue
    }

    for ($i = 4; $i -ge 1; $i--) {
        $src = "$path.$i"
        $dst = "$path." + ($i + 1)
        if (Test-Path -LiteralPath $src) {
            Move-Item -LiteralPath $src -Destination $dst -Force
        }
    }

    Move-Item -LiteralPath $path -Destination "$path.1" -Force
}

function Write-PotatoLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO',

        [string]$LogFile = 'potatonet.log',

        [int]$EventId = 1000
    )

    $path = Join-Path $Global:LogDir $LogFile
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$timestamp [$Level] $Message"

    Rotate-PotatoLogs -LogFileName $LogFile
    Add-Content -LiteralPath $path -Value $line -Encoding UTF8

    try {
        $entryType = switch ($Level) {
            'ERROR' { 'Error' }
            'WARN'  { 'Warning' }
            default { 'Information' }
        }

        Write-EventLog -LogName Application -Source $Global:EventSource -EntryType $entryType -EventId $EventId -Message $line
    }
    catch {
        # Do not break script if Event Viewer write fails.
    }
}

function WriteLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = 'INFO',
        [string]$LogFile = 'potatonet.log',
        [int]$EventId = 1000
    )

    Write-PotatoLog -Message $Message -Level $Level -LogFile $LogFile -EventId $EventId
}

function Get-PotatoEmoji {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $normalized = $Name.Trim().ToLowerInvariant()
    $codePoint = switch ($normalized) {
        'backup'  { 128190 }
        'floppy'  { 128190 }
        'save'    { 128190 }
        'success' { 9989 }
        'check'   { 9989 }
        'warning' { 9888 }
        'warn'    { 9888 }
        'error'   { 10060 }
        'fail'    { 10060 }
        'cross'   { 10060 }
        'clean'   { 129529 }
        'broom'   { 129529 }
        default   { 9888 }
    }

    return [char]::ConvertFromUtf32($codePoint)
}

function Send-DiscordWebhook {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Url,
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$LogFile = 'potatonet.log'
    )

    $resolvedUrl = Resolve-PotatoWebhookUrl -Url $Url
    if ([string]::IsNullOrWhiteSpace($resolvedUrl) -or $resolvedUrl -eq 'REPLACE_ME_DISCORD_WEBHOOK_URL') {
        throw "Discord webhook URL is not configured."
    }

    $payloadObject = @{ content = $Message }
    $json = $payloadObject | ConvertTo-Json -Compress -Depth 5
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)

    Invoke-RestMethod `
        -Uri $resolvedUrl `
        -Method Post `
        -Body $bodyBytes `
        -ContentType "application/json; charset=utf-8" |
        Out-Null
}

function SendDiscordWebhook {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Url,
        [string]$LogFile = 'potatonet.log'
    )

    Send-DiscordWebhook -Url $Url -Message $Message -LogFile $LogFile
}

function Send-DiscordEmbed {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Url,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [int]$Color = 3447003,
        [string]$LogFile = 'potatonet.log'
    )

    $resolvedUrl = Resolve-PotatoWebhookUrl -Url $Url
    if ([string]::IsNullOrWhiteSpace($resolvedUrl) -or $resolvedUrl -eq 'REPLACE_ME_DISCORD_WEBHOOK_URL') {
        throw "Discord webhook URL is not configured."
    }

    $payloadObject = @{
        embeds = @(
            @{
                title       = $Title
                description = $Description
                color       = $Color
            }
        )
    }

    $json = $payloadObject | ConvertTo-Json -Compress -Depth 8
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)

    Invoke-RestMethod `
        -Uri $resolvedUrl `
        -Method Post `
        -Body $bodyBytes `
        -ContentType "application/json; charset=utf-8" |
        Out-Null
}

function SendDiscordEmbed {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [int]$Color = 3447003,
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Url,
        [string]$LogFile = 'potatonet.log'
    )

    Send-DiscordEmbed -Url $Url -Title $Title -Description $Description -Color $Color -LogFile $LogFile
}

function Get-PotatoLockPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName
    )

    $safeName = ($ScriptName -replace '[^a-zA-Z0-9._-]', '_')
    return Join-Path $Global:LockDir "$safeName.lock"
}

function Enter-PotatoScriptLock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName,
        [Parameter(Mandatory = $true)]
        [string]$LogFile,
        [string]$WebhookUrl
    )

    $lockPath = Get-PotatoLockPath -ScriptName $ScriptName

    if (Test-Path -LiteralPath $lockPath) {
        $existing = $null
        try {
            $existing = Get-Content -LiteralPath $lockPath -Raw -ErrorAction Stop
        }
        catch {
        }

        $msg = "Lock exists for $ScriptName at $lockPath. Existing lock content: $existing"
        Write-PotatoLog -Message $msg -Level 'WARN' -LogFile $LogFile -EventId 3001

        try {
            $desc = @(
                "Host: $env:COMPUTERNAME"
                "Script: $ScriptName"
                "Lock file: $lockPath"
                "Existing lock: $existing"
                "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            ) -join "`n"

            Send-DiscordEmbed -Url $WebhookUrl -Title "$(Get-PotatoEmoji -Name 'warning') Script already running" -Description $desc -Color 15105570 -LogFile $LogFile
        }
        catch {
        }

        throw "Script lock already exists: $lockPath"
    }

    $lockContent = @(
        "Host=$env:COMPUTERNAME"
        "PID=$PID"
        "Started=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "Script=$ScriptName"
    ) -join '; '

    Set-Content -LiteralPath $lockPath -Value $lockContent -Encoding UTF8
    $script:__PotatoLockPath = $lockPath
}

function Exit-PotatoScriptLock {
    if ($script:__PotatoLockPath -and (Test-Path -LiteralPath $script:__PotatoLockPath)) {
        Remove-Item -LiteralPath $script:__PotatoLockPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-PotatoCommandLine {
    try {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $PID" -ErrorAction Stop
        return $proc.CommandLine
    }
    catch {
        try {
            return (Get-WmiObject Win32_Process -Filter "ProcessId = $PID" -ErrorAction Stop).CommandLine
        }
        catch {
            return 'Unavailable'
        }
    }
}

function Start-PotatoScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName,
        [Parameter(Mandatory = $true)]
        [string]$LogFile,
        [string]$WebhookUrl,
        [int]$StartEventId = 1000
    )

    $script:__PotatoStartTime = Get-Date
    $script:__PotatoScriptName = $ScriptName
    $script:__PotatoLogFile = $LogFile
    $script:__PotatoWebhookUrl = Resolve-PotatoWebhookUrl -Url $WebhookUrl
    $script:__PotatoStartEventId = $StartEventId
    $script:__PotatoEndEventId = $StartEventId + 1

    Enter-PotatoScriptLock -ScriptName $ScriptName -LogFile $LogFile -WebhookUrl $script:__PotatoWebhookUrl

    Write-PotatoLog -Message "$ScriptName started on $env:COMPUTERNAME" -Level INFO -LogFile $LogFile -EventId $script:__PotatoStartEventId

    $psVersion = $PSVersionTable.PSVersion.ToString()
    $edition = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { 'Desktop' }
    $commandLine = Get-PotatoCommandLine
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { 'Unknown' }

    Write-PotatoLog -Message "Launch details: Host=$env:COMPUTERNAME; PID=$PID; ScriptPath=$scriptPath; PSVersion=$psVersion; PSEdition=$edition; CommandLine=$commandLine" -Level INFO -LogFile $LogFile -EventId 1005
}

function Stop-PotatoScript {
    param(
        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO',
        [string]$Status = 'completed',
        [string]$Result,
        [int]$EventId
    )

    try {
        if ($null -ne $script:__PotatoStartTime) {
            $elapsed = [int]((Get-Date) - $script:__PotatoStartTime).TotalSeconds
            $name = $script:__PotatoScriptName
            $log = $script:__PotatoLogFile

            if (-not [string]::IsNullOrWhiteSpace($Result)) {
                $Status = $Result
            }

            if (-not $PSBoundParameters.ContainsKey('EventId')) {
                $EventId = switch ($Level) {
                    'ERROR' {
                        if ($null -ne $script:__PotatoEndEventId) { $script:__PotatoEndEventId + 1007 } else { 2001 }
                    }
                    'WARN'  {
                        if ($null -ne $script:__PotatoEndEventId) { $script:__PotatoEndEventId + 1008 } else { 1002 }
                    }
                    default {
                        if ($null -ne $script:__PotatoEndEventId) { $script:__PotatoEndEventId } else { 1001 }
                    }
                }
            }

            Write-PotatoLog -Message "$name $Status on $env:COMPUTERNAME in $elapsed second(s)" -Level $Level -LogFile $log -EventId $EventId
        }
    }
    finally {
        Exit-PotatoScriptLock
    }
}

function Invoke-PotatoUnhandledError {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $log = if ($script:__PotatoLogFile) { $script:__PotatoLogFile } else { 'potatonet.log' }
    $scriptName = if ($script:__PotatoScriptName) { $script:__PotatoScriptName } else { 'unknown-script' }
    $webhook = Resolve-PotatoWebhookUrl -Url $script:__PotatoWebhookUrl

    $msg = $ErrorRecord.Exception.Message
    $line = $ErrorRecord.InvocationInfo.ScriptLineNumber
    $command = $ErrorRecord.InvocationInfo.Line
    $path = $ErrorRecord.InvocationInfo.ScriptName

    Write-PotatoLog -Message "Unhandled error in $scriptName. Message=$msg; Script=$path; Line=$line; Command=$command" -Level 'ERROR' -LogFile $log -EventId 9000

    try {
        $desc = @(
            "Host: $env:COMPUTERNAME"
            "Script: $scriptName"
            "Message: $msg"
            "Line: $line"
            "Command: $command"
            "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        ) -join "`n"

        Send-DiscordEmbed -Url $webhook -Title "$(Get-PotatoEmoji -Name 'cross') Unhandled script failure" -Description $desc -Color 15158332 -LogFile $log
    }
    catch {
    }

    Stop-PotatoScript -Status 'failed' -Level 'ERROR'
}
