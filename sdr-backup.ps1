# =========================
# Config
# =========================
. "$PSScriptRoot\common.ps1"

$ErrorActionPreference = 'Stop'
$WebhookUrl = $null

$TargetPaths = @(
    "C:\Users\nabro\sdrtrunk\configuration",
    "C:\Users\nabro\sdrtrunk\playlist",
    "C:\Users\nabro\sdrtrunk\settings",
    "C:\Users\nabro\sdrtrunk\streaming",
    "C:\Users\nabro\sdrtrunk\SDRTrunk.properties"
)

$archiveFilename = "SDRTunk$(Get-Date -Format yyyyMMdd).zip"
$backupRoot = "C:\BackupStaging\"
$TargetPathsString = $TargetPaths -join ", "
$destinationPath = "Bullseye's Google Drive\System\SDRTrunk Backup"
$LogFile = 'backup.log'

$CertFile = $backupRoot + "REPLACE_ME"
$CertPassword = "REPLACE_ME"
$Project = "REPLACE_ME"
$ServiceAccountName = "REPLACE_ME"
$ServiceAccount = "REPLACE_ME"

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
Start-PotatoScript -ScriptName 'sdr-backup.ps1' -LogFile $LogFile -WebhookUrl $WebhookUrl -StartEventId 1040

