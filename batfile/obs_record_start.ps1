param(
    [string]$Uri = "ws://127.0.0.1:4455",
    [string]$Password = "TMCTMC",
    [string]$ResultPath = "",
    [int]$ConnectTimeoutMs = 5000,
    [int]$RequestTimeoutMs = 5000,
    [int]$OverallTimeoutMs = 30000,
    [int]$PollIntervalMs = 200
)

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Security

function Get-Base64Sha256([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return [Convert]::ToBase64String($sha.ComputeHash($bytes))
    }
    finally {
        $sha.Dispose()
    }
}

function Get-AuthString([string]$PasswordValue, [string]$Salt, [string]$Challenge) {
    $secret = Get-Base64Sha256 ($PasswordValue + $Salt)
    return Get-Base64Sha256 ($secret + $Challenge)
}

function Get-RemainingTimeout(
    [System.Diagnostics.Stopwatch]$Stopwatch,
    [int]$OverallLimitMs,
    [int]$OperationLimitMs,
    [string]$Operation
) {
    $remaining = $OverallLimitMs - [int]$Stopwatch.ElapsedMilliseconds
    if ($remaining -le 0) {
        throw "TIMEOUT_$Operation"
    }
    return [Math]::Max(1, [Math]::Min($remaining, $OperationLimitMs))
}

function Wait-Task($Task, [int]$TimeoutMs, [string]$Operation) {
    if (-not $Task.Wait($TimeoutMs)) {
        throw "TIMEOUT_$Operation"
    }
    return $Task.GetAwaiter().GetResult()
}

function Receive-Json(
    [System.Net.WebSockets.ClientWebSocket]$WebSocket,
    [int]$TimeoutMs,
    [string]$Operation
) {
    $buffer = New-Object byte[] 65536
    $segment = [ArraySegment[byte]]::new($buffer)
    $stream = New-Object System.IO.MemoryStream
    $timer = [Diagnostics.Stopwatch]::StartNew()

    try {
        do {
            $remaining = $TimeoutMs - [int]$timer.ElapsedMilliseconds
            if ($remaining -le 0) {
                throw "TIMEOUT_$Operation"
            }
            $result = Wait-Task ($WebSocket.ReceiveAsync(
                $segment,
                [Threading.CancellationToken]::None
            )) $remaining $Operation

            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                throw "WEBSOCKET_CLOSED_$Operation"
            }

            $stream.Write($buffer, 0, $result.Count)
        } while (-not $result.EndOfMessage)

        $json = [Text.Encoding]::UTF8.GetString($stream.ToArray())
        return $json | ConvertFrom-Json
    }
    finally {
        $timer.Stop()
        $stream.Dispose()
    }
}

function Send-Json(
    [System.Net.WebSockets.ClientWebSocket]$WebSocket,
    $Object,
    [int]$TimeoutMs,
    [string]$Operation
) {
    $json = $Object | ConvertTo-Json -Depth 10 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $segment = [ArraySegment[byte]]::new($bytes)
    $null = Wait-Task ($WebSocket.SendAsync(
        $segment,
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        [Threading.CancellationToken]::None
    )) $TimeoutMs $Operation
}

function Send-Request(
    [System.Net.WebSockets.ClientWebSocket]$WebSocket,
    [string]$RequestType,
    [int]$TimeoutMs
) {
    $requestId = [guid]::NewGuid().ToString()
    $payload = @{
        op = 6
        d  = @{
            requestType = $RequestType
            requestId   = $requestId
        }
    }

    Send-Json $WebSocket $payload $TimeoutMs ("SEND_" + $RequestType)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        while ($true) {
            $remaining = $TimeoutMs - [int]$timer.ElapsedMilliseconds
            if ($remaining -le 0) {
                throw ("TIMEOUT_RESPONSE_" + $RequestType)
            }
            $response = Receive-Json $WebSocket $remaining ("RECEIVE_" + $RequestType)
            if ($response.op -eq 7 -and $response.d.requestId -eq $requestId) {
                return $response
            }
        }
    }
    finally {
        $timer.Stop()
    }
}

