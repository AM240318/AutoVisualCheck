<#
.SYNOPSIS
分割録画フローを停止し、CaseNo、Tag、Repeat単位で成果物を保存します。

.DESCRIPTION
CANログ、OBS録画、Tera Termログを順番に停止します。
log_session.marker と video_session.marker を読み、録画、スクリーンショット、
Tera Termログ、CANログをCaseNo/Tag親フォルダ配下へ移動します。
各処理の失敗は記録し、安全に続行できる後続処理を試行します。
OBSの停止を確認できない場合は、未完成ファイルの誤移動を避けるためMP4を移動しません。

.PARAMETER CaseNo
正の整数形式のケース番号です。保存名では最低3桁へゼロ埋めします。

.PARAMETER Tag
英数字、アンダースコア、ハイフンで構成する任意のタグです。大文字化します。

.PARAMETER Repeat
正の整数形式のRepeat番号です。保存名へ #Repeat の形式で追加します。

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\STOP_REC2.ps1 1 WB 2

.EXAMPLE
.\STOP_REC2.ps1 -CaseNo 1 -Tag WB -Repeat 2

.NOTES
終了コード0は成功または警告のみ、1は1件以上のエラーを表します。
Windows PowerShell 5.1、同じフォルダのnircmd.exeとobs_record_stop.ps1を使用します。
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [AllowEmptyString()]
    [string]$CaseNo = '',

    [Parameter(Position = 1)]
    [AllowEmptyString()]
    [string]$Tag = '',

    [Parameter(Position = 2)]
    [AllowEmptyString()]
    [string]$Repeat = ''
)

$ErrorActionPreference = 'Stop'
$script:HadError = $false
$script:HadWarning = $false

function Write-InfoMessage {
    param([string]$Message)
    [Console]::Out.WriteLine(("[INFO] {0}" -f $Message))
}

function Write-WarningMessage {
    param([string]$Message)
    $script:HadWarning = $true
    [Console]::Out.WriteLine(("[WARN] {0}" -f $Message))
}

function Write-ErrorMessage {
    param([string]$Message)
    $script:HadError = $true
    [Console]::Out.WriteLine(("[ERROR] {0}" -f $Message))
}

function Convert-PositiveNumber {
    param(
        [AllowEmptyString()]
        [string]$Value,
        [switch]$IncludeDisplay
    )

    $present = -not [string]::IsNullOrEmpty($Value)
    $valid = -not $present
    $canonical = ''
    $display = ''

    if ($present -and $Value -cmatch '\A[0-9]+\z') {
        $canonical = $Value.TrimStart('0')
        if ($canonical.Length -gt 0) {
            $valid = $true
            if ($IncludeDisplay) {
                $display = $canonical.PadLeft(3, '0')
            }
        }
    }

    [pscustomobject]@{
        Present   = $present
        Valid     = $valid
        Canonical = $canonical
        Display   = $display
    }
}

function Convert-Tag {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    $present = -not [string]::IsNullOrEmpty($Value)
    $valid = -not $present
    $normalized = ''

    if ($present -and $Value -cmatch '\A[A-Za-z0-9_-]+\z') {
        $valid = $true
        $normalized = $Value.ToUpperInvariant()
    }

    [pscustomobject]@{
        Present    = $present
        Valid      = $valid
        Normalized = $normalized
    }
}

function Read-MarkerValues {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Marker file was not found."
    }

    $values = @{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $separator = $line.IndexOf('=')
        if ($separator -lt 1) {
            throw "Marker contains an invalid line."
        }

        $key = $line.Substring(0, $separator)
        if ($values.Keys -ccontains $key) {
            throw "Marker contains a duplicate key: $key"
        }
        $values[$key] = $line.Substring($separator + 1)
    }

    $values
}

function Get-RequiredMarkerValue {
    param(
        [hashtable]$Values,
        [string]$Key
    )

    if (-not ($Values.Keys -ccontains $Key)) {
        throw "Marker key is missing: $Key"
    }
    [string]$Values[$Key]
}