try {
    $files = @(Get-ChildItem -Path $TargetPaths -File -Recurse -ErrorAction Stop)
    $count = $files.Count

    $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $totalBytes) { $totalBytes = 0 }
    $totalMB = [Math]::Round($totalBytes / 1MB, 2)

    Write-PotatoLog -Message "Preparing backup from $count file(s) totalling approximately $totalMB MB" -Level 'INFO' -LogFile $LogFile -EventId 1200

    $archive = Join-Path ($backupRoot + "Staging") $archiveFilename
    Compress-Archive -Path $TargetPaths -DestinationPath $archive -Force

    $totalArchiveBytes = (Get-Item -LiteralPath $archive -ErrorAction Stop).Length
    if ($null -eq $totalArchiveBytes) { $totalArchiveBytes = 0 }
    $totalArchiveMB = [Math]::Round($totalArchiveBytes / 1MB, 2)

    Write-PotatoLog -Message "Archive created at $archive with size approximately $totalArchiveMB MB" -Level 'INFO' -LogFile $LogFile -EventId 1201

    $beforeDesc = @(
        "Host: $env:COMPUTERNAME"
        "Paths: $TargetPathsString"
        "Destination: $destinationPath\$archiveFilename"
        "Candidates: $count file(s), approx $totalMB MB"
        "Archive Size: $totalArchiveMB MB"
        "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    ) -join "`n"

    Send-DiscordEmbed `
        -Url $WebhookUrl `
        -Title "$(Get-PotatoEmoji -Name 'backup') SDRTrunk settings backup starting" `
        -Description $beforeDesc `
        -Color $Blue

    Add-Type -AssemblyName System.Security
    Add-Type -AssemblyName System.Net
    $VerbosePreference = "Continue"

    $Scope = "https://www.googleapis.com/auth/drive"
    $ExpirationSeconds = 3600

    if (-not (Test-Path -LiteralPath $CertFile)) {
        throw "Certificate file not found: $CertFile"
    }

    $Certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $CertFile,
        $CertPassword,
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
    )

    $RSACryptoServiceProvider = New-Object System.Security.Cryptography.RSACryptoServiceProvider
    $RSACryptoServiceProvider.ImportParameters($Certificate.PrivateKey.ExportParameters($true))

    $JwtHeader = '{"alg":"RS256","typ":"JWT"}'
    $JwtHeaderBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($JwtHeader))
    $JwtHeaderBase64UrlEncoded = $JwtHeaderBase64 -replace "/","_" -replace "\+","-" -replace "=", ""

    $Now = (Get-Date).ToUniversalTime()
    $NowUnixTimestamp = (Get-Date -Date ($Now.DateTime) -UFormat %s)
    $Expiration = $Now.AddSeconds($ExpirationSeconds)
    $ExpirationUnixTimestamp = (Get-Date -Date ($Expiration.DateTime) -UFormat %s)

    $JwtClaimSet = @"
{"iss":"$ServiceAccount","scope":"$Scope","aud":"https://oauth2.googleapis.com/token","exp":$ExpirationUnixTimestamp,"iat":$NowUnixTimestamp}
"@

    $JwtClaimSetBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($JwtClaimSet))
    $JwtClaimSetBase64UrlEncoded = $JwtClaimSetBase64 -replace "/","_" -replace "\+","-" -replace "=", ""

    $StringToSign = $JwtHeaderBase64UrlEncoded + "." + $JwtClaimSetBase64UrlEncoded
    $SHA256 = [System.Security.Cryptography.SHA256]::Create()
    $Hash = $SHA256.ComputeHash([Text.Encoding]::UTF8.GetBytes($StringToSign))
    $SignatureBase64 = [Convert]::ToBase64String(
        $RSACryptoServiceProvider.SignData(
            [System.Text.Encoding]::UTF8.GetBytes($StringToSign),
            "SHA256"
        )
    )
    $SignatureBase64UrlEncoded = $SignatureBase64 -replace "/","_" -replace "\+","-" -replace "=", ""

    $Jwt = $JwtHeaderBase64UrlEncoded + "." + $JwtClaimSetBase64UrlEncoded + "." + $SignatureBase64UrlEncoded
    $Body = "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=$Jwt"
    $uri = "https://www.googleapis.com/oauth2/v4/token"

    $AccessToken = Invoke-RestMethod -Method Post -Uri $uri -Body $Body -ContentType "application/x-www-form-urlencoded" |
        Select-Object -ExpandProperty access_token

    $SourceFile = $archive
    $sourceItem = Get-Item -LiteralPath $SourceFile -ErrorAction Stop
    $sourceBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($sourceItem.FullName))
    $sourceMime = [System.Web.MimeMapping]::GetMimeMapping($sourceItem.FullName)

    $supportsTeamDrives = 'false'

    $uploadMetadata = @{
        originalFilename = $sourceItem.Name
        name = $sourceItem.Name
        description = $sourceItem.VersionInfo.FileDescription
        parents = @('1BLYsMKXev78MB6Axh6NpZ1BDxpewOhD_')
    }

    $crlf = "`r`n"
    $metadataJson = $uploadMetadata | ConvertTo-Json -Depth 5
    $uploadBody =
        "--boundary$crlf" +
        "Content-Type: application/json; charset=UTF-8$crlf$crlf" +
        "$metadataJson$crlf$crlf" +
        "--boundary$crlf" +
        "Content-Type: $sourceMime$crlf" +
        "Content-Transfer-Encoding: base64$crlf$crlf" +
        "$sourceBase64$crlf" +
        "--boundary--$crlf"

    $uploadHeaders = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type" = 'multipart/related; boundary=boundary'
        "Content-Length" = $uploadBody.Length
    }

    $response = Invoke-RestMethod `
        -Uri "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsTeamDrives=$supportsTeamDrives" `
        -Method Post `
        -Headers $uploadHeaders `
        -Body $uploadBody

    Write-PotatoLog -Message "Backup upload completed successfully to $destinationPath\$archiveFilename" -Level 'INFO' -LogFile $LogFile -EventId 1202

    Remove-Item -LiteralPath $archive -Force -ErrorAction Stop
    Write-PotatoLog -Message "Local archive removed after upload: $archive" -Level 'INFO' -LogFile $LogFile -EventId 1203

    $afterDesc = @(
        "Host: $env:COMPUTERNAME"
        "Paths: $TargetPathsString"
        "Destination: $destinationPath\$archiveFilename"
        "Candidates: $count file(s), approx $totalMB MB"
        "Archive Size: $totalArchiveMB MB"
        "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    ) -join "`n"

    Send-DiscordEmbed `
        -Url $WebhookUrl `
        -Title "$(Get-PotatoEmoji -Name 'check') SDRTrunk settings backup completed" `
        -Description $afterDesc `
        -Color $Green

    Stop-PotatoScript -Status 'completed successfully' -Level 'INFO'
}
catch {
    $err = $_.Exception.Message
    Write-PotatoLog -Message "Backup script failed: $err" -Level 'ERROR' -LogFile $LogFile -EventId 3000

    $errorDesc = @(
        "Host: $env:COMPUTERNAME"
        "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "Error: $err"
    ) -join "`n"

    try {
        Send-DiscordEmbed `
            -Url $WebhookUrl `
            -Title "$(Get-PotatoEmoji -Name 'cross') SDRTrunk settings backup FAILED" `
            -Description $errorDesc `
            -Color $Red
    }
    catch {
    }

    Stop-PotatoScript -Status 'failed' -Level 'ERROR'
    return
}