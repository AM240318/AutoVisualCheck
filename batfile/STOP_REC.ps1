<#
.SYNOPSIS
CANログ、OBS録画、Tera Termログを停止し、録画成果物をCase/Tag別に保存します。

.DESCRIPTION
既存のSTOP_REC.batと同じ停止順（CAN、OBS、Tera Term、保存）を
PowerShellとして実装したスクリプトです。

legacy_session.markerのVersion 1/2を読み取り、開始時刻以降に生成された
MP4、PNG、LOG、ASCを選択します。マーカーが欠落または不正な場合は、
種類ごとの最新ファイル1件へフォールバックします。
OBSの停止を確認できない場合は、未完成ファイルの誤移動を避けるためMP4を移動しません。

保存先は次の形式です。
  LogZips\Case001_WB\Case001_WB_yyyyMMdd_HHmmss

MP4はCase001_WB.mp4へ変更し、その他のファイルにはCase001_WB_を
接頭辞として付けます。既存BAT、マーカー、OBS補助スクリプトは変更しません。

.PARAMETER CaseNo
正の数字で指定するケース番号です。保存名では最低3桁にゼロ埋めします。
省略した場合は、有効な開始マーカーの値を使用します。

.PARAMETER Tag
英数字、アンダースコア、ハイフンで指定するタグです。
保存名では大文字化します。省略した場合は、有効な開始マーカーの値を使用します。

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\STOP_REC.ps1 1 WB

位置引数でCaseNo=1、Tag=WBを指定します。

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\STOP_REC.ps1 -CaseNo 1 -Tag WB

名前付き引数で同じ値を指定します。

.OUTPUTS
標準出力へ[INFO]、[WARN]、[ERROR]、[RESULT]形式で処理結果を出力します。

.NOTES
終了コード:
  0: 成功、または警告のみ
  1: 1件以上のエラーあり

依存関係:
  同じフォルダのnircmd.exe、obs_record_stop.ps1
  Windows PowerShell 5.1

OBS、CANoe、Tera Termおよび保存元フォルダへアクセスするため、
実機環境でのみ本体を実行してください。
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

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'RESULT')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    [Console]::Out.WriteLine('[{0}] {1}' -f $Level, $Message)
}

function Add-RecordedError {
    param([Parameter(Mandatory = $true)][string]$Message)

    $script:HadError = $true
    Write-Log -Level ERROR -Message $Message
}

function Add-RecordedWarning {
    param([Parameter(Mandatory = $true)][string]$Message)

    $script:HadWarning = $true
    Write-Log -Level WARN -Message $Message
}

function Convert-CaseNo {
    param([AllowNull()][string]$Value)

    $present = -not [string]::IsNullOrEmpty($Value)
    if (-not $present) {
        return [pscustomobject]@{
            Present   = $false
            Valid     = $true
            Canonical = ''
            Display   = ''
        }
    }

    if ($Value -notmatch '\A[0-9]+\z') {
        return [pscustomobject]@{
            Present   = $true
            Valid     = $false
            Canonical = ''
            Display   = ''
        }
    }

    $canonical = $Value.TrimStart('0')
    if ([string]::IsNullOrEmpty($canonical)) {
        return [pscustomobject]@{
            Present   = $true
            Valid     = $false
            Canonical = ''
            Display   = ''
        }
    }

    return [pscustomobject]@{
        Present   = $true
        Valid     = $true
        Canonical = $canonical
        Display   = $canonical.PadLeft(3, '0')
    }
}

function Convert-Tag {
    param([AllowNull()][string]$Value)

    $present = -not [string]::IsNullOrEmpty($Value)
    if (-not $present) {
        return [pscustomobject]@{
            Present    = $false
            Valid      = $true
            Normalized = ''
        }
    }

    if ($Value -notmatch '\A[A-Za-z0-9_-]+\z') {
        return [pscustomobject]@{
            Present    = $true
            Valid      = $false
            Normalized = ''
        }
    }

    return [pscustomobject]@{
        Present    = $true
        Valid      = $true
        Normalized = $Value.ToUpperInvariant()
    }
}

