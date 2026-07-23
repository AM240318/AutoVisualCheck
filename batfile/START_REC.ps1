<#
.SYNOPSIS
従来の一括録画フローを開始します。

.DESCRIPTION
OBS録画、CANログ、Tera Termログ、スクリーンショットの順に開始し、
開始情報を legacy_session.marker に記録します。
OBS開始に失敗しても、OBS用PowerShellプロセスの終了を確認できた場合は
残りの開始処理を試行します。

.PARAMETER CaseNo
ケース番号です。正の数字を指定します。省略できます。

.PARAMETER Tag
録画識別用のTagです。英数字、アンダースコア、ハイフンを指定できます。
保存時に使用できるよう大文字へ正規化してマーカーに記録します。省略できます。

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\START_REC.ps1 1 WB

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\START_REC.ps1 -CaseNo 1 -Tag WB

.OUTPUTS
標準出力へ [INFO]、[WARN]、[ERROR]、[RESULT] で始まるメッセージを出力します。

.NOTES
終了コードは、エラーなしの場合0、1件以上のエラーがあった場合1です。
Windows PowerShell 5.1、nircmd.exe、obs_record_start.ps1を使用します。
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [AllowEmptyString()]
    [string]$CaseNo = '',

    [Parameter(Position = 1)]
    [AllowEmptyString()]
    [string]$Tag = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:HadError = $false
$script:HadWarning = $false

function Write-InfoMessage {
    param([string]$Message)
    [Console]::Out.WriteLine('[INFO] {0}', $Message)
}

function Add-WarningMessage {
    param([string]$Message)
    $script:HadWarning = $true
    [Console]::Out.WriteLine('[WARN] {0}', $Message)
}

function Add-ErrorMessage {
    param([string]$Message)
    $script:HadError = $true
    [Console]::Out.WriteLine('[ERROR] {0}', $Message)
}

function Convert-CaseNo {
    param([AllowNull()][string]$Value)

    $present = -not [string]::IsNullOrEmpty($Value)
    if (-not $present) {
        return [pscustomobject]@{
            IsPresent = $false
            IsValid   = $true
            Canonical = ''
        }
    }

    if ($Value -notmatch '\A[0-9]+\z') {
        return [pscustomobject]@{
            IsPresent = $true
            IsValid   = $false
            Canonical = ''
        }
    }

    $canonical = $Value.TrimStart('0')
    if ($canonical.Length -eq 0) {
        return [pscustomobject]@{
            IsPresent = $true
            IsValid   = $false
            Canonical = ''
        }
    }

    return [pscustomobject]@{
        IsPresent = $true
        IsValid   = $true
        Canonical = $canonical
    }
}

function Convert-RecordingTag {
    param([AllowNull()][string]$Value)

    $present = -not [string]::IsNullOrEmpty($Value)
    if (-not $present) {
        return [pscustomobject]@{
            IsPresent = $false
            IsValid   = $true
            Normalized = ''
        }
    }

    if ($Value -notmatch '\A[A-Za-z0-9_-]+\z') {
        return [pscustomobject]@{
            IsPresent = $true
            IsValid   = $false
            Normalized = ''
        }
    }

    return [pscustomobject]@{
        IsPresent = $true
        IsValid   = $true
        Normalized = $Value.ToUpperInvariant()
    }
}

function Get-UtcTimestamp {
    return [DateTime]::UtcNow.ToString(
        'o',
        [Globalization.CultureInfo]::InvariantCulture
    )
}

function Remove-CurrentMarker {
    param([string]$Path)

    try {
        if (Test-Path -LiteralPath $Path -PathType Container) {
            throw "Marker path is a directory: `"$Path`""
        }

        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            Remove-Item -LiteralPath $Path -Force
            if (Test-Path -LiteralPath $Path) {
                throw "Marker remained after removal: `"$Path`""
            }
            Write-InfoMessage "Invalidated marker: `"$Path`""
        }
        return $true
    }
    catch {
        Add-ErrorMessage "Failed to invalidate marker `"$Path`": $($_.Exception.Message)"
        return $false
    }
}

