<#
.SYNOPSIS
分割録画フローのCAN、Tera Term、スクリーンショット取得を開始します。

.DESCRIPTION
OBSには触れず、CANログ、Tera Termログ、スクリーンショットの順に開始します。
同じSessionIdを後続のSTART_REC3.ps1が利用できるよう、
開始情報を log_session.marker に記録します。

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\START_REC2.ps1

.OUTPUTS
標準出力へ [INFO]、[WARN]、[ERROR]、[RESULT] で始まるメッセージを出力します。

.NOTES
終了コードは、エラーなしの場合0、1件以上のエラーがあった場合1です。
Windows PowerShell 5.1とnircmd.exeを使用します。
#>
[CmdletBinding()]
param()

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

function Get-UtcTimestamp {
    return [DateTime]::UtcNow.ToString(
        'o',
        [Globalization.CultureInfo]::InvariantCulture
    )
}

function Remove-CurrentMarker {
    param(
        [string]$Path,
        [string]$DisplayName
    )

    try {
        if (Test-Path -LiteralPath $Path -PathType Container) {
            throw "$DisplayName path is a directory: `"$Path`""
        }

        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            Remove-Item -LiteralPath $Path -Force
            if (Test-Path -LiteralPath $Path) {
                throw "$DisplayName remained after removal: `"$Path`""
            }
            Write-InfoMessage "Invalidated $DisplayName`: `"$Path`""
        }
        return $true
    }
    catch {
        Add-ErrorMessage "Failed to invalidate $DisplayName `"$Path`": $($_.Exception.Message)"
        return $false
    }
}

function Publish-LogMarker {
    param(
        [string]$Path,
        [string]$SessionId,
        [string]$SessionStartTimeUtc,
        [string]$LogStartTimeUtc
    )

    $temporaryPath = '{0}.{1}.tmp' -f $Path, [Guid]::NewGuid().ToString('N')
    $lines = @(
        'Version=1'
        "SessionId=$SessionId"
        "SessionStartTimeUtc=$SessionStartTimeUtc"
        "LogStartTimeUtc=$LogStartTimeUtc"
    )

    try {
        if (Test-Path -LiteralPath $Path -PathType Container) {
            throw "Log marker path is a directory: `"$Path`""
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
            throw "Published log marker was not found: `"$Path`""
        }
        if (Test-Path -LiteralPath $temporaryPath) {
            throw "Temporary log marker remained after publication: `"$temporaryPath`""
        }

        Write-InfoMessage "Updated log session marker: `"$Path`""
        return $true
    }
    catch {
        Add-ErrorMessage "Failed to publish log marker `"$Path`": $($_.Exception.Message)"
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
$nirCmdPath = Join-Path $scriptDirectory 'nircmd.exe'
$logMarkerPath = Join-Path $scriptDirectory 'log_session.marker'
$videoMarkerPath = Join-Path $scriptDirectory 'video_session.marker'

$null = Remove-CurrentMarker -Path $videoMarkerPath -DisplayName 'video_session.marker'
$null = Remove-CurrentMarker -Path $logMarkerPath -DisplayName 'log_session.marker'

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

$logStartTimeUtc = 'UNKNOWN'

Write-InfoMessage "Marker path: `"$logMarkerPath`""
Write-InfoMessage "NirCmd path: `"$nirCmdPath`""
Write-InfoMessage "SessionId=$sessionId SessionStartTimeUtc=$sessionStartTimeUtc"
$null = Publish-LogMarker `
    -Path $logMarkerPath `
    -SessionId $sessionId `
    -SessionStartTimeUtc $sessionStartTimeUtc `
    -LogStartTimeUtc $logStartTimeUtc

Start-Sleep -Seconds 2

try {
    $logStartTimeUtc = Get-UtcTimestamp
}
catch {
    $logStartTimeUtc = 'UNKNOWN'
    Add-ErrorMessage "Failed to get LogStartTimeUtc: $($_.Exception.Message)"
}

Write-InfoMessage "LogStartTimeUtc=$logStartTimeUtc"
$null = Publish-LogMarker `
    -Path $logMarkerPath `
    -SessionId $sessionId `
    -SessionStartTimeUtc $sessionStartTimeUtc `
    -LogStartTimeUtc $logStartTimeUtc

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

if ($script:HadError) {
    [Console]::Out.WriteLine('[RESULT] START_REC2 completed with errors. ExitCode=1')
    exit 1
}

if ($script:HadWarning) {
    [Console]::Out.WriteLine('[RESULT] START_REC2 completed with warnings. ExitCode=0')
}
else {
    [Console]::Out.WriteLine('[RESULT] START_REC2 completed successfully. ExitCode=0')
}
exit 0