function Convert-UtcMarkerTime {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    [DateTime]$parsed = [DateTime]::MinValue
    $parsedOk = [DateTime]::TryParseExact(
        $Value,
        'o',
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$parsed
    )

    if (-not $parsedOk -or $parsed.Kind -ne [DateTimeKind]::Utc) {
        throw ('Invalid UTC marker field: {0}' -f $FieldName)
    }

    return $parsed
}

function Read-LegacyMarker {
    param([Parameter(Mandatory = $true)][string]$Path)

    $invalidResult = [pscustomobject]@{
        Present             = $false
        Valid               = $false
        Error               = ''
        Version             = ''
        SessionId           = ''
        ArgsValid           = ''
        CaseNoCanonical     = ''
        TagNormalized       = ''
        SessionStartTimeUtc = [DateTime]::MinValue
        VideoStartTimeUtc   = [DateTime]::MinValue
        LogStartTimeUtc     = [DateTime]::MinValue
        ObsStartSucceeded   = ''
    }

    if (Test-Path -LiteralPath $Path -PathType Container) {
        $invalidResult.Present = $true
        $invalidResult.Error = 'Marker path is a directory.'
        return $invalidResult
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $invalidResult.Error = 'Marker file is missing.'
        return $invalidResult
    }

    $invalidResult.Present = $true

    try {
        $requiredKeys = @(
            'Version',
            'SessionId',
            'ArgsValid',
            'CaseNoCanonical',
            'TagNormalized',
            'SessionStartTimeUtc',
            'VideoStartTimeUtc',
            'LogStartTimeUtc',
            'ObsStartSucceeded'
        )
        $values = @{}

        foreach ($line in [IO.File]::ReadAllLines($Path)) {
            $separatorIndex = $line.IndexOf('=')
            if ($separatorIndex -lt 1) {
                throw 'Marker contains a malformed line.'
            }

            $key = $line.Substring(0, $separatorIndex)
            if ($requiredKeys -ccontains $key) {
                if ($values.Keys -ccontains $key) {
                    throw ('Marker contains a duplicate field: {0}' -f $key)
                }
                $values[$key] = $line.Substring($separatorIndex + 1)
            }
        }

        foreach ($requiredKey in $requiredKeys) {
            if (-not ($values.Keys -ccontains $requiredKey)) {
                throw ('Marker field is missing: {0}' -f $requiredKey)
            }
        }

        $version = $values['Version']
        if ($version -cne '1' -and $version -cne '2') {
            throw 'Marker Version must be 1 or 2.'
        }

        [Guid]$sessionGuid = [Guid]::Empty
        if (-not [Guid]::TryParseExact($values['SessionId'], 'D', [ref]$sessionGuid)) {
            throw 'Marker SessionId is invalid.'
        }

        $argsValid = $values['ArgsValid']
        if ($argsValid -cne '0' -and $argsValid -cne '1') {
            throw 'Marker ArgsValid is invalid.'
        }

        $markerCase = $values['CaseNoCanonical']
        if ($version -ceq '1' -and $markerCase -ceq 'UNKNOWN') {
            $markerCase = ''
        }
        if (-not [string]::IsNullOrEmpty($markerCase)) {
            if ($markerCase -notmatch '\A[0-9]+\z') {
                throw 'Marker CaseNoCanonical is invalid.'
            }
            $markerCase = $markerCase.TrimStart('0')
            if ([string]::IsNullOrEmpty($markerCase)) {
                throw 'Marker CaseNoCanonical must be positive.'
            }
        }

        $markerTag = $values['TagNormalized']
        if ($version -ceq '1' -and $markerTag -ceq 'UNKNOWN') {
            $markerTag = ''
        }
        if (
            -not [string]::IsNullOrEmpty($markerTag) -and
            $markerTag -notmatch '\A[A-Z0-9_-]+\z'
        ) {
            throw 'Marker TagNormalized is invalid.'
        }

        if (
            $version -ceq '1' -and
            $argsValid -ceq '1' -and
            (
                [string]::IsNullOrEmpty($markerCase) -or
                [string]::IsNullOrEmpty($markerTag)
            )
        ) {
            throw 'Version 1 marker with ArgsValid=1 requires CaseNo and Tag.'
        }

        $sessionStartUtc = Convert-UtcMarkerTime `
            -Value $values['SessionStartTimeUtc'] `
            -FieldName 'SessionStartTimeUtc'
        $videoStartUtc = Convert-UtcMarkerTime `
            -Value $values['VideoStartTimeUtc'] `
            -FieldName 'VideoStartTimeUtc'
        $logStartUtc = Convert-UtcMarkerTime `
            -Value $values['LogStartTimeUtc'] `
            -FieldName 'LogStartTimeUtc'

        $obsStartSucceeded = $values['ObsStartSucceeded']
        if ($obsStartSucceeded -cne '0' -and $obsStartSucceeded -cne '1') {
            throw 'Marker ObsStartSucceeded is invalid.'
        }

        return [pscustomobject]@{
            Present             = $true
            Valid               = $true
            Error               = ''
            Version             = $version
            SessionId           = $sessionGuid.ToString()
            ArgsValid           = $argsValid
            CaseNoCanonical     = $markerCase
            TagNormalized       = $markerTag
            SessionStartTimeUtc = $sessionStartUtc
            VideoStartTimeUtc   = $videoStartUtc
            LogStartTimeUtc     = $logStartUtc
            ObsStartSucceeded   = $obsStartSucceeded
        }
    }
    catch {
        $invalidResult.Error = $_.Exception.Message
        return $invalidResult
    }
}

