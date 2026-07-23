<#
.SYNOPSIS
分割録画フローのOBS録画を開始します。

.DESCRIPTION
CaseNoとTagに対応する保存先の親フォルダを準備し、
START_REC2.ps1が作成したlog_session.markerからSessionIdを継承して
OBS録画を開始します。開始結果はvideo_session.markerへ記録します。

.PARAMETER CaseNo
ケース番号です。正の数字を指定します。省略できます。

.PARAMETER Tag
録画識別用のTagです。英数字、アンダースコア、ハイフンを指定できます。
大文字へ正規化して使用します。省略できます。

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\START_REC3.ps1 1 WB

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\START_REC3.ps1 -CaseNo 1 -Tag WB

.OUTPUTS
標準出力へ [INFO]、[WARN]、[ERROR]、[RESULT] で始まるメッセージを出力します。

.NOTES
終了コードは、エラーなしの場合0、1件以上のエラーがあった場合1です。
Windows PowerShell 5.1とobs_record_start.ps1を使用します。
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
            Display   = ''
        }
    }

    if ($Value -notmatch '\A[0-9]+\z') {
        return [pscustomobject]@{
            IsPresent = $true
            IsValid   = $false
            Canonical = ''
            Display   = ''
        }
    }

    $canonical = $Value.TrimStart('0')
    if ($canonical.Length -eq 0) {
        return [pscustomobject]@{
            IsPresent = $true
            IsValid   = $false
            Canonical = ''
            Display   = ''
        }
    }

    return [pscustomobject]@{
        IsPresent = $true
        IsValid   = $true
        Canonical = $canonical
        Display   = $canonical.PadLeft(3, '0')
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
            throw "Video marker path is a directory: `"$Path`""
        }

        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            Remove-Item -LiteralPath $Path -Force
            if (Test-Path -LiteralPath $Path) {
                throw "Video marker remained after removal: `"$Path`""
            }
            Write-InfoMessage "Invalidated video session marker: `"$Path`""
        }
        return $true
    }
    catch {
        Add-ErrorMessage "Failed to invalidate video marker `"$Path`": $($_.Exception.Message)"
        return $false
    }
}