function Convert-UtcMarkerTime {
    param([string]$Value)

    $parsed = [DateTime]::MinValue
    $style = [Globalization.DateTimeStyles]::RoundtripKind
    $culture = [Globalization.CultureInfo]::InvariantCulture
    if (-not [DateTime]::TryParseExact($Value, 'o', $culture, $style, [ref]$parsed)) {
        throw "Marker UTC time is invalid."
    }
    if ($parsed.Kind -ne [DateTimeKind]::Utc) {
        throw "Marker time is not UTC."
    }
    $parsed
}

function Read-LogMarker {
    param([string]$Path)

    $values = Read-MarkerValues -Path $Path
    if ((Get-RequiredMarkerValue -Values $values -Key 'Version') -cne '1') {
        throw "Unsupported log marker version."
    }

    $sessionText = Get-RequiredMarkerValue -Values $values -Key 'SessionId'
    $sessionId = [Guid]::Empty
    if (-not [Guid]::TryParseExact($sessionText, 'D', [ref]$sessionId)) {
        throw "Log marker SessionId is invalid."
    }

    $sessionStartText = Get-RequiredMarkerValue -Values $values -Key 'SessionStartTimeUtc'
    $logStartText = Get-RequiredMarkerValue -Values $values -Key 'LogStartTimeUtc'

    [pscustomobject]@{
        SessionId        = $sessionId
        SessionStartText = $sessionStartText
        SessionStartUtc  = Convert-UtcMarkerTime -Value $sessionStartText
        LogStartText     = $logStartText
        LogStartUtc      = Convert-UtcMarkerTime -Value $logStartText
    }
}

function Read-VideoMarker {
    param([string]$Path)

    $values = Read-MarkerValues -Path $Path
    $version = Get-RequiredMarkerValue -Values $values -Key 'Version'
    if ($version -cne '1' -and $version -cne '2') {
        throw "Unsupported video marker version."
    }

    $sessionText = Get-RequiredMarkerValue -Values $values -Key 'SessionId'
    $sessionId = [Guid]::Empty
    if (-not [Guid]::TryParseExact($sessionText, 'D', [ref]$sessionId)) {
        throw "Video marker SessionId is invalid."
    }

    $argsValidText = Get-RequiredMarkerValue -Values $values -Key 'ArgsValid'
    if ($argsValidText -cne '0' -and $argsValidText -cne '1') {
        throw "Video marker ArgsValid is invalid."
    }

    $caseCanonical = Get-RequiredMarkerValue -Values $values -Key 'CaseNoCanonical'
    $tagNormalized = Get-RequiredMarkerValue -Values $values -Key 'TagNormalized'
    if ($version -ceq '1' -and $caseCanonical -ceq 'UNKNOWN') {
        $caseCanonical = ''
    }
    if ($version -ceq '1' -and $tagNormalized -ceq 'UNKNOWN') {
        $tagNormalized = ''
    }

    if ($caseCanonical.Length -gt 0) {
        if ($caseCanonical -cnotmatch '\A[0-9]+\z') {
            throw "Video marker CaseNo is invalid."
        }
        $caseCanonical = $caseCanonical.TrimStart('0')
        if ($caseCanonical.Length -eq 0) {
            throw "Video marker CaseNo is zero."
        }
    }
    if ($tagNormalized.Length -gt 0 -and $tagNormalized -cnotmatch '\A[A-Z0-9_-]+\z') {
        throw "Video marker Tag is invalid."
    }
    if ($version -ceq '1' -and $argsValidText -ceq '1' -and
        ($caseCanonical.Length -eq 0 -or $tagNormalized.Length -eq 0)) {
        throw "Version 1 video marker has incomplete valid arguments."
    }

    $videoStartText = Get-RequiredMarkerValue -Values $values -Key 'VideoStartTimeUtc'
    $obsStartText = Get-RequiredMarkerValue -Values $values -Key 'ObsStartSucceeded'
    if ($obsStartText -cne '0' -and $obsStartText -cne '1') {
        throw "Video marker ObsStartSucceeded is invalid."
    }

    [pscustomobject]@{
        SessionId         = $sessionId
        ArgsValid         = $argsValidText -ceq '1'
        CaseCanonical     = $caseCanonical
        TagNormalized     = $tagNormalized
        VideoStartText    = $videoStartText
        VideoStartUtc     = Convert-UtcMarkerTime -Value $videoStartText
        ObsStartSucceeded = $obsStartText -ceq '1'
    }
}