function Connect-Obs(
    [string]$TargetUri,
    [string]$TargetPassword,
    [System.Diagnostics.Stopwatch]$OverallTimer
) {
    $webSocket = [System.Net.WebSockets.ClientWebSocket]::new()
    try {
        $webSocket.Options.AddSubProtocol("obswebsocket.json")
        $connectLimit = Get-RemainingTimeout $OverallTimer $OverallTimeoutMs $ConnectTimeoutMs "CONNECT"
        $null = Wait-Task ($webSocket.ConnectAsync(
            [Uri]$TargetUri,
            [Threading.CancellationToken]::None
        )) $connectLimit "CONNECT"

        $helloLimit = Get-RemainingTimeout $OverallTimer $OverallTimeoutMs $RequestTimeoutMs "HELLO"
        $hello = Receive-Json $webSocket $helloLimit "HELLO"
        if ($hello.op -ne 0) {
            throw "PROTOCOL_HELLO_NOT_RECEIVED"
        }

        $identify = @{
            op = 1
            d  = @{
                rpcVersion = 1
            }
        }
        $authenticationProperty = $hello.d.PSObject.Properties["authentication"]
        if ($null -ne $authenticationProperty -and $null -ne $authenticationProperty.Value) {
            $identify.d.authentication = Get-AuthString `
                $TargetPassword `
                $authenticationProperty.Value.salt `
                $authenticationProperty.Value.challenge
        }

        $identifyLimit = Get-RemainingTimeout $OverallTimer $OverallTimeoutMs $RequestTimeoutMs "IDENTIFY"
        Send-Json $webSocket $identify $identifyLimit "IDENTIFY"
        $identified = Receive-Json $webSocket $identifyLimit "IDENTIFIED"
        if ($identified.op -ne 2) {
            throw "AUTHENTICATION_OR_IDENTIFY_FAILED"
        }

        return $webSocket
    }
    catch {
        $webSocket.Dispose()
        throw
    }
}

function Close-Obs([System.Net.WebSockets.ClientWebSocket]$WebSocket) {
    if ($null -eq $WebSocket) {
        return
    }
    try {
        if ($WebSocket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $null = Wait-Task ($WebSocket.CloseAsync(
                [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                "done",
                [Threading.CancellationToken]::None
            )) 1000 "CLOSE"
        }
    }
    catch {
        # Closing is best effort; the operation result was already decided.
    }
    finally {
        $WebSocket.Dispose()
    }
}

function Get-ReasonText($ErrorRecord) {
    $message = $ErrorRecord.Exception.GetBaseException().Message
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = "UNKNOWN_ERROR"
    }
    return [Regex]::Replace($message, "[`r`n=]", "_")
}

function Write-OperationResult(
    [string]$Path,
    [string]$Outcome,
    [string]$State,
    [string]$Reason,
    [int]$ExitCode,
    [string]$StartedUtc,
    [string]$CompletedUtc
) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        [IO.Directory]::CreateDirectory($directory) | Out-Null
    }

    $temporaryPath = $Path + ".tmp." + $PID
    $lines = @(
        "Version=1",
        "Outcome=$Outcome",
        "State=$State",
        "Reason=$Reason",
        "ExitCode=$ExitCode",
        "StartedTimeUtc=$StartedUtc",
        "CompletedTimeUtc=$CompletedUtc"
    )
    [IO.File]::WriteAllLines($temporaryPath, $lines, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$startedUtc = [DateTime]::UtcNow.ToString("o", [Globalization.CultureInfo]::InvariantCulture)
$outcome = "FAILED"
$state = "UNKNOWN"
$reason = "NOT_STARTED"
$exitCode = 11
$overallTimer = [Diagnostics.Stopwatch]::StartNew()
$startWasRequested = $false

try {
    $obsProcesses = @(
        Get-Process -Name "obs64", "obs32" -ErrorAction SilentlyContinue
    )
    if ($obsProcesses.Count -eq 0) {
        $state = "NOT_RECORDING"
        $reason = "OBS_PROCESS_NOT_FOUND"
        $exitCode = 10
    }
    else {
        $lastError = $null
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            $webSocket = $null
            try {
                $webSocket = Connect-Obs $Uri $Password $overallTimer
                $requestLimit = Get-RemainingTimeout `
                    $overallTimer `
                    $OverallTimeoutMs `
                    $RequestTimeoutMs `
                    "GET_RECORD_STATUS"
                $status = Send-Request $webSocket "GetRecordStatus" $requestLimit
                if (-not $status.d.requestStatus.result) {
                    throw "GET_RECORD_STATUS_REJECTED"
                }

                if ($status.d.responseData.outputActive -eq $true) {
                    $outcome = if ($startWasRequested) { "SUCCEEDED" } else { "DEGRADED" }
                    $state = "RECORDING"
                    $reason = if ($startWasRequested) {
                        "STARTED_AFTER_RETRY"
                    }
                    else {
                        "ALREADY_RECORDING"
                    }
                    $exitCode = if ($startWasRequested) { 0 } else { 2 }
                    break
                }

                $requestLimit = Get-RemainingTimeout `
                    $overallTimer `
                    $OverallTimeoutMs `
                    $RequestTimeoutMs `
                    "START_RECORD"
                $startResponse = Send-Request $webSocket "StartRecord" $requestLimit
                if (-not $startResponse.d.requestStatus.result) {
                    throw "START_RECORD_REJECTED"
                }
                $startWasRequested = $true

                $consecutiveActive = 0
                while ($overallTimer.ElapsedMilliseconds -lt $OverallTimeoutMs) {
                    Start-Sleep -Milliseconds $PollIntervalMs
                    $requestLimit = Get-RemainingTimeout `
                        $overallTimer `
                        $OverallTimeoutMs `
                        $RequestTimeoutMs `
                        "VERIFY_RECORD_STATUS"
                    $verify = Send-Request $webSocket "GetRecordStatus" $requestLimit
                    if (-not $verify.d.requestStatus.result) {
                        throw "VERIFY_RECORD_STATUS_REJECTED"
                    }
                    if ($verify.d.responseData.outputActive -eq $true) {
                        $consecutiveActive++
                        if ($consecutiveActive -ge 2) {
                            $outcome = "SUCCEEDED"
                            $state = "RECORDING"
                            $reason = "STARTED_AND_VERIFIED"
                            $exitCode = 0
                            break
                        }
                    }
                    else {
                        $consecutiveActive = 0
                    }
                }

                if ($outcome -eq "SUCCEEDED") {
                    break
                }
                throw "TIMEOUT_RECORDING_STATE"
            }
            catch {
                $lastError = $_
                if ($attempt -lt 2 -and $overallTimer.ElapsedMilliseconds -lt $OverallTimeoutMs) {
                    Start-Sleep -Milliseconds 500
                }
            }
            finally {
                Close-Obs $webSocket
            }
        }

        if ($outcome -eq "FAILED") {
            if ($null -ne $lastError) {
                $reason = Get-ReasonText $lastError
            }
            $state = "UNKNOWN"
            $exitCode = if ($reason -like "TIMEOUT_*") { 12 } else { 11 }
        }
    }
}
catch {
    $reason = Get-ReasonText $_
    $state = "UNKNOWN"
    $outcome = "FAILED"
    $exitCode = if ($reason -like "TIMEOUT_*") { 12 } else { 11 }
}
finally {
    $overallTimer.Stop()
    $completedUtc = [DateTime]::UtcNow.ToString("o", [Globalization.CultureInfo]::InvariantCulture)
    try {
        Write-OperationResult `
            $ResultPath `
            $outcome `
            $state `
            $reason `
            $exitCode `
            $startedUtc `
            $completedUtc
    }
    catch {
        $exitCode = 20
    }
}

exit $exitCode