function Invoke-NirCmd {
    param(
        [Parameter(Mandatory = $true)][string]$NirCmdPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    if (-not (Test-Path -LiteralPath $NirCmdPath -PathType Leaf)) {
        Add-RecordedError ('{0} was skipped because NirCmd was not found.' -f $Operation)
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
        $startInfo.FileName = $NirCmdPath
        $startInfo.Arguments = $argumentText
        $startInfo.WorkingDirectory = $PSScriptRoot
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw 'Failed to start NirCmd.'
        }
        $process.WaitForExit()

        if ($process.ExitCode -ne 0) {
            Add-RecordedError (
                '{0} failed. NirCmdExitCode={1}' -f $Operation, $process.ExitCode
            )
            return $false
        }

        Write-Log -Level INFO -Message ('{0} completed.' -f $Operation)
        return $true
    }
    catch {
        Add-RecordedError (
            '{0} failed: {1}' -f $Operation, $_.Exception.Message
        )
        return $false
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function Stop-CanLog {
    param([Parameter(Mandatory = $true)][string]$NirCmdPath)

    Write-Log -Level INFO -Message 'Stopping CAN log.'
    Start-Sleep -Seconds 2
    Invoke-NirCmd `
        -NirCmdPath $NirCmdPath `
        -Arguments @('win', 'activate', 'title', 'Measurement Setup') `
        -Operation 'CAN window activation' | Out-Null
    Start-Sleep -Seconds 2
    Invoke-NirCmd `
        -NirCmdPath $NirCmdPath `
        -Arguments @('sendkeypress', 't') `
        -Operation 'CAN stop key' | Out-Null
    Start-Sleep -Seconds 2
}

function Stop-ObsRecording {
    param([Parameter(Mandatory = $true)][string]$ObsScriptPath)

    Write-Log -Level INFO -Message 'Stopping OBS recording.'
    if (-not (Test-Path -LiteralPath $ObsScriptPath -PathType Leaf)) {
        Add-RecordedError ('OBS stop script was not found: "{0}"' -f $ObsScriptPath)
        return $false
    }

    $powerShellPath = Join-Path -Path $PSHOME -ChildPath 'powershell.exe'
    if (-not (Test-Path -LiteralPath $powerShellPath -PathType Leaf)) {
        $powerShellPath = 'powershell.exe'
    }

    $process = $null
    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $powerShellPath
        $startInfo.Arguments = (
            '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f
            $ObsScriptPath.Replace('"', '\"')
        )
        $startInfo.WorkingDirectory = $PSScriptRoot
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw 'Failed to start the child PowerShell process.'
        }

        if (-not $process.WaitForExit(20000)) {
            $terminationConfirmed = $false
            try {
                $process.Kill()
                $terminationConfirmed = $process.WaitForExit(2000)
            }
            catch {
                $terminationConfirmed = $false
            }

            if ($terminationConfirmed) {
                Add-RecordedError 'OBS stop timed out after 20 seconds; the child process was terminated.'
            }
            else {
                Add-RecordedError 'OBS stop timed out and child-process termination could not be confirmed.'
            }
            return $false
        }

        if ($process.ExitCode -ne 0) {
            Add-RecordedError (
                'OBS stop failed. ExitCode={0}' -f $process.ExitCode
            )
            return $false
        }

        Write-Log -Level INFO -Message 'OBS stop completed.'
        return $true
    }
    catch {
        Add-RecordedError ('OBS stop failed: {0}' -f $_.Exception.Message)
        return $false
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function Stop-TeraTermLog {
    param([Parameter(Mandatory = $true)][string]$NirCmdPath)

    Write-Log -Level INFO -Message 'Stopping COM42 Tera Term log.'
    Invoke-NirCmd `
        -NirCmdPath $NirCmdPath `
        -Arguments @('win', 'activate', 'title', 'COM42 - Tera Term VT') `
        -Operation 'COM42 window activation' | Out-Null
    Start-Sleep -Seconds 1
    Invoke-NirCmd `
        -NirCmdPath $NirCmdPath `
        -Arguments @('sendkeypress', 'alt+f') `
        -Operation 'COM42 Alt+F' | Out-Null
    Start-Sleep -Seconds 1
    Invoke-NirCmd `
        -NirCmdPath $NirCmdPath `
        -Arguments @('sendkeypress', 'q') `
        -Operation 'COM42 stop command' | Out-Null
    Start-Sleep -Seconds 5
}

function Initialize-Destination {
    param(
        [Parameter(Mandatory = $true)][string]$BaseDirectory,
        [AllowEmptyString()][string]$NameComponent,
        [Parameter(Mandatory = $true)][string]$StopTimestamp
    )

    $parentDirectory = $BaseDirectory
    if (-not [string]::IsNullOrEmpty($NameComponent)) {
        $parentDirectory = Join-Path -Path $BaseDirectory -ChildPath $NameComponent
    }

    try {
        if (Test-Path -LiteralPath $parentDirectory -PathType Leaf) {
            throw 'The parent destination path is a file.'
        }
        if (-not (Test-Path -LiteralPath $parentDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $parentDirectory -Force -ErrorAction Stop |
                Out-Null
        }
        Write-Log -Level INFO -Message (
            'Destination parent folder: "{0}"' -f $parentDirectory
        )
    }
    catch {
        Add-RecordedError (
            'Failed to prepare destination parent folder "{0}": {1}' -f
            $parentDirectory, $_.Exception.Message
        )
        return $null
    }

    if (-not [string]::IsNullOrEmpty($NameComponent)) {
        try {
            $childPattern = '\A{0}_[0-9]{{8}}_[0-9]{{6}}\z' -f
                [Regex]::Escape($NameComponent)
            $previous = @(
                Get-ChildItem -LiteralPath $parentDirectory -Directory -ErrorAction Stop |
                    Where-Object {
                        $_.Name -notmatch '_OLD_' -and
                        $_.Name -match $childPattern
                    } |
                    Sort-Object -Property Name -Descending |
                    Select-Object -First 1
            )

            if ($previous.Count -gt 0) {
                $archiveBase = '{0}_OLD_{1}' -f $previous[0].Name, $StopTimestamp
                $archiveName = $archiveBase
                $archiveIndex = 1
                while (
                    Test-Path -LiteralPath (
                        Join-Path -Path $parentDirectory -ChildPath $archiveName
                    )
                ) {
                    $archiveName = '{0}_{1}' -f (
                        $archiveBase,
                        $archiveIndex.ToString(
                            '00',
                            [Globalization.CultureInfo]::InvariantCulture
                        )
                    )
                    $archiveIndex++
                }

                Rename-Item `
                    -LiteralPath $previous[0].FullName `
                    -NewName $archiveName `
                    -ErrorAction Stop
                Write-Log -Level INFO -Message (
                    'Archived previous child folder: "{0}"' -f
                    (Join-Path -Path $parentDirectory -ChildPath $archiveName)
                )
            }
            else {
                Write-Log -Level INFO -Message 'No previous matching child folder requires archiving.'
            }
        }
        catch {
            Add-RecordedError (
                'Failed to archive the latest previous child folder: {0}' -f
                $_.Exception.Message
            )
            return $null
        }
    }
    else {
        Write-Log -Level INFO -Message 'Previous-folder archiving was skipped because CaseNo/Tag naming is unavailable.'
    }

    $childName = $StopTimestamp
    if (-not [string]::IsNullOrEmpty($NameComponent)) {
        $childName = '{0}_{1}' -f $NameComponent, $StopTimestamp
    }
    $destination = Join-Path -Path $parentDirectory -ChildPath $childName

    try {
        if (Test-Path -LiteralPath $destination) {
            throw 'The destination child folder already exists.'
        }
        New-Item -ItemType Directory -Path $destination -ErrorAction Stop |
            Out-Null
        Write-Log -Level INFO -Message (
            'Destination folder: "{0}"' -f $destination
        )
        return $destination
    }
    catch {
        Add-RecordedError (
            'Failed to create destination folder "{0}": {1}' -f
            $destination, $_.Exception.Message
        )
        return $null
    }
}