function Invoke-NirCmd {
    param(
        [string]$Path,
        [string[]]$Arguments,
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-ErrorMessage "NirCmd is unavailable; skipped $Description."
        return $false
    }

    $process = $null
    try {
        $argumentText = @(
            foreach ($argument in $Arguments) {
                if ($argument -match '[\s"]') {
                    '"{0}"' -f $argument.Replace('"', '\"')
                }
                else {
                    $argument
                }
            }
        ) -join ' '

        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $Path
        $startInfo.Arguments = $argumentText
        $startInfo.WorkingDirectory = $PSScriptRoot
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw "Failed to start NirCmd."
        }
        $process.WaitForExit()

        if ($process.ExitCode -ne 0) {
            Write-ErrorMessage "$Description failed. ExitCode=$($process.ExitCode)"
            return $false
        }
        return $true
    }
    catch {
        Write-ErrorMessage "$Description failed: $($_.Exception.Message)"
        return $false
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function Invoke-ObsHelper {
    param(
        [string]$ScriptPath,
        [int]$TimeoutMilliseconds = 20000
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        return 125
    }

    $powerShellPath = Join-Path -Path $PSHOME -ChildPath 'powershell.exe'
    $quotedScript = '"{0}"' -f $ScriptPath
    $process = $null
    try {
        $process = Start-Process -FilePath $powerShellPath `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $quotedScript) `
            -WindowStyle Hidden -PassThru

        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            try {
                $process.Kill()
                if (-not $process.WaitForExit(2000)) {
                    return 125
                }
            }
            catch {
                return 125
            }
            return 124
        }
        return [int]$process.ExitCode
    }
    catch {
        return 125
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function Get-LatestArchiveCandidate {
    param(
        [string]$ParentFolder,
        [string]$NameComponent
    )

    if ([string]::IsNullOrEmpty($NameComponent)) {
        $pattern = '\A[0-9]{8}_[0-9]{6}\z'
    }
    else {
        $pattern = '\A{0}_[0-9]{{8}}_[0-9]{{6}}\z' -f [Regex]::Escape($NameComponent)
    }

    @(Get-ChildItem -LiteralPath $ParentFolder -Directory |
        Where-Object { $_.Name -notmatch '_OLD_' -and $_.Name -match $pattern } |
        Sort-Object -Property Name -Descending |
        Select-Object -First 1)
}

function Archive-PreviousChild {
    param(
        [string]$ParentFolder,
        [string]$NameComponent,
        [string]$StopDateTime
    )

    try {
        $candidate = Get-LatestArchiveCandidate -ParentFolder $ParentFolder -NameComponent $NameComponent
        if ($candidate.Count -eq 0) {
            Write-InfoMessage "No previous matching child folder requires archiving."
            return $true
        }

        $archiveBase = '{0}_OLD_{1}' -f $candidate[0].Name, $StopDateTime
        $archiveName = $archiveBase
        $index = 1
        while (Test-Path -LiteralPath (Join-Path -Path $ParentFolder -ChildPath $archiveName)) {
            $archiveName = '{0}_{1}' -f $archiveBase, $index.ToString('00')
            $index++
        }

        Rename-Item -LiteralPath $candidate[0].FullName -NewName $archiveName
        Write-InfoMessage ('Archived OLD folder: "{0}"' -f
            (Join-Path -Path $ParentFolder -ChildPath $archiveName))
        return $true
    }
    catch {
        Write-ErrorMessage "Failed to archive the latest previous matching child folder: $($_.Exception.Message)"
        return $false
    }
}

function Move-SelectedFiles {
    param(
        [string]$SourceKind,
        [string]$SourceDirectory,
        [string]$Extension,
        [string]$TimeProperty,
        [ValidateSet('MARKER', 'LATEST')]
        [string]$SelectionMode,
        [Nullable[DateTime]]$StartTimeUtc,
        [bool]$AllMarkerMatches,
        [string]$DestinationFolder,
        [string]$FilePrefix
    )

    try {
        $files = @(Get-ChildItem -LiteralPath $SourceDirectory -File -Filter ("*.{0}" -f $Extension))
        if ($SelectionMode -ceq 'MARKER') {
            if ($null -eq $StartTimeUtc) {
                throw "Selection start time is unavailable."
            }
            $files = @($files |
                Where-Object { $_.$TimeProperty -ge $StartTimeUtc } |
                Sort-Object -Property $TimeProperty -Descending)
            if ($SourceKind -ceq 'MP4' -and $files.Count -gt 1) {
                Write-WarningMessage "Multiple MP4 candidates found: $($files.Count). The latest one will be used."
            }
            if (-not $AllMarkerMatches -and $files.Count -gt 1) {
                $files = @($files[0])
            }
        }
        else {
            $files = @($files |
                Sort-Object -Property $TimeProperty -Descending |
                Select-Object -First 1)
        }

        if ($files.Count -eq 0) {
            Write-WarningMessage "No $SourceKind file matched the selection rule."
            return
        }

        foreach ($file in $files) {
            if ($SourceKind -ceq 'MP4') {
                $targetName = '{0}.mp4' -f $FilePrefix
            }
            else {
                $targetName = '{0}_{1}' -f $FilePrefix, $file.Name
            }
            $target = Join-Path -Path $DestinationFolder -ChildPath $targetName
            Write-InfoMessage ('Selected source file: "{0}"' -f $file.FullName)
            if (Test-Path -LiteralPath $target) {
                Write-ErrorMessage ('Destination file already exists: "{0}"' -f $target)
                continue
            }

            try {
                Move-Item -LiteralPath $file.FullName -Destination $target
                Write-InfoMessage ('Renamed destination file: "{0}"' -f $target)
            }
            catch {
                Write-ErrorMessage "Failed to move selected $SourceKind file: $($_.Exception.Message)"
            }
        }
    }
    catch {
        Write-ErrorMessage "Failed to enumerate or select $SourceKind files: $($_.Exception.Message)"
    }
}

function Remove-SessionMarker {
    param(
        [string]$Path,
        [string]$Name
    )

    if (Test-Path -LiteralPath $Path -PathType Container) {
        Write-WarningMessage ('Marker path is a directory and was not deleted: "{0}"' -f $Path)
        return
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-InfoMessage "$Name is already absent."
        return
    }

    try {
        Remove-Item -LiteralPath $Path -Force
        Write-InfoMessage ('Deleted marker: "{0}"' -f $Path)
    }
    catch {
        Write-WarningMessage "Failed to delete ${Name}: $($_.Exception.Message)"
    }
}

$userDataRoot = $env:USERPROFILE
if ([string]::IsNullOrEmpty($userDataRoot)) {
    $userDataRoot = 'C:\Users\TMC'
}

$baseDirectory = Join-Path -Path $userDataRoot -ChildPath 'Desktop\LogZips'
$captureDirectory = Join-Path -Path $userDataRoot -ChildPath 'Videos\Captures'
$screenshotDirectory = Join-Path -Path $userDataRoot -ChildPath 'Pictures\Screenshots'
$teraTermLogDirectory = 'C:\teraterm-5.2\log'
$canLogDirectory = Join-Path -Path $baseDirectory -ChildPath 'CANtemp'
$obsScript = Join-Path -Path $PSScriptRoot -ChildPath 'obs_record_stop.ps1'
$nirCmd = Join-Path -Path $PSScriptRoot -ChildPath 'nircmd.exe'
$logMarkerPath = Join-Path -Path $PSScriptRoot -ChildPath 'log_session.marker'
$videoMarkerPath = Join-Path -Path $PSScriptRoot -ChildPath 'video_session.marker'

$caseInfo = Convert-PositiveNumber -Value $CaseNo -IncludeDisplay
$tagInfo = Convert-Tag -Value $Tag
$repeatInfo = Convert-PositiveNumber -Value $Repeat
$argumentsValid = $caseInfo.Valid -and $tagInfo.Valid -and $repeatInfo.Valid

if (-not $argumentsValid) {
    Write-ErrorMessage "Invalid non-empty CaseNo, Tag, or Repeat."
}

Write-InfoMessage ("Raw arguments: CaseNoPresent={0} TagPresent={1} RepeatPresent={2}" -f
    [int]$caseInfo.Present, [int]$tagInfo.Present, [int]$repeatInfo.Present)
Write-InfoMessage ("Normalized arguments: ArgsValid={0} CaseNo={1} Tag={2} Repeat={3}" -f
    [int]$argumentsValid, $caseInfo.Canonical, $tagInfo.Normalized, $repeatInfo.Canonical)
Write-InfoMessage ('OBS script path: "{0}"' -f $obsScript)
Write-InfoMessage ('NirCmd path: "{0}"' -f $nirCmd)

if (-not (Test-Path -LiteralPath $obsScript -PathType Leaf)) {
    Write-ErrorMessage ('OBS stop script was not found: "{0}"' -f $obsScript)
}
if (-not (Test-Path -LiteralPath $nirCmd -PathType Leaf)) {
    Write-ErrorMessage ('NirCmd was not found: "{0}"' -f $nirCmd)
}

$logMarker = $null
$videoMarker = $null
$logMarkerValid = $false
$videoMarkerValid = $false

if (Test-Path -LiteralPath $logMarkerPath -PathType Leaf) {
    try {
        $logMarker = Read-LogMarker -Path $logMarkerPath
        $logMarkerValid = $true
        Write-InfoMessage ('Log marker: "{0}" Status=valid SessionId={1}' -f
            $logMarkerPath, $logMarker.SessionId)
        Write-InfoMessage ("SessionStartTimeUtc={0} LogStartTimeUtc={1}" -f
            $logMarker.SessionStartText, $logMarker.LogStartText)
    }
    catch {
        Write-ErrorMessage ('Log marker: "{0}" Status=invalid. {1}' -f
            $logMarkerPath, $_.Exception.Message)
    }
}
else {
    Write-ErrorMessage ('Log marker: "{0}" Status=missing' -f $logMarkerPath)
}

if (Test-Path -LiteralPath $videoMarkerPath -PathType Leaf) {
    try {
        $videoMarker = Read-VideoMarker -Path $videoMarkerPath
        $videoMarkerValid = $true
        Write-InfoMessage ('Video marker: "{0}" Status=valid SessionId={1}' -f
            $videoMarkerPath, $videoMarker.SessionId)
        Write-InfoMessage ("VideoStartTimeUtc={0} ObsStartSucceeded={1}" -f
            $videoMarker.VideoStartText, [int]$videoMarker.ObsStartSucceeded)
    }
    catch {
        Write-ErrorMessage ('Video marker: "{0}" Status=invalid. {1}' -f
            $videoMarkerPath, $_.Exception.Message)
    }
}
else {
    Write-ErrorMessage ('Video marker: "{0}" Status=missing' -f $videoMarkerPath)
}

$logSelectionMode = if ($logMarkerValid) { 'MARKER' } else { 'LATEST' }
$videoSelectionMode = if ($videoMarkerValid) { 'MARKER' } else { 'LATEST' }
$namingMode = 'NORMAL'
$sessionMismatch = $false
$caseMismatch = $false
$skipMp4 = $false

if ($logMarkerValid -and $videoMarkerValid -and
    $logMarker.SessionId -ne $videoMarker.SessionId) {
    $sessionMismatch = $true
    $logSelectionMode = 'LATEST'
    $videoSelectionMode = 'LATEST'
    $namingMode = 'FALLBACK'
    if (-not $videoMarker.ObsStartSucceeded) {
        $skipMp4 = $true
        Write-ErrorMessage "OBS start was not successful; MP4 will not be moved."
    }
    Write-ErrorMessage "Log and video SessionId values do not match; both marker timelines are discarded."
}
else {
    if ($videoMarkerValid -and -not $videoMarker.ObsStartSucceeded) {
        $skipMp4 = $true
        Write-ErrorMessage "OBS start was not successful; MP4 will not be moved."
    }
    if ($videoMarkerValid -and -not $videoMarker.ArgsValid) {
        Write-ErrorMessage "Video marker contained an invalid non-empty CaseNo or Tag; valid matching fields will still be used."
    }
    if ($videoMarkerValid) {
        if (($caseInfo.Canonical -cne $videoMarker.CaseCanonical) -or
            ($tagInfo.Normalized -cne $videoMarker.TagNormalized)) {
            $caseMismatch = $true
            $namingMode = 'FALLBACK'
            Write-ErrorMessage "START and STOP CaseNo/Tag do not match; CaseNo and Tag will be omitted from names."
        }
        else {
            Write-InfoMessage "STOP arguments and available video marker arguments match."
        }
    }
    else {
        Write-InfoMessage "Video marker argument comparison is unavailable; normalized STOP arguments will be used."
    }
}

$stopDateTime = [DateTime]::Now.ToString(
    'yyyyMMdd_HHmmss',
    [Globalization.CultureInfo]::InvariantCulture
)
Write-InfoMessage "STOP local date and time: $stopDateTime"

Write-InfoMessage "Stopping CAN log."
Start-Sleep -Seconds 2
[void](Invoke-NirCmd -Path $nirCmd `
    -Arguments @('win', 'activate', 'title', 'Measurement Setup') `
    -Description 'Measurement Setup activation')
Start-Sleep -Seconds 2
[void](Invoke-NirCmd -Path $nirCmd -Arguments @('sendkeypress', 't') `
    -Description 'CAN stop key')
Start-Sleep -Seconds 2

Write-InfoMessage "Stopping OBS recording."
$obsExitCode = Invoke-ObsHelper -ScriptPath $obsScript
if ($obsExitCode -eq 0) {
    Write-InfoMessage "OBS stop result: success."
}
elseif ($obsExitCode -eq 124) {
    Write-ErrorMessage "OBS stop timed out after 20 seconds."
    $skipMp4 = $true
    Write-WarningMessage "MP4 processing will be skipped because OBS stop was not confirmed."
}
else {
    Write-ErrorMessage "OBS stop failed. ExitCode=$obsExitCode"
    $skipMp4 = $true
    Write-WarningMessage "MP4 processing will be skipped because OBS stop was not confirmed."
}

Write-InfoMessage "Stopping COM42 Tera Term log."
[void](Invoke-NirCmd -Path $nirCmd `
    -Arguments @('win', 'activate', 'title', 'COM42 - Tera Term VT') `
    -Description 'COM42 Tera Term activation')
Start-Sleep -Seconds 1
[void](Invoke-NirCmd -Path $nirCmd -Arguments @('sendkeypress', 'alt+f') `
    -Description 'COM42 Alt+F')
Start-Sleep -Seconds 1
[void](Invoke-NirCmd -Path $nirCmd -Arguments @('sendkeypress', 'q') `
    -Description 'COM42 stop command')
Start-Sleep -Seconds 5

$parentName = ''
if ($namingMode -ceq 'NORMAL') {
    if ($caseInfo.Valid -and $caseInfo.Display.Length -gt 0) {
        $parentName = "Case$($caseInfo.Display)"
    }
    if ($tagInfo.Valid -and $tagInfo.Normalized.Length -gt 0) {
        if ($parentName.Length -gt 0) {
            $parentName = '{0}_{1}' -f $parentName, $tagInfo.Normalized
        }
        else {
            $parentName = $tagInfo.Normalized
        }
    }
}

$nameComponent = $parentName
if ($repeatInfo.Valid -and $repeatInfo.Canonical.Length -gt 0) {
    if ($nameComponent.Length -gt 0) {
        $nameComponent = '{0}#{1}' -f $nameComponent, $repeatInfo.Canonical
    }
    else {
        $nameComponent = "Repeat$($repeatInfo.Canonical)"
    }
}

$parentFolder = $baseDirectory
if ($parentName.Length -gt 0) {
    $parentFolder = Join-Path -Path $baseDirectory -ChildPath $parentName
}
$filePrefix = if ($nameComponent.Length -gt 0) { $nameComponent } else { $stopDateTime }
$runFolderName = if ($nameComponent.Length -gt 0) {
    '{0}_{1}' -f $nameComponent, $stopDateTime
}
else {
    $stopDateTime
}

$parentReady = $false
try {
    if (Test-Path -LiteralPath $parentFolder -PathType Container) {
        Write-InfoMessage ('Reusing parent folder: "{0}"' -f $parentFolder)
    }
    else {
        New-Item -ItemType Directory -Path $parentFolder -Force | Out-Null
        Write-WarningMessage ('Parent folder was missing and was created by STOP_REC2.ps1: "{0}"' -f
            $parentFolder)
    }
    $parentReady = $true
}
catch {
    Write-ErrorMessage "Failed to prepare parent folder: $($_.Exception.Message)"
}

$archiveReady = $false
if ($parentReady) {
    $archiveReady = Archive-PreviousChild -ParentFolder $parentFolder `
        -NameComponent $nameComponent -StopDateTime $stopDateTime
}

$destinationFolder = Join-Path -Path $parentFolder -ChildPath $runFolderName
$destinationReady = $false
if ($archiveReady) {
    if (Test-Path -LiteralPath $destinationFolder) {
        Write-ErrorMessage ('Destination child already exists; file movement will be skipped: "{0}"' -f
            $destinationFolder)
    }
    else {
        try {
            New-Item -ItemType Directory -Path $destinationFolder | Out-Null
            $destinationReady = $true
            Write-InfoMessage ('Destination child folder: "{0}"' -f $destinationFolder)
        }
        catch {
            Write-ErrorMessage "Failed to create destination child folder: $($_.Exception.Message)"
        }
    }
}

if ($destinationReady) {
    if ($skipMp4) {
        Write-WarningMessage "MP4 processing skipped because OBS start or stop was not confirmed."
    }
    else {
        $videoStart = if ($videoMarkerValid -and $videoSelectionMode -ceq 'MARKER') {
            [Nullable[DateTime]]$videoMarker.VideoStartUtc
        }
        else {
            [Nullable[DateTime]]$null
        }
        Move-SelectedFiles -SourceKind 'MP4' -SourceDirectory $captureDirectory `
            -Extension 'mp4' -TimeProperty 'CreationTimeUtc' `
            -SelectionMode $videoSelectionMode -StartTimeUtc $videoStart `
            -AllMarkerMatches $false -DestinationFolder $destinationFolder `
            -FilePrefix $filePrefix
    }

    $sessionStart = if ($logMarkerValid -and $logSelectionMode -ceq 'MARKER') {
        [Nullable[DateTime]]$logMarker.SessionStartUtc
    }
    else {
        [Nullable[DateTime]]$null
    }
    $logStart = if ($logMarkerValid -and $logSelectionMode -ceq 'MARKER') {
        [Nullable[DateTime]]$logMarker.LogStartUtc
    }
    else {
        [Nullable[DateTime]]$null
    }

    Move-SelectedFiles -SourceKind 'PNG' -SourceDirectory $screenshotDirectory `
        -Extension 'png' -TimeProperty 'CreationTimeUtc' `
        -SelectionMode $logSelectionMode -StartTimeUtc $sessionStart `
        -AllMarkerMatches $true -DestinationFolder $destinationFolder `
        -FilePrefix $filePrefix
    Move-SelectedFiles -SourceKind 'LOG' -SourceDirectory $teraTermLogDirectory `
        -Extension 'log' -TimeProperty 'LastWriteTimeUtc' `
        -SelectionMode $logSelectionMode -StartTimeUtc $logStart `
        -AllMarkerMatches $true -DestinationFolder $destinationFolder `
        -FilePrefix $filePrefix
    Move-SelectedFiles -SourceKind 'ASC' -SourceDirectory $canLogDirectory `
        -Extension 'asc' -TimeProperty 'LastWriteTimeUtc' `
        -SelectionMode $logSelectionMode -StartTimeUtc $logStart `
        -AllMarkerMatches $true -DestinationFolder $destinationFolder `
        -FilePrefix $filePrefix
}

Remove-SessionMarker -Path $logMarkerPath -Name 'log_session.marker'
Remove-SessionMarker -Path $videoMarkerPath -Name 'video_session.marker'

[Console]::Out.WriteLine(("[RESULT] NamingMode={0} VideoSelection={1} LogSelection={2}" -f
    $namingMode, $videoSelectionMode, $logSelectionMode))
[Console]::Out.WriteLine(("[RESULT] SessionMismatch={0} CaseMismatch={1} DestinationReady={2}" -f
    [int]$sessionMismatch, [int]$caseMismatch, [int]$destinationReady))

if ($script:HadError) {
    [Console]::Out.WriteLine("[RESULT] STOP_REC2 completed with errors. ExitCode=1")
    exit 1
}
if ($script:HadWarning) {
    [Console]::Out.WriteLine("[RESULT] STOP_REC2 completed with warnings. ExitCode=0")
}
else {
    [Console]::Out.WriteLine("[RESULT] STOP_REC2 completed successfully. ExitCode=0")
}
exit 0