function Publish-Marker {
    param(
        [string]$Path,
        [string[]]$Lines
    )

    $temporaryPath = '{0}.{1}.tmp' -f $Path, [Guid]::NewGuid().ToString('N')
    try {
        if (Test-Path -LiteralPath $Path -PathType Container) {
            throw "Marker path is a directory: `"$Path`""
        }

        $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllLines($temporaryPath, $Lines, $utf8WithoutBom)

        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [IO.File]::Replace($temporaryPath, $Path, $null)
        }
        else {
            [IO.File]::Move($temporaryPath, $Path)
        }

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "Published marker was not found: `"$Path`""
        }
        if (Test-Path -LiteralPath $temporaryPath) {
            throw "Temporary marker remained after publication: `"$temporaryPath`""
        }

        Write-InfoMessage "Updated marker: `"$Path`""
        return $true
    }
    catch {
        Add-ErrorMessage "Failed to publish marker `"$Path`": $($_.Exception.Message)"
        try {
            if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
                Remove-Item -LiteralPath $temporaryPath -Force
            }
        }
        catch {
            Add-WarningMessage "Failed to remove temporary marker `"$temporaryPath`": $($_.Exception.Message)"
        }
        return $false
    }
}

function New-LegacyMarkerLines {
    param(
        [string]$SessionId,
        [string]$ArgsValid,
        [string]$CaseNoCanonical,
        [string]$TagNormalized,
        [string]$SessionStartTimeUtc,
        [string]$VideoStartTimeUtc,
        [string]$LogStartTimeUtc,
        [string]$ObsStartSucceeded
    )

    return @(
        'Version=2'
        "SessionId=$SessionId"
        "ArgsValid=$ArgsValid"
        "CaseNoCanonical=$CaseNoCanonical"
        "TagNormalized=$TagNormalized"
        "SessionStartTimeUtc=$SessionStartTimeUtc"
        "VideoStartTimeUtc=$VideoStartTimeUtc"
        "LogStartTimeUtc=$LogStartTimeUtc"
        "ObsStartSucceeded=$ObsStartSucceeded"
    )
}

