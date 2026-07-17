param(
    [string]$Uri = "ws://127.0.0.1:4455",
    [string]$Password = "TMCTMC"
)

Add-Type -AssemblyName System.Security

function Get-Base64Sha256([string]$text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($text)
        return [Convert]::ToBase64String($sha.ComputeHash($bytes))
    }
    finally {
        $sha.Dispose()
    }
}

function Get-AuthString([string]$password, [string]$salt, [string]$challenge) {
    $secret = Get-Base64Sha256 ($password + $salt)
    return Get-Base64Sha256 ($secret + $challenge)
}

function Receive-Json([System.Net.WebSockets.ClientWebSocket]$ws) {
    $buffer = New-Object byte[] 65536
    $segment = [ArraySegment[byte]]::new($buffer)
    $ms = New-Object System.IO.MemoryStream

    try {
        do {
            $result = $ws.ReceiveAsync($segment, [Threading.CancellationToken]::None).Result

            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                throw "WebSocket closed by server."
            }

            $ms.Write($buffer, 0, $result.Count)
        } while (-not $result.EndOfMessage)

        $json = [Text.Encoding]::UTF8.GetString($ms.ToArray())
        return $json | ConvertFrom-Json
    }
    finally {
        $ms.Dispose()
    }
}

function Send-Json([System.Net.WebSockets.ClientWebSocket]$ws, $obj) {
    $json = $obj | ConvertTo-Json -Depth 10 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $segment = [ArraySegment[byte]]::new($bytes)

    $ws.SendAsync(
        $segment,
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        [Threading.CancellationToken]::None
    ).Wait()
}

function Send-Request([System.Net.WebSockets.ClientWebSocket]$ws, [string]$requestType) {
    $requestId = [guid]::NewGuid().ToString()

    $payload = @{
        op = 6
        d  = @{
            requestType = $requestType
            requestId   = $requestId
        }
    }

    Send-Json $ws $payload

    while ($true) {
        $resp = Receive-Json $ws

        if ($resp.op -eq 7 -and $resp.d.requestId -eq $requestId) {
            return $resp
        }
    }
}

function Stop-Once([string]$Uri, [string]$Password) {
    $ws = [System.Net.WebSockets.ClientWebSocket]::new()

    try {
        $ws.Options.AddSubProtocol("obswebsocket.json")
        $ws.ConnectAsync($Uri, [Threading.CancellationToken]::None).Wait()

        $hello = Receive-Json $ws
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
            $identify.d.authentication = Get-AuthString $Password $hello.d.authentication.salt $hello.d.authentication.challenge
        }

        Send-Json $ws $identify

        $identified = Receive-Json $ws
        if ($identified.op -ne 2) {
            throw "Identified(op=2) was not received."
        }

        $status = Send-Request $ws "GetRecordStatus"
        if (-not $status.d.requestStatus.result) {
            throw "GetRecordStatus failed."
        }

        if ($status.d.responseData.outputActive -ne $true) {
            return 0
        }

        $stop = Send-Request $ws "StopRecord"
        if (-not $stop.d.requestStatus.result) {
            return 1
        }

        Start-Sleep -Milliseconds 500

        $verify = Send-Request $ws "GetRecordStatus"
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
        if ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $ws.CloseAsync(
                [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                "done",
                [Threading.CancellationToken]::None
            ).Wait()
        }
        $ws.Dispose()
    }
}

$result = Stop-Once -Uri $Uri -Password $Password
if ($result -ne 0) {
    Start-Sleep -Milliseconds 800
    $result = Stop-Once -Uri $Uri -Password $Password
}

exit $result