function Move-SelectedFiles {
    param(
        [Parameter(Mandatory = $true)][string]$Kind,
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$Extension,
        [Parameter(Mandatory = $true)][string]$TimeProperty,
        [Parameter(Mandatory = $true)][ValidateSet('MARKER', 'LATEST')]
        [string]$SelectionMode,
        [DateTime]$StartUtc = [DateTime]::MinValue,
        [Parameter(Mandatory = $true)][bool]$AllWhenMarker,
        [Parameter(Mandatory = $true)][string]$DestinationDirectory,
        [Parameter(Mandatory = $true)][string]$FilePrefix
    )

    try {
        $files = @(
            Get-ChildItem `
                -LiteralPath $SourceDirectory `
                -File `
                -Filter ('*.{0}' -f $Extension) `
                -ErrorAction Stop
        )

        if ($SelectionMode -ceq 'MARKER') {
            $files = @(
                $files |
                    Where-Object { $_.$TimeProperty -ge $StartUtc } |
                    Sort-Object -Property $TimeProperty -Descending
            )

            if ($Kind -ceq 'MP4' -and $files.Count -gt 1) {
                Add-RecordedWarning (
                    'Multiple MP4 candidates were found ({0}); the latest one will be used.' -f
                    $files.Count
                )
            }

            if (-not $AllWhenMarker -and $files.Count -gt 1) {
                $files = @($files[0])
            }
        }
        else {
            $files = @(
                $files |
                    Sort-Object -Property $TimeProperty -Descending |
                    Select-Object -First 1
            )
        }

        if ($files.Count -eq 0) {
            Add-RecordedWarning (
                'No {0} file matched the {1} selection rule in "{2}".' -f
                $Kind, $SelectionMode, $SourceDirectory
            )
            return
        }

        foreach ($file in $files) {
            $targetName = if ($Kind -ceq 'MP4') {
                '{0}.mp4' -f $FilePrefix
            }
            else {
                '{0}_{1}' -f $FilePrefix, $file.Name
            }
            $targetPath = Join-Path `
                -Path $DestinationDirectory `
                -ChildPath $targetName

            Write-Log -Level INFO -Message (
                'Selected {0} source file: "{1}"' -f $Kind, $file.FullName
            )
            if (Test-Path -LiteralPath $targetPath) {
                Add-RecordedError (
                    'Destination file already exists; source was not moved: "{0}"' -f
                    $targetPath
                )
                continue
            }

            try {
                Move-Item `
                    -LiteralPath $file.FullName `
                    -Destination $targetPath `
                    -ErrorAction Stop
                Write-Log -Level INFO -Message (
                    'Moved {0} file to: "{1}"' -f $Kind, $targetPath
                )
            }
            catch {
                Add-RecordedError (
                    'Failed to move {0} file "{1}": {2}' -f
                    $Kind, $file.FullName, $_.Exception.Message
                )
            }
        }
    }
    catch {
        Add-RecordedError (
            'Failed to enumerate or select {0} files in "{1}": {2}' -f
            $Kind, $SourceDirectory, $_.Exception.Message
        )
    }
}

function Remove-LegacyMarker {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Container) {
        Add-RecordedWarning (
            'Marker path is a directory and was not deleted: "{0}"' -f $Path
        )
        return
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Log -Level INFO -Message 'Legacy session marker is already absent.'
        return
    }

    try {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        Write-Log -Level INFO -Message (
            'Deleted legacy session marker: "{0}"' -f $Path
        )
    }
    catch {
        Add-RecordedWarning (
            'Failed to delete legacy session marker "{0}": {1}' -f
            $Path, $_.Exception.Message
        )
    }
}

$userDataRoot = $env:USERPROFILE
if ([string]::IsNullOrWhiteSpace($userDataRoot)) {
    $userDataRoot = 'C:\Users\TMC'
}

$baseDirectory = Join-Path -Path $userDataRoot -ChildPath 'Desktop\LogZips'
$captureDirectory = Join-Path -Path $userDataRoot -ChildPath 'Videos\Captures'
$screenshotDirectory = Join-Path -Path $userDataRoot -ChildPath 'Pictures\Screenshots'
$teraTermLogDirectory = 'C:\teraterm-5.2\log'
$canLogDirectory = Join-Path -Path $baseDirectory -ChildPath 'CANtemp'
$obsScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'obs_record_stop.ps1'
$legacyMarkerPath = Join-Path -Path $PSScriptRoot -ChildPath 'legacy_session.marker'
$nirCmdPath = Join-Path -Path $PSScriptRoot -ChildPath 'nircmd.exe'

$selectionMode = 'LATEST'
$namingMode = 'NORMAL'
$destinationReady = $false
$destinationDirectory = ''
$filePrefix = ''
$nameComponent = ''
$stopTimestamp = [DateTime]::Now.ToString(
    'yyyyMMdd_HHmmss',
    [Globalization.CultureInfo]::InvariantCulture
)
$marker = $null
$skipMp4 = $false

try {
    $caseInfo = Convert-CaseNo -Value $CaseNo
    $tagInfo = Convert-Tag -Value $Tag

    if ($caseInfo.Present -and -not $caseInfo.Valid) {
        Add-RecordedError 'CaseNo is invalid; marker or safe naming fallback will be used.'
    }
    if ($tagInfo.Present -and -not $tagInfo.Valid) {
        Add-RecordedError 'Tag is invalid; marker or safe naming fallback will be used.'
    }

    Write-Log -Level INFO -Message (
        'Raw arguments: CaseNoPresent={0} TagPresent={1}' -f
        [int]$caseInfo.Present, [int]$tagInfo.Present
    )

    if (-not (Test-Path -LiteralPath $nirCmdPath -PathType Leaf)) {
        Add-RecordedError ('NirCmd was not found: "{0}"' -f $nirCmdPath)
    }
    if (-not (Test-Path -LiteralPath $obsScriptPath -PathType Leaf)) {
        Add-RecordedError ('OBS stop script was not found: "{0}"' -f $obsScriptPath)
    }
    Write-Log -Level INFO -Message ('OBS script path: "{0}"' -f $obsScriptPath)
    Write-Log -Level INFO -Message ('NirCmd path: "{0}"' -f $nirCmdPath)

    $marker = Read-LegacyMarker -Path $legacyMarkerPath
    if ($marker.Valid) {
        $selectionMode = 'MARKER'
        Write-Log -Level INFO -Message (
            'Marker path: "{0}" Status=valid Version={1}' -f
            $legacyMarkerPath, $marker.Version
        )
        Write-Log -Level INFO -Message (
            'SessionId={0} SessionStartTimeUtc={1:o}' -f
            $marker.SessionId, $marker.SessionStartTimeUtc
        )
        Write-Log -Level INFO -Message (
            'VideoStartTimeUtc={0:o} LogStartTimeUtc={1:o}' -f
            $marker.VideoStartTimeUtc, $marker.LogStartTimeUtc
        )
    }
    else {
        $markerStatus = if ($marker.Present) { 'invalid' } else { 'missing' }
        Add-RecordedError (
            'Marker path: "{0}" Status={1}. {2}' -f
            $legacyMarkerPath, $markerStatus, $marker.Error
        )
        Write-Log -Level INFO -Message 'Latest-one fallback selection will be used.'
    }

    $effectiveCaseCanonical = $caseInfo.Canonical
    $effectiveCaseDisplay = $caseInfo.Display
    $effectiveCaseValid = $caseInfo.Valid
    $effectiveTag = $tagInfo.Normalized
    $effectiveTagValid = $tagInfo.Valid

    if ($marker.Valid) {
        if (
            (-not $caseInfo.Present -or -not $caseInfo.Valid) -and
            -not [string]::IsNullOrEmpty($marker.CaseNoCanonical)
        ) {
            $effectiveCaseCanonical = $marker.CaseNoCanonical
            $effectiveCaseDisplay = $marker.CaseNoCanonical.PadLeft(3, '0')
            $effectiveCaseValid = $true
            Write-Log -Level INFO -Message 'CaseNo was obtained from the START marker.'
        }
        if (
            (-not $tagInfo.Present -or -not $tagInfo.Valid) -and
            -not [string]::IsNullOrEmpty($marker.TagNormalized)
        ) {
            $effectiveTag = $marker.TagNormalized
            $effectiveTagValid = $true
            Write-Log -Level INFO -Message 'Tag was obtained from the START marker.'
        }

        if ($marker.ArgsValid -cne '1') {
            Add-RecordedError 'START marker reports invalid CaseNo or Tag arguments.'
        }
        if ($marker.ObsStartSucceeded -ceq '0') {
            Add-RecordedError 'START marker reports that OBS recording did not start; MP4 will not be moved.'
            $skipMp4 = $true
        }

        $caseMismatch = (
            -not [string]::IsNullOrEmpty($effectiveCaseCanonical) -and
            -not [string]::IsNullOrEmpty($marker.CaseNoCanonical) -and
            $effectiveCaseCanonical -cne $marker.CaseNoCanonical
        )
        $tagMismatch = (
            -not [string]::IsNullOrEmpty($effectiveTag) -and
            -not [string]::IsNullOrEmpty($marker.TagNormalized) -and
            $effectiveTag -cne $marker.TagNormalized
        )
        if ($caseMismatch -or $tagMismatch) {
            Add-RecordedError 'START and STOP CaseNo/Tag do not match; date-time fallback naming will be used.'
            $namingMode = 'DATETIME'
        }
        else {
            Write-Log -Level INFO -Message 'START and STOP CaseNo/Tag are compatible.'
        }
    }

    Write-Log -Level INFO -Message (
        'Effective arguments: CaseNo={0} Tag={1}' -f
        $effectiveCaseCanonical, $effectiveTag
    )
    Write-Log -Level INFO -Message (
        'STOP local date and time: {0}' -f $stopTimestamp
    )

    if ($namingMode -ceq 'NORMAL') {
        if (
            $effectiveCaseValid -and
            -not [string]::IsNullOrEmpty($effectiveCaseDisplay)
        ) {
            $nameComponent = 'Case{0}' -f $effectiveCaseDisplay
        }
        if (
            $effectiveTagValid -and
            -not [string]::IsNullOrEmpty($effectiveTag)
        ) {
            if ([string]::IsNullOrEmpty($nameComponent)) {
                $nameComponent = $effectiveTag
            }
            else {
                $nameComponent = '{0}_{1}' -f $nameComponent, $effectiveTag
            }
        }
    }
    if ([string]::IsNullOrEmpty($nameComponent)) {
        $filePrefix = $stopTimestamp
    }
    else {
        $filePrefix = $nameComponent
    }

    Stop-CanLog -NirCmdPath $nirCmdPath
    $obsStopSucceeded = Stop-ObsRecording -ObsScriptPath $obsScriptPath
    if (-not $obsStopSucceeded) {
        $skipMp4 = $true
        Add-RecordedWarning 'MP4 processing will be skipped because OBS stop was not confirmed.'
    }
    Stop-TeraTermLog -NirCmdPath $nirCmdPath

    $destinationDirectory = Initialize-Destination `
        -BaseDirectory $baseDirectory `
        -NameComponent $nameComponent `
        -StopTimestamp $stopTimestamp

    if (-not [string]::IsNullOrEmpty($destinationDirectory)) {
        $destinationReady = $true

        if ($skipMp4) {
            Add-RecordedWarning 'MP4 processing was skipped because OBS start or stop was not confirmed.'
        }
        else {
            Move-SelectedFiles `
                -Kind 'MP4' `
                -SourceDirectory $captureDirectory `
                -Extension 'mp4' `
                -TimeProperty 'CreationTimeUtc' `
                -SelectionMode $selectionMode `
                -StartUtc $(if ($marker.Valid) {
                    $marker.VideoStartTimeUtc
                }
                else {
                    [DateTime]::MinValue
                }) `
                -AllWhenMarker $false `
                -DestinationDirectory $destinationDirectory `
                -FilePrefix $filePrefix
        }

        Move-SelectedFiles `
            -Kind 'PNG' `
            -SourceDirectory $screenshotDirectory `
            -Extension 'png' `
            -TimeProperty 'CreationTimeUtc' `
            -SelectionMode $selectionMode `
            -StartUtc $(if ($marker.Valid) {
                $marker.SessionStartTimeUtc
            }
            else {
                [DateTime]::MinValue
            }) `
            -AllWhenMarker $true `
            -DestinationDirectory $destinationDirectory `
            -FilePrefix $filePrefix

        Move-SelectedFiles `
            -Kind 'LOG' `
            -SourceDirectory $teraTermLogDirectory `
            -Extension 'log' `
            -TimeProperty 'LastWriteTimeUtc' `
            -SelectionMode $selectionMode `
            -StartUtc $(if ($marker.Valid) {
                $marker.LogStartTimeUtc
            }
            else {
                [DateTime]::MinValue
            }) `
            -AllWhenMarker $true `
            -DestinationDirectory $destinationDirectory `
            -FilePrefix $filePrefix

        Move-SelectedFiles `
            -Kind 'ASC' `
            -SourceDirectory $canLogDirectory `
            -Extension 'asc' `
            -TimeProperty 'LastWriteTimeUtc' `
            -SelectionMode $selectionMode `
            -StartUtc $(if ($marker.Valid) {
                $marker.LogStartTimeUtc
            }
            else {
                [DateTime]::MinValue
            }) `
            -AllWhenMarker $true `
            -DestinationDirectory $destinationDirectory `
            -FilePrefix $filePrefix
    }
}
catch {
    Add-RecordedError ('Unexpected STOP_REC failure: {0}' -f $_.Exception.Message)
}
finally {
    Remove-LegacyMarker -Path $legacyMarkerPath
}

Write-Log -Level RESULT -Message (
    'NamingMode={0} SelectionMode={1} DestinationReady={2}' -f
    $namingMode, $selectionMode, [int]$destinationReady
)

if ($script:HadError) {
    Write-Log -Level RESULT -Message 'STOP_REC completed with errors. ExitCode=1'
    exit 1
}

if ($script:HadWarning) {
    Write-Log -Level RESULT -Message 'STOP_REC completed with warnings. ExitCode=0'
}
else {
    Write-Log -Level RESULT -Message 'STOP_REC completed successfully. ExitCode=0'
}
exit 0
