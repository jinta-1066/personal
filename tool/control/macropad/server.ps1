# Windowsの標準機能を使って直接キーボードを操作するプログラム
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Keyboard {
    [DllImport("user32.dll", SetLastError = true)]
    static extern void keybd_event(byte bVk, byte bScan, int dwFlags, int dwExtraInfo);
    public const int KEYEVENTF_KEYDOWN = 0x0000;
    public const int KEYEVENTF_KEYUP = 0x0002;
    public static void PressKeys(byte[] keys) {
        foreach(byte key in keys) {
            keybd_event(key, 0, KEYEVENTF_KEYDOWN, 0);
        }
        System.Threading.Thread.Sleep(50);
        for(int i = keys.Length - 1; i >= 0; i--) {
            keybd_event(keys[i], 0, KEYEVENTF_KEYUP, 0);
        }
    }
}
"@

$KeyMap = @{
    'LeftControl' = 0xA2; 'LeftShift' = 0xA0; 'LeftAlt' = 0xA4; 'LeftSuper' = 0x5B;
    'Return' = 0x0D; 'Space' = 0x20; 'Backspace' = 0x08; 'Tab' = 0x09; 'Escape' = 0x1B;
    'Up' = 0x26; 'Down' = 0x28; 'Left' = 0x25; 'Right' = 0x27; 'Delete' = 0x2E; 'Insert' = 0x2D;
    'Minus' = 0xBD; 'Equal' = 0xBB; 'LeftBracket' = 0xDB; 'RightBracket' = 0xDD;
    'Backslash' = 0xDC; 'Semicolon' = 0xBA; 'Quote' = 0xDE; 'Comma' = 0xBC; 'Period' = 0xBE; 'Slash' = 0xBF; 'Grave' = 0xC0
}
[char[]]"ABCDEFGHIJKLMNOPQRSTUVWXYZ" | ForEach-Object { $KeyMap[$_.ToString()] = [byte]$_ }
0..9 | ForEach-Object { $KeyMap["Num$_"] = [byte](48 + $_) }
1..12 | ForEach-Object { $KeyMap["F$_"] = [byte](111 + $_) }

$port = 3000
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port)
try {
    $listener.Start()
} catch {
    Write-Host "Port $port is busy." -ForegroundColor Red
    Pause
    exit
}

$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback" } | Select-Object -First 1).IPAddress
Write-Host "========================================="
Write-Host "🚀 Web Macro Pad Server is running!"
Write-Host "📱 Access: http://$($ip):$($port)/"
Write-Host "========================================="

while ($true) {
    if (!$listener.Pending()) {
        Start-Sleep -Milliseconds 100
        continue
    }
    
    $client = $listener.AcceptTcpClient()
    $stream = $client.GetStream()
    $reader = New-Object System.IO.StreamReader($stream)
    $writer = New-Object System.IO.StreamWriter($stream)
    
    try {
        $requestLine = $reader.ReadLine()
        if ([string]::IsNullOrEmpty($requestLine)) { $client.Close(); continue }
        
        $parts = $requestLine -split ' '
        $method = $parts[0]
        $path = $parts[1]
        
        $contentLength = 0
        while ($true) {
            $line = $reader.ReadLine()
            if ([string]::IsNullOrEmpty($line)) { break }
            if ($line.StartsWith("Content-Length:")) {
                $contentLength = [int]($line -replace "Content-Length:\s*", "")
            }
        }
        
        # ヘッダー作成（バッククォートを排除）
        $headers = @(
            "HTTP/1.1 200 OK",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: POST, GET, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "Connection: close"
        )
        $headerString = [string]::Join([char]13 + [char]10, $headers) + [char]13 + [char]10 + [char]13 + [char]10

        if ($method -eq 'OPTIONS') {
            $writer.Write($headerString)
            $writer.Flush()
        } elseif ($method -eq 'GET' -and ($path -eq '/' -or $path -eq '/index.html')) {
            $htmlPath = Join-Path $PSScriptRoot "public\index.html"
            if (Test-Path $htmlPath) {
                $html = Get-Content -Path $htmlPath -Raw -Encoding UTF8
                $writer.Write($headerString)
                $writer.Write($html)
                $writer.Flush()
            } else {
                $writer.Write("HTTP/1.1 404 Not Found")
                $writer.Flush()
            }
        } elseif ($method -eq 'POST' -and $path -eq '/api/shortcut') {
            $body = ""
            if ($contentLength -gt 0) {
                $buffer = New-Object char[] $contentLength
                $reader.Read($buffer, 0, $contentLength) | Out-Null
                $body = -join $buffer
            }
            
            try {
                $json = $body | ConvertFrom-Json
                if ($json.sequence) {
                    foreach ($seq in $json.sequence) {
                        $keys = @()
                        foreach ($k in $seq) {
                            if ($KeyMap.ContainsKey($k)) { $keys += $KeyMap[$k] }
                        }
                        if ($keys.Count -gt 0) {
                            [Keyboard]::PressKeys([byte[]]$keys)
                            Start-Sleep -Milliseconds 50
                        }
                    }
                }
                $resBody = '{"success":true}'
            } catch {
                $resBody = '{"success":false}'
            }
            $writer.Write($headerString)
            $writer.Write($resBody)
            $writer.Flush()
        } else {
            $writer.Write("HTTP/1.1 404 Not Found")
            $writer.Flush()
        }
    } catch {
        Write-Host "Error occurred."
    } finally {
        $client.Close()
    }
}