function Invoke-ObsStartWithTimeout {
    param(
        [string]$ScriptPath,
        [int]$TimeoutMilliseconds = 20000
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        return [pscustomobject]@{
            ExitCode             = 126
            TerminationConfirmed = $true
            Detail               = 'ScriptNotFound'
        }
    }

    $process = $null
    try {
        $powerShellPath = Join-Path $PSHOME 'powershell.exe'
        $quotedScriptPath = '"{0}"' -f $ScriptPath
        $process = Start-Process `
            -FilePath $powerShellPath `
            -ArgumentList @(
                '-NoProfile',
                '-NonInteractive',
                '-ExecutionPolicy',
                'Bypass',
                '-File',
                $quotedScriptPath
            ) `
            -WindowStyle Hidden `
            -PassThru

        if ($process.WaitForExit($TimeoutMilliseconds)) {
            return [pscustomobject]@{
                ExitCode             = $process.ExitCode
                TerminationConfirmed = $true
                Detail               = 'Completed'
            }
        }

        try {
            $process.Kill()
        }
        catch {
            return [pscustomobject]@{
                ExitCode             = 125
                TerminationConfirmed = $false
                Detail               = 'KillFailed'
            }
        }

        if (-not $process.WaitForExit(2000)) {
            return [pscustomobject]@{
                ExitCode             = 125
                TerminationConfirmed = $false
                Detail               = 'TerminationUnconfirmed'
            }
        }

        return [pscustomobject]@{
            ExitCode             = 124
            TerminationConfirmed = $true
            Detail               = 'TimedOut'
        }
    }
    catch {
        $launchErrorMessage = $_.Exception.Message
        $terminationConfirmed = $true
        if ($null -ne $process) {
            try {
                if (-not $process.HasExited) {
                    $process.Kill()
                    $terminationConfirmed = $process.WaitForExit(2000)
                }
            }
            catch {
                $terminationConfirmed = $false
            }
        }
        return [pscustomobject]@{
            ExitCode             = 125
            TerminationConfirmed = $terminationConfirmed
            Detail               = "LaunchFailed: $launchErrorMessage"
        }
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function Convert-ToProcessArgument {
    param([AllowEmptyString()][AllowNull()][string]$Argument)

    if ($null -eq $Argument) {
        return '""'
    }
    if ($Argument.Length -gt 0 -and $Argument -notmatch '[\s"]') {
        return $Argument
    }

    $builder = New-Object System.Text.StringBuilder
    $null = $builder.Append([char]'"')
    $backslashCount = 0

    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq [char]'\') {
            $backslashCount++
            continue
        }

        if ($character -eq [char]'"') {
            if ($backslashCount -gt 0) {
                $null = $builder.Append([char]'\', ($backslashCount * 2))
            }
            $null = $builder.Append([char]'\')
            $null = $builder.Append([char]'"')
            $backslashCount = 0
            continue
        }

        if ($backslashCount -gt 0) {
            $null = $builder.Append([char]'\', $backslashCount)
            $backslashCount = 0
        }
        $null = $builder.Append($character)
    }

    if ($backslashCount -gt 0) {
        $null = $builder.Append([char]'\', ($backslashCount * 2))
    }
    $null = $builder.Append([char]'"')
    return $builder.ToString()
}

function Invoke-NirCmd {
    param(
        [string]$Path,
        [string[]]$Arguments,
        [string]$Description
    )

    $process = $null
    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $Path
        $startInfo.Arguments = (
            @($Arguments | ForEach-Object {
                Convert-ToProcessArgument -Argument $_
            }) -join ' '
        )
        $startInfo.WorkingDirectory = $PSScriptRoot
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw 'Failed to start NirCmd.'
        }

        $process.WaitForExit()
        $exitCode = $process.ExitCode
        if ($exitCode -ne 0) {
            Add-ErrorMessage "$Description failed. NirCmdExitCode=$exitCode"
            return $false
        }
        return $true
    }
    catch {
        Add-ErrorMessage "$Description failed: $($_.Exception.Message)"
        return $false
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

$scriptDirectory = $PSScriptRoot
$obsScriptPath = Join-Path $scriptDirectory 'obs_record_start.ps1'
$nirCmdPath = Join-Path $scriptDirectory 'nircmd.exe'
$legacyMarkerPath = Join-Path $scriptDirectory 'legacy_session.marker'

$caseResult = Convert-CaseNo -Value $CaseNo
$tagResult = Convert-RecordingTag -Value $Tag
$argsValid = if ($caseResult.IsValid -and $tagResult.IsValid) { '1' } else { '0' }

if (-not $caseResult.IsValid) {
    Add-ErrorMessage 'Invalid non-empty CaseNo. Recording will continue without that field.'
}
if (-not $tagResult.IsValid) {
    Add-ErrorMessage 'Invalid non-empty Tag. Recording will continue without that field.'
}

Write-InfoMessage (
    'Raw arguments: CaseNoPresent={0} TagPresent={1}' -f
    [int]$caseResult.IsPresent,
    [int]$tagResult.IsPresent
)
Write-InfoMessage (
    'Normalized arguments: ArgsValid={0} CaseNo={1} Tag={2}' -f
    $argsValid,
    $caseResult.Canonical,
    $tagResult.Normalized
)
Write-InfoMessage "Marker path: `"$legacyMarkerPath`""
Write-InfoMessage "OBS script path: `"$obsScriptPath`""
Write-InfoMessage "NirCmd path: `"$nirCmdPath`""

$null = Remove-CurrentMarker -Path $legacyMarkerPath
$nirCmdAvailable = Test-Path -LiteralPath $nirCmdPath -PathType Leaf
if (-not $nirCmdAvailable) {
    Add-ErrorMessage "NirCmd was not found: `"$nirCmdPath`""
}

try {
    $sessionStartTimeUtc = Get-UtcTimestamp
}
catch {
    $sessionStartTimeUtc = 'UNKNOWN'
    Add-ErrorMessage "Failed to get SessionStartTimeUtc: $($_.Exception.Message)"
}

try {
    $sessionId = [Guid]::NewGuid().ToString()
}
catch {
    $sessionId = 'UNKNOWN'
    Add-ErrorMessage "Failed to create SessionId: $($_.Exception.Message)"
}

$videoStartTimeUtc = 'UNKNOWN'
$logStartTimeUtc = 'UNKNOWN'
$obsStartSucceeded = '0'

Write-InfoMessage "SessionId=$sessionId SessionStartTimeUtc=$sessionStartTimeUtc"
$null = Publish-Marker -Path $legacyMarkerPath -Lines (
    New-LegacyMarkerLines `
        -SessionId $sessionId `
        -ArgsValid $argsValid `
        -CaseNoCanonical $caseResult.Canonical `
        -TagNormalized $tagResult.Normalized `
        -SessionStartTimeUtc $sessionStartTimeUtc `
        -VideoStartTimeUtc $videoStartTimeUtc `
        -LogStartTimeUtc $logStartTimeUtc `
        -ObsStartSucceeded $obsStartSucceeded
)

try {
    $videoStartTimeUtc = Get-UtcTimestamp
}
catch {
    $videoStartTimeUtc = 'UNKNOWN'
    Add-ErrorMessage "Failed to get VideoStartTimeUtc: $($_.Exception.Message)"
}
Write-InfoMessage "VideoStartTimeUtc=$videoStartTimeUtc"
$null = Publish-Marker -Path $legacyMarkerPath -Lines (
    New-LegacyMarkerLines `
        -SessionId $sessionId `
        -ArgsValid $argsValid `
        -CaseNoCanonical $caseResult.Canonical `
        -TagNormalized $tagResult.Normalized `
        -SessionStartTimeUtc $sessionStartTimeUtc `
        -VideoStartTimeUtc $videoStartTimeUtc `
        -LogStartTimeUtc $logStartTimeUtc `
        -ObsStartSucceeded $obsStartSucceeded
)

$obsResult = Invoke-ObsStartWithTimeout -ScriptPath $obsScriptPath
if ($obsResult.ExitCode -eq 0) {
    $obsStartSucceeded = '1'
    Write-InfoMessage 'OBS start result: success.'
}
elseif ($obsResult.ExitCode -eq 124) {
    Add-ErrorMessage 'OBS start timed out after 20 seconds. The child process was terminated.'
}
elseif (-not $obsResult.TerminationConfirmed) {
    Add-ErrorMessage (
        'OBS start process termination could not be confirmed. Remaining GUI operations will be skipped. Detail={0}' -f
        $obsResult.Detail
    )
}
else {
    Add-ErrorMessage (
        'OBS start failed. ExitCode={0} Detail={1}' -f
        $obsResult.ExitCode,
        $obsResult.Detail
    )
}

$null = Publish-Marker -Path $legacyMarkerPath -Lines (
    New-LegacyMarkerLines `
        -SessionId $sessionId `
        -ArgsValid $argsValid `
        -CaseNoCanonical $caseResult.Canonical `
        -TagNormalized $tagResult.Normalized `
        -SessionStartTimeUtc $sessionStartTimeUtc `
        -VideoStartTimeUtc $videoStartTimeUtc `
        -LogStartTimeUtc $logStartTimeUtc `
        -ObsStartSucceeded $obsStartSucceeded
)

if ($obsResult.TerminationConfirmed) {
    Start-Sleep -Seconds 2

    try {
        $logStartTimeUtc = Get-UtcTimestamp
    }
    catch {
        $logStartTimeUtc = 'UNKNOWN'
        Add-ErrorMessage "Failed to get LogStartTimeUtc: $($_.Exception.Message)"
    }
    Write-InfoMessage "LogStartTimeUtc=$logStartTimeUtc"
    $null = Publish-Marker -Path $legacyMarkerPath -Lines (
        New-LegacyMarkerLines `
            -SessionId $sessionId `
            -ArgsValid $argsValid `
            -CaseNoCanonical $caseResult.Canonical `
            -TagNormalized $tagResult.Normalized `
            -SessionStartTimeUtc $sessionStartTimeUtc `
            -VideoStartTimeUtc $videoStartTimeUtc `
            -LogStartTimeUtc $logStartTimeUtc `
            -ObsStartSucceeded $obsStartSucceeded
    )

    if ($nirCmdAvailable) {
        $null = Invoke-NirCmd `
            -Path $nirCmdPath `
            -Arguments @('win', 'activate', 'title', 'Measurement Setup') `
            -Description 'CAN window activation'
        Start-Sleep -Seconds 1
        $null = Invoke-NirCmd `
            -Path $nirCmdPath `
            -Arguments @('sendkeypress', 't') `
            -Description 'CAN log start key'
        Start-Sleep -Seconds 1

        $null = Invoke-NirCmd `
            -Path $nirCmdPath `
            -Arguments @('win', 'activate', 'title', 'COM42 - Tera Term VT') `
            -Description 'COM42 window activation'
        Start-Sleep -Seconds 1
        $null = Invoke-NirCmd `
            -Path $nirCmdPath `
            -Arguments @('sendkeypress', 'alt+f') `
            -Description 'COM42 File menu'
        Start-Sleep -Seconds 1
        $null = Invoke-NirCmd `
            -Path $nirCmdPath `
            -Arguments @('sendkeypress', 'l') `
            -Description 'COM42 log command'
        Start-Sleep -Seconds 1
        $null = Invoke-NirCmd `
            -Path $nirCmdPath `
            -Arguments @('sendkeypress', 'enter') `
            -Description 'COM42 log confirmation'
        Start-Sleep -Seconds 1

        $null = Invoke-NirCmd `
            -Path $nirCmdPath `
            -Arguments @('sendkeypress', 'rwin+printscreen') `
            -Description 'Screenshot'
    }
}

if ($script:HadError) {
    [Console]::Out.WriteLine('[RESULT] START_REC completed with errors. ExitCode=1')
    exit 1
}

if ($script:HadWarning) {
    [Console]::Out.WriteLine('[RESULT] START_REC completed with warnings. ExitCode=0')
}
else {
    [Console]::Out.WriteLine('[RESULT] START_REC completed successfully. ExitCode=0')
}
exit 0
