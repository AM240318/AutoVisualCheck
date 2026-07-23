param(
    [string]$Uri = "ws://127.0.0.1:4455",
    [string]$Password = "TMCTMC"
)

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

function Receive-Json([System.Net.WebSockets.ClientWebSocket]$WebSocket) {
    $buffer = New-Object byte[] 65536
    $segment = [ArraySegment[byte]]::new($buffer)
    $stream = New-Object System.IO.MemoryStream

    try {
        do {
            $result = $WebSocket.ReceiveAsync(
                $segment,
                [Threading.CancellationToken]::None
            ).Result

            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                throw "WebSocket closed by server."
            }

            $stream.Write($buffer, 0, $result.Count)
        } while (-not $result.EndOfMessage)

        $json = [Text.Encoding]::UTF8.GetString($stream.ToArray())
        return $json | ConvertFrom-Json
    }
    finally {
        $stream.Dispose()
    }
}

function Send-Json([System.Net.WebSockets.ClientWebSocket]$WebSocket, $Object) {
    $json = $Object | ConvertTo-Json -Depth 10 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $segment = [ArraySegment[byte]]::new($bytes)

    $WebSocket.SendAsync(
        $segment,
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        [Threading.CancellationToken]::None
    ).Wait()
}

function Send-Request(
    [System.Net.WebSockets.ClientWebSocket]$WebSocket,
    [string]$RequestType
) {
    $requestId = [guid]::NewGuid().ToString()
    $payload = @{
        op = 6
        d  = @{
            requestType = $RequestType
            requestId   = $requestId
        }
    }

    Send-Json $WebSocket $payload
    while ($true) {
        $response = Receive-Json $WebSocket
        if ($response.op -eq 7 -and $response.d.requestId -eq $requestId) {
            return $response
        }
    }
}

function Stop-Once([string]$TargetUri, [string]$TargetPassword) {
    $webSocket = [System.Net.WebSockets.ClientWebSocket]::new()

    try {
        $webSocket.Options.AddSubProtocol("obswebsocket.json")
        $webSocket.ConnectAsync(
            $TargetUri,
            [Threading.CancellationToken]::None
        ).Wait()

        $hello = Receive-Json $webSocket
        if ($hello.op -ne 0) {
            throw "Hello(op=0) was not received."
        }

        $identify = @{
            op = 1
            d  = @{
                rpcVersion = 1
            }
        }

        if ($hello.d.authentication) {
            $identify.d.authentication = Get-AuthString `
                $TargetPassword `
                $hello.d.authentication.salt `
                $hello.d.authentication.challenge
        }

        Send-Json $webSocket $identify
        $identified = Receive-Json $webSocket
        if ($identified.op -ne 2) {
            throw "Identified(op=2) was not received."
        }

        $status = Send-Request $webSocket "GetRecordStatus"
        if (-not $status.d.requestStatus.result) {
            throw "GetRecordStatus failed."
        }
        if ($status.d.responseData.outputActive -ne $true) {
            return 0
        }

        $stop = Send-Request $webSocket "StopRecord"
        if (-not $stop.d.requestStatus.result) {
            return 1
        }

        Start-Sleep -Milliseconds 500
        $verify = Send-Request $webSocket "GetRecordStatus"
        if (-not $verify.d.requestStatus.result) {
            return 1
        }
        if ($verify.d.responseData.outputActive -eq $false) {
            return 0
        }
        return 1
    }
    catch {
        return 1
    }
    finally {
        if ($webSocket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $webSocket.CloseAsync(
                [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                "done",
                [Threading.CancellationToken]::None
            ).Wait()
        }
        $webSocket.Dispose()
    }
}

$result = Stop-Once -TargetUri $Uri -TargetPassword $Password
if ($result -ne 0) {
    Start-Sleep -Milliseconds 800
    $result = Stop-Once -TargetUri $Uri -TargetPassword $Password
}

exit $result