function Publish-VideoMarker {
    param(
        [string]$Path,
        [string]$SessionId,
        [string]$ArgsValid,
        [string]$CaseNoCanonical,
        [string]$TagNormalized,
        [string]$VideoStartTimeUtc,
        [string]$ObsStartSucceeded
    )

    $temporaryPath = '{0}.{1}.tmp' -f $Path, [Guid]::NewGuid().ToString('N')
    $lines = @(
        'Version=2'
        "SessionId=$SessionId"
        "ArgsValid=$ArgsValid"
        "CaseNoCanonical=$CaseNoCanonical"
        "TagNormalized=$TagNormalized"
        "VideoStartTimeUtc=$VideoStartTimeUtc"
        "ObsStartSucceeded=$ObsStartSucceeded"
    )

    try {
        if (Test-Path -LiteralPath $Path -PathType Container) {
            throw "Video marker path is a directory: `"$Path`""
        }

        $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllLines($temporaryPath, $lines, $utf8WithoutBom)

        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [IO.File]::Replace($temporaryPath, $Path, $null)
        }
        else {
            [IO.File]::Move($temporaryPath, $Path)
        }

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "Published video marker was not found: `"$Path`""
        }
        if (Test-Path -LiteralPath $temporaryPath) {
            throw "Temporary video marker remained after publication: `"$temporaryPath`""
        }

        Write-InfoMessage "Updated video session marker: `"$Path`""
        return $true
    }
    catch {
        Add-ErrorMessage "Failed to publish video marker `"$Path`": $($_.Exception.Message)"
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

function Get-LogSession {
    param([string]$Path)

    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw 'Log marker was not found.'
        }

        $requiredKeys = @(
            'Version',
            'SessionId',
            'SessionStartTimeUtc',
            'LogStartTimeUtc'
        )
        $values = @{}

        foreach ($line in [IO.File]::ReadAllLines($Path)) {
            $separatorIndex = $line.IndexOf('=')
            if ($separatorIndex -lt 1) {
                throw 'Log marker contains an invalid line.'
            }

            $key = $line.Substring(0, $separatorIndex)
            if ($requiredKeys -ccontains $key) {
                if ($values.ContainsKey($key)) {
                    throw "Log marker contains duplicate key: $key"
                }
                $values[$key] = $line.Substring($separatorIndex + 1)
            }
        }

        foreach ($key in $requiredKeys) {
            if (-not $values.ContainsKey($key)) {
                throw "Log marker is missing key: $key"
            }
        }

        if ($values['Version'] -cne '1') {
            throw 'Unsupported log marker version.'
        }

        [Guid]$sessionGuid = [Guid]::Empty
        if (-not [Guid]::TryParseExact($values['SessionId'], 'D', [ref]$sessionGuid)) {
            throw 'Log marker SessionId is invalid.'
        }

        [DateTime]$sessionStart = [DateTime]::MinValue
        if (-not [DateTime]::TryParseExact(
            $values['SessionStartTimeUtc'],
            'o',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$sessionStart
        )) {
            throw 'Log marker SessionStartTimeUtc is invalid.'
        }
        if ($sessionStart.Kind -ne [DateTimeKind]::Utc) {
            throw 'Log marker SessionStartTimeUtc is not UTC.'
        }

        [DateTime]$logStart = [DateTime]::MinValue
        if (-not [DateTime]::TryParseExact(
            $values['LogStartTimeUtc'],
            'o',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$logStart
        )) {
            throw 'Log marker LogStartTimeUtc is invalid.'
        }
        if ($logStart.Kind -ne [DateTimeKind]::Utc) {
            throw 'Log marker LogStartTimeUtc is not UTC.'
        }

        return [pscustomobject]@{
            IsValid  = $true
            SessionId = $sessionGuid.ToString()
            Detail   = 'Valid'
        }
    }
    catch {
        return [pscustomobject]@{
            IsValid  = $false
            SessionId = ''
            Detail   = $_.Exception.Message
        }
    }
}

function Ensure-ParentFolder {
    param(
        [string]$SaveRoot,
        [pscustomobject]$CaseResult,
        [pscustomobject]$TagResult
    )

    $nameComponents = New-Object System.Collections.Generic.List[string]
    if ($CaseResult.IsValid -and $CaseResult.Display.Length -gt 0) {
        $nameComponents.Add("Case$($CaseResult.Display)")
    }
    if ($TagResult.IsValid -and $TagResult.Normalized.Length -gt 0) {
        $nameComponents.Add($TagResult.Normalized)
    }

    $parentDirectory = $SaveRoot
    if ($nameComponents.Count -gt 0) {
        $parentDirectory = Join-Path $SaveRoot ($nameComponents -join '_')
    }

    try {
        if (Test-Path -LiteralPath $parentDirectory -PathType Leaf) {
            throw "Parent folder path is a file: `"$parentDirectory`""
        }

        if (Test-Path -LiteralPath $parentDirectory -PathType Container) {
            Write-InfoMessage "Reusing parent folder: `"$parentDirectory`""
        }
        else {
            $null = New-Item -ItemType Directory -Path $parentDirectory -Force
            if (-not (Test-Path -LiteralPath $parentDirectory -PathType Container)) {
                throw "Parent folder was not found after creation: `"$parentDirectory`""
            }
            Write-InfoMessage "Created parent folder: `"$parentDirectory`""
        }
        return $true
    }
    catch {
        Add-ErrorMessage "Failed to prepare parent folder `"$parentDirectory`": $($_.Exception.Message)"
        return $false
    }
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

$scriptDirectory = $PSScriptRoot
$obsScriptPath = Join-Path $scriptDirectory 'obs_record_start.ps1'
$logMarkerPath = Join-Path $scriptDirectory 'log_session.marker'
$videoMarkerPath = Join-Path $scriptDirectory 'video_session.marker'

$userDataRoot = $env:USERPROFILE
if ([string]::IsNullOrWhiteSpace($userDataRoot)) {
    $userDataRoot = 'C:\Users\TMC'
}
$saveRoot = Join-Path (Join-Path $userDataRoot 'Desktop') 'LogZips'

$caseResult = Convert-CaseNo -Value $CaseNo
$tagResult = Convert-RecordingTag -Value $Tag
$argsValid = if ($caseResult.IsValid -and $tagResult.IsValid) { '1' } else { '0' }

if (-not $caseResult.IsValid) {
    Add-ErrorMessage 'Invalid non-empty CaseNo. OBS start will continue without that field.'
}
if (-not $tagResult.IsValid) {
    Add-ErrorMessage 'Invalid non-empty Tag. OBS start will continue without that field.'
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

$null = Remove-CurrentMarker -Path $videoMarkerPath
$null = Ensure-ParentFolder `
    -SaveRoot $saveRoot `
    -CaseResult $caseResult `
    -TagResult $tagResult

$logSession = Get-LogSession -Path $logMarkerPath
if ($logSession.IsValid) {
    $sessionId = $logSession.SessionId
    Write-InfoMessage "Inherited SessionId from `"$logMarkerPath`": $sessionId"
}
else {
    Add-ErrorMessage "Valid SessionId could not be read from `"$logMarkerPath`". Detail=$($logSession.Detail)"
    try {
        $sessionId = [Guid]::NewGuid().ToString()
        Write-InfoMessage "Created fallback SessionId: $sessionId"
    }
    catch {
        $sessionId = 'UNKNOWN'
        Add-ErrorMessage "Failed to create fallback SessionId: $($_.Exception.Message)"
    }
}

try {
    $videoStartTimeUtc = Get-UtcTimestamp
}
catch {
    $videoStartTimeUtc = 'UNKNOWN'
    Add-ErrorMessage "Failed to get VideoStartTimeUtc: $($_.Exception.Message)"
}

$obsStartSucceeded = '0'
Write-InfoMessage "Video marker path: `"$videoMarkerPath`""
Write-InfoMessage "OBS script path: `"$obsScriptPath`""
Write-InfoMessage "SessionId=$sessionId VideoStartTimeUtc=$videoStartTimeUtc"
$null = Publish-VideoMarker `
    -Path $videoMarkerPath `
    -SessionId $sessionId `
    -ArgsValid $argsValid `
    -CaseNoCanonical $caseResult.Canonical `
    -TagNormalized $tagResult.Normalized `
    -VideoStartTimeUtc $videoStartTimeUtc `
    -ObsStartSucceeded $obsStartSucceeded

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
        'OBS start process termination could not be confirmed. Detail={0}' -f
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

$null = Publish-VideoMarker `
    -Path $videoMarkerPath `
    -SessionId $sessionId `
    -ArgsValid $argsValid `
    -CaseNoCanonical $caseResult.Canonical `
    -TagNormalized $tagResult.Normalized `
    -VideoStartTimeUtc $videoStartTimeUtc `
    -ObsStartSucceeded $obsStartSucceeded

if ($script:HadError) {
    [Console]::Out.WriteLine('[RESULT] START_REC3 completed with errors. ExitCode=1')
    exit 1
}

if ($script:HadWarning) {
    [Console]::Out.WriteLine('[RESULT] START_REC3 completed with warnings. ExitCode=0')
}
else {
    [Console]::Out.WriteLine('[RESULT] START_REC3 completed successfully. ExitCode=0')
}
exit 0
