# R11: the AI request transport (ii-shim ai-request).
#   - the request file (it holds the prompt) is gone once the request has been read, whatever the outcome
#   - the credential is never in that file: headers name environment variables and the shim expands them
#   - stale request.*.json files of ours are swept (older than an hour, only that name pattern); anything
#     else in the folder is left alone
# Talks to a throwaway HTTP server on 127.0.0.1; no real service, no real key.
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$shim = Join-Path $repo 'host\build-clang\ii-shim.exe'
if (-not (Test-Path $shim)) { Skip-Test 'ii-shim not built with clang-cl: cmake -S host -B host\build-clang -G Ninja -DCMAKE_CXX_COMPILER=clang-cl ...; cmake --build host\build-clang --target ii-shim' }
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { Skip-Test 'python not found (used as a throwaway HTTP server)' }

$base = Join-Path $env:TEMP ('ii-airequest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $base | Out-Null
$server = $null
try {
    $port = Get-Random -Minimum 20000 -Maximum 40000
    $serverScript = Join-Path $base 'server.py'
    Set-Content $serverScript @"
import http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0)); body = self.rfile.read(n).decode()
        out = ('AUTH=' + str(self.headers.get('Authorization')) + ' BODY=' + body).encode()
        self.send_response(200); self.send_header('Content-Type', 'text/plain'); self.send_header('Content-Length', str(len(out))); self.end_headers(); self.wfile.write(out)
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', $port), H).serve_forever()
"@
    $server = Start-Process python -ArgumentList '-I', $serverScript -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 2

    $folder = Join-Path $base 'ai'
    New-Item -ItemType Directory -Force $folder | Out-Null
    $request = Join-Path $folder 'request.instA.json'
    @{ url = "http://127.0.0.1:$port/v1/chat"; headers = @{ Authorization = 'Bearer ${II_TEST_KEY}'; 'Content-Type' = 'application/json' }; body = '{"prompt":"SENTINEL-PROMPT"}' } |
        ConvertTo-Json -Depth 4 | Set-Content $request -Encoding UTF8
    Assert-True (-not (Get-Content $request -Raw).Contains('SENTINEL-KEY-VALUE')) 'the request file does not contain the credential'

    # stale files: ours and old, ours and new, and somebody else's
    $old = Join-Path $folder 'request.instOld.json'; Set-Content $old '{}'; (Get-Item $old).LastWriteTime = (Get-Date).AddHours(-3)
    $new = Join-Path $folder 'request.instNew.json'; Set-Content $new '{}'
    $other = Join-Path $folder 'notes.json'; Set-Content $other '{}'; (Get-Item $other).LastWriteTime = (Get-Date).AddHours(-3)
    $otherRequest = Join-Path $folder 'request.txt'; Set-Content $otherRequest 'x'; (Get-Item $otherRequest).LastWriteTime = (Get-Date).AddHours(-3)

    $env:II_TEST_KEY = 'SENTINEL-KEY-VALUE'
    $out = & $shim ai-request $request 2>&1 | Out-String
    Remove-Item Env:II_TEST_KEY
    Assert-Equal $LASTEXITCODE 0 "the request succeeds ($($out.Trim()))"
    Assert-True ($out.Contains('AUTH=Bearer SENTINEL-KEY-VALUE')) 'the shim expanded the environment variable into the header'
    Assert-True ($out.Contains('SENTINEL-PROMPT')) 'and sent the body'
    Assert-PathMissing $request 'the request file (with the prompt) is deleted once read'
    Assert-PathMissing $old 'a stale request.*.json of ours was swept'
    Assert-PathExists $new 'a recent one was not'
    Assert-PathExists $other 'an unrelated old file was not touched'
    Assert-PathExists $otherRequest 'neither was a file that only looks similar'

    # a failing request still removes its file
    $request2 = Join-Path $folder 'request.instB.json'
    @{ url = 'http://127.0.0.1:1/unreachable'; headers = @{}; body = '{"prompt":"SENTINEL-PROMPT-2"}' } | ConvertTo-Json | Set-Content $request2 -Encoding UTF8
    $failOut = & $shim ai-request $request2 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -ne 0) 'a request to an unreachable server fails'
    Assert-PathMissing $request2 'and its file is deleted anyway'

    # a malformed request file: the failure is reported (and the file is not our concern: it is invalid)
    $request3 = Join-Path $folder 'request.instC.json'
    Set-Content $request3 'not json'
    [void](& $shim ai-request $request3 2>&1)
    Assert-True ($LASTEXITCODE -ne 0) 'an invalid request file is refused'
}
finally {
    Remove-Item Env:II_TEST_KEY -ErrorAction SilentlyContinue
    if ($server) { try { $server.Kill() } catch {} }
    Start-Sleep -Milliseconds 300
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
