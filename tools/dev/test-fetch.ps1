# Host-only tests: no GUI, config writes, or installed binaries. --test alone enables fixtures.
param(
    [string]$Shim = (Join-Path $PSScriptRoot '..\..\host\build\ii-shim.exe'),
    [switch]$Offline
)

$ErrorActionPreference = 'Stop'
$Shim = (Resolve-Path -LiteralPath $Shim).Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('ii-fetch-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$saved = [Environment]::GetEnvironmentVariable('II_HTTP_TEST_RESPONSES', 'Process')
$env:II_HTTP_TEST_RESPONSES = Join-Path $testRoot 'responses.json'
$script:responses = @{}
$script:passed = 0
$script:failed = 0
$utf8 = [Text.UTF8Encoding]::new($false)

function Invoke-Shim([string[]]$Arguments) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Shim
    $info.Arguments = ($Arguments | ForEach-Object {
        $quoted = [regex]::Replace($_, '(\\*)"', '$1$1\"')
        '"' + [regex]::Replace($quoted, '(\\+)$', '$1$1') + '"'
    }) -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)
    $buffer = [IO.MemoryStream]::new()
    try {
        $stdout = $process.StandardOutput.BaseStream.CopyToAsync($buffer)
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(90000)) {
            $process.Kill()
            throw 'ii-shim test timed out'
        }
        $stdout.GetAwaiter().GetResult()
        $bytes = $buffer.ToArray()
        [pscustomobject]@{ Code = $process.ExitCode; Bytes = $bytes; Out = $utf8.GetString($bytes); Error = $stderr.Result.Trim() }
    } finally { $buffer.Dispose(); $process.Dispose() }
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Test-Case([string]$Name, [scriptblock]$Body) {
    try {
        & $Body
        Write-Output "PASS $Name"
        $script:passed++
    } catch {
        Write-Output "FAIL ${Name}: $($_.Exception.Message)"
        $script:failed++
    }
}

function Set-Responses($Responses) {
    [IO.File]::WriteAllText($env:II_HTTP_TEST_RESPONSES, ($Responses | ConvertTo-Json -Depth 12), $utf8)
}

function Assert-Bytes([byte[]]$Actual, [byte[]]$Expected) {
    Assert-True ([Convert]::ToBase64String($Actual) -ceq [Convert]::ToBase64String($Expected)) 'Response bytes changed'
}

function Assert-Failure($Result, [string]$Reason, [string]$Directory = '') {
    Assert-True ($Result.Code -ne 0) 'Expected non-zero exit'
    Assert-True ($Result.Error -match $Reason) "Unexpected error: $($Result.Error)"
    Assert-True (($Result.Error -split '\r?\n').Count -eq 1) 'Expected one-line stderr reason'
    Assert-True ($Result.Bytes.Length -eq 0) 'Failure printed a partial response'
    if ($Directory) {
        Assert-True (@(Get-ChildItem -LiteralPath $Directory -Recurse -File -ErrorAction SilentlyContinue).Count -eq 0) 'Failure left a file behind'
    }
}

function Assert-Weather($Result) {
    Assert-True ($Result.Code -eq 0) "exit=$($Result.Code): $($Result.Error)"
    $weather = $Result.Out | ConvertFrom-Json
    Assert-True (@($weather.PSObject.Properties).Count -eq 3) 'Weather must have exactly three keys'
    foreach ($key in @('current', 'location', 'astronomy')) {
        Assert-True ($null -ne $weather.$key -and $weather.$key -is [pscustomobject]) "Missing weather object $key"
    }
    return $weather
}

try {
    # The envelope substitutes response headers and a body stream, below shared redirect/cap checks.
    $bodyPath = Join-Path $testRoot 'binary fixture.bin'
    $fixtureBytes = [byte[]]@(0, 10, 13, 10, 26, 39, 128, 255)
    [IO.File]::WriteAllBytes($bodyPath, $fixtureBytes)
    $weatherPath = Join-Path $testRoot 'weather.json'
    [IO.File]::WriteAllText($weatherPath, '{"current_condition":[{"temp_C":"17","humidity":"81"},{"temp_C":"99"}],"nearest_area":[{"areaName":[{"value":"Bogot\u00e1"}]}],"weather":[{"astronomy":[{"sunrise":"05:45 AM","sunset":"05:47 PM"}]}],"unused":true}', $utf8)
    $script:responses = @{
        'https://fixture.invalid/body' = @{ status = 200; bodyFile = $bodyPath; contentLength = '8' }
        'https://fixture.invalid/empty' = @{ status = 204 }
        'https://fixture.invalid/agent' = @{ status = 200; bodyFile = $bodyPath; agent = "ii-test/O'Brien & safe" }
        'https://fixture.invalid/redirect' = @{ status = 302; location = '/body' }
        'https://fixture.invalid/cross-host' = @{ status = 301; location = 'https://other.invalid/redirect' }
        'https://other.invalid/redirect' = @{ status = 307; location = 'https://fixture.invalid/last-hop' }
        'https://fixture.invalid/last-hop' = @{ status = 308; location = '/body' }
        'https://fixture.invalid/downgrade' = @{ status = 302; location = 'http://fixture.invalid/body' }
        'https://fixture.invalid/second-hop' = @{ status = 303; location = '/downgrade' }
        'https://fixture.invalid/loop' = @{ status = 302; location = '/loop' }
        'https://fixture.invalid/no-location' = @{ status = 302 }
        'https://fixture.invalid/error' = @{ status = 404 }
        'https://fixture.invalid/no-length' = @{ status = 200; bodyFile = $bodyPath }
        'https://fixture.invalid/truncated' = @{ status = 200; bodyFile = $bodyPath; contentLength = '10' }
        'https://fixture.invalid/huge-length' = @{ status = 200; bodyFile = $bodyPath; contentLength = '18446744073709551616' }
        'https://wttr.in/San%20Francisco?format=j1' = @{ status = 200; bodyFile = $weatherPath }
        'https://wttr.in/Bogot%C3%A1%20%26%20%2F%3F%23%25?format=j1' = @{ status = 200; bodyFile = $weatherPath }
        'https://wttr.in/4.711%2C-74.072?format=j1' = @{ status = 200; bodyFile = $weatherPath }
    }
    Set-Responses $script:responses

    Test-Case 'binary stdout preserves NUL, CRLF, Ctrl-Z and high bytes' {
        $result = Invoke-Shim @('fetch', 'https://fixture.invalid/body', '--test')
        Assert-True ($result.Code -eq 0 -and -not $result.Error) "exit=$($result.Code): $($result.Error)"
        Assert-Bytes $result.Bytes $fixtureBytes
    }
    Test-Case 'empty successful response' {
        $result = Invoke-Shim @('fetch', 'https://fixture.invalid/empty', '--test')
        Assert-True ($result.Code -eq 0 -and $result.Bytes.Length -eq 0) $result.Error
    }
    Test-Case 'atomic out creates parents and preserves literal path characters' {
        $path = Join-Path $testRoot "out space\O'Brien & # %\image.bin"
        $result = Invoke-Shim @('fetch', 'https://fixture.invalid/body', '--out', $path, '--test')
        Assert-True ($result.Code -eq 0 -and $result.Bytes.Length -eq 0) $result.Error
        Assert-Bytes ([IO.File]::ReadAllBytes($path)) $fixtureBytes
        Assert-True (@(Get-ChildItem -LiteralPath (Split-Path $path) -File).Count -eq 1) 'Temp file left behind'
        [IO.File]::WriteAllText($path, 'old')
        $result = Invoke-Shim @('fetch', 'https://fixture.invalid/body', '--out', $path, '--test')
        Assert-True ($result.Code -eq 0) $result.Error
        Assert-Bytes ([IO.File]::ReadAllBytes($path)) $fixtureBytes
    }
    Test-Case 'keep skips request and leaves existing file untouched' {
        $path = Join-Path $testRoot 'keep.bin'
        [IO.File]::WriteAllText($path, 'keep me')
        $result = Invoke-Shim @('fetch', 'https://not-in-fixture.invalid/', '--out', $path, '--keep', '--test')
        Assert-True ($result.Code -eq 0 -and $result.Bytes.Length -eq 0) $result.Error
        Assert-True ([IO.File]::ReadAllText($path) -ceq 'keep me') 'Existing file replaced'
    }
    Test-Case 'keep downloads a missing file' {
        $path = Join-Path $testRoot 'keep-missing.bin'
        $result = Invoke-Shim @('fetch', 'https://fixture.invalid/body', '--out', $path, '--keep', '--test')
        Assert-True ($result.Code -eq 0) $result.Error
        Assert-Bytes ([IO.File]::ReadAllBytes($path)) $fixtureBytes
    }
    Test-Case 'agent is forwarded literally' {
        $result = Invoke-Shim @('fetch', 'https://fixture.invalid/agent', '--agent', "ii-test/O'Brien & safe", '--test')
        Assert-True ($result.Code -eq 0) $result.Error
        Assert-Bytes $result.Bytes $fixtureBytes
    }
    foreach ($url in @('redirect', 'cross-host')) {
        Test-Case "HTTPS redirects ($url)" {
            $result = Invoke-Shim @('fetch', "https://fixture.invalid/$url", '--test')
            Assert-True ($result.Code -eq 0) $result.Error
            Assert-Bytes $result.Bytes $fixtureBytes
        }
    }
    foreach ($url in @('http://fixture.invalid/body', 'ftp://fixture.invalid/body', 'https://user:secret@fixture.invalid/body', "https://fixture.invalid/a`nheader")) {
        Test-Case "reject unsafe URL ($($url.Replace("`n", '<LF>')))" {
            Assert-Failure (Invoke-Shim @('fetch', $url, '--test')) 'HTTPS|invalid'
        }
    }
    foreach ($case in @(
        @{ Url = 'downgrade'; Reason = 'HTTPS' },
        @{ Url = 'second-hop'; Reason = 'HTTPS' },
        @{ Url = 'loop'; Reason = 'redirects' },
        @{ Url = 'no-location'; Reason = 'location' },
        @{ Url = 'error'; Reason = '404' },
        @{ Url = 'truncated'; Reason = 'incomplete' },
        @{ Url = 'huge-length'; Reason = 'size limit|content length' }
    )) {
        Test-Case "failed fetch leaves no file ($($case.Url))" {
            $directory = Join-Path $testRoot $case.Url
            Assert-Failure (Invoke-Shim @('fetch', "https://fixture.invalid/$($case.Url)", '--out', (Join-Path $directory 'body.bin'), '--test')) $case.Reason $directory
        }
    }
    foreach ($url in @('body', 'no-length')) {
        Test-Case "size cap with and without Content-Length ($url)" {
            $directory = Join-Path $testRoot "cap-$url"
            Assert-Failure (Invoke-Shim @('fetch', "https://fixture.invalid/$url", '--out', (Join-Path $directory 'body.bin'), '--max', '7', '--test')) 'size limit' $directory
            $result = Invoke-Shim @('fetch', "https://fixture.invalid/$url", '--max', '8', '--test')
            Assert-True ($result.Code -eq 0) $result.Error
            Assert-Bytes $result.Bytes $fixtureBytes
        }
    }
    Test-Case 'default 40 MB cap rejects an oversized streamed body' {
        $largePath = Join-Path $testRoot 'large.bin'
        $stream = [IO.File]::OpenWrite($largePath)
        try { $stream.SetLength(40 * 1024 * 1024 + 1) } finally { $stream.Dispose() }
        $script:responses['https://fixture.invalid/large'] = @{ status = 200; bodyFile = $largePath }
        Set-Responses $script:responses
        $directory = Join-Path $testRoot 'default-cap'
        Assert-Failure (Invoke-Shim @('fetch', 'https://fixture.invalid/large', '--out', (Join-Path $directory 'body.bin'), '--test')) 'size limit' $directory
    }
    Test-Case 'failed replacement preserves old file' {
        $path = Join-Path $testRoot 'preserve.bin'
        [IO.File]::WriteAllText($path, 'existing')
        Assert-Failure (Invoke-Shim @('fetch', 'https://fixture.invalid/truncated', '--out', $path, '--test')) 'incomplete'
        Assert-True ([IO.File]::ReadAllText($path) -ceq 'existing') 'Old file changed'
    }
    Test-Case 'rename failure removes temporary file' {
        $directory = Join-Path $testRoot 'rename'
        $target = Join-Path $directory 'directory.bin'
        [IO.Directory]::CreateDirectory($target) | Out-Null
        Assert-Failure (Invoke-Shim @('fetch', 'https://fixture.invalid/body', '--out', $target, '--test')) 'rename|output.*directory' $directory
    }
    foreach ($arguments in @(
        @('fetch'), @('fetch', 'https://fixture.invalid/body', '--out'),
        @('fetch', 'https://fixture.invalid/body', '--keep'),
        @('fetch', 'https://fixture.invalid/body', '--max', '0'),
        @('fetch', 'https://fixture.invalid/body', '--max', '-1'),
        @('fetch', 'https://fixture.invalid/body', '--max', '18446744073709551616'),
        @('fetch', 'https://fixture.invalid/body', '--unknown'),
        @('fetch', 'https://fixture.invalid/body', '--agent', "bad`r`nAgent"),
        @('weather'), @('weather', 'city', 'unexpected')
    )) {
        Test-Case "reject malformed arguments ($($arguments -join ' '))" {
            Assert-Failure (Invoke-Shim ($arguments + @('--test'))) 'usage|User-Agent|max'
        }
    }
    foreach ($place in @('San Francisco', 'San+Francisco', "Bogot$([char]0xE1) & /?#%", '4.711,-74.072')) {
        Test-Case "weather shape and URL encoding ($place)" {
            $weather = Assert-Weather (Invoke-Shim @('weather', $place, '--test'))
            Assert-True ($weather.current.temp_C -ceq '17') 'Wrong current condition selected'
            Assert-True ($weather.location.areaName[0].value -ceq "Bogot$([char]0xE1)") 'Location changed'
            Assert-True ($weather.astronomy.sunrise -ceq '05:45 AM') 'Astronomy changed'
        }
    }
    foreach ($text in @('{broken', '{"current_condition":[],"nearest_area":[{}],"weather":[{"astronomy":[{}]}]}', '{"current_condition":[{}],"nearest_area":[{}],"weather":[{"astronomy":[null]}]}')) {
        Test-Case 'weather rejects malformed or incomplete JSON without partial stdout' {
            [IO.File]::WriteAllText($weatherPath, $text, $utf8)
            Assert-Failure (Invoke-Shim @('weather', 'San+Francisco', '--test')) 'JSON|weather'
        }
    }
    # No listener, no TLS override: this checks real transport failure and fixture flag isolation.
    $socket = [Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::InterNetwork, [Net.Sockets.SocketType]::Stream, [Net.Sockets.ProtocolType]::Tcp)
    $socket.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Loopback, 0))
    try {
        $url = "https://127.0.0.1:$($socket.LocalEndPoint.Port)/body"
        $script:responses[$url] = @{ status = 200; bodyFile = $bodyPath }
        Set-Responses $script:responses
        Test-Case 'test environment ignored without explicit flag; transport failure leaves no file' {
            $directory = Join-Path $testRoot 'no-network'
            Assert-Failure (Invoke-Shim @('fetch', $url, '--out', (Join-Path $directory 'body.bin'))) 'HTTP request failed' $directory
        }
    } finally { $socket.Dispose() }

    # Check the actual staged QML's JS boundary without starting Qt or creating a window.
    # Node is optional and must already be installed; it is never downloaded by this test.
    if (Get-Command node -ErrorAction SilentlyContinue) {
        Test-Case 'QML image probe encodes native paths and preserves file URLs' {
            $probeScript = Join-Path $testRoot 'probe-paths.cjs'
            [IO.File]::WriteAllText($probeScript, @'
const fs = require('node:fs');
const assert = require('node:assert/strict');
const qml = fs.readFileSync(process.argv[2], 'utf8').replace(/\r\n/g, '\n');
const functions = [...qml.matchAll(/^    function \w+\(\) \{[\s\S]*?\n    \}/gm)].map(match => match[0]).join('\n');
const assignments = [...qml.matchAll(/imageSizeProbe\.source = ([^\n;]+);/g)].map(match => match[1]).filter(value => value !== '""');
assert.equal(assignments.length, 1, 'Expected one image probe load expression');
const run = new Function('filePath', 'FileUtils', 'Qt', functions + '\nconst root = {filePath}; return [processFilePath(), (' + assignments[0] + ').toString()];');
const FileUtils = {trimFileProtocol: path => path.startsWith('file://') ? path.slice(7) : path};
const Qt = {resolvedUrl: path => new URL(path, 'file:///C:/fixture/')};
for (const [path, native, uri] of [
    ['/C:/cache/a#b.png', '/C:/cache/a#b.png', 'file:///C:/cache/a%23b.png'],
    ['C:\\cache\\a%20b.png', 'C:\\cache\\a%20b.png', 'file:///C:/cache/a%2520b.png'],
    ['file:///C:/cache/a%20b%23c%25.png', '/C:/cache/a b#c%.png', 'file:///C:/cache/a%20b%23c%25.png'],
    ['//server/share/a#b.png', '//server/share/a#b.png', 'file://server/share/a%23b.png'],
    ['a#b.png', 'a#b.png', 'file:///C:/fixture/a%23b.png'],
]) {
    assert.deepEqual(run(path, FileUtils, Qt), [native, uri], path);
}
'@, $utf8)
            $qmlPath = Join-Path $PSScriptRoot '..\..\build\ii\modules\common\utils\ImageDownloaderProcess.qml'
            & node $probeScript $qmlPath
            Assert-True ($LASTEXITCODE -eq 0) 'QML image path conversion failed'
        }
    } else { Write-Output 'SKIP QML image path conversion: existing Node is unavailable' }

    if (-not $Offline) {
        $env:II_HTTP_TEST_RESPONSES = $null
        Test-Case 'live HTTPS stdout' {
            $result = Invoke-Shim @('fetch', 'https://www.example.com/')
            Assert-True ($result.Code -eq 0 -and $result.Out -match 'Example Domain') "exit=$($result.Code): $($result.Error)"
        }
        Test-Case 'live HTTPS redirect and atomic out' {
            $path = Join-Path $testRoot 'live\redirect.json'
            $result = Invoke-Shim @('fetch', 'https://httpbin.org/redirect-to?url=https%3A%2F%2Fhttpbin.org%2Fget', '--out', $path)
            Assert-True ($result.Code -eq 0) "exit=$($result.Code): $($result.Error)"
            $response = [IO.File]::ReadAllText($path) | ConvertFrom-Json
            Assert-True ($response.url -eq 'https://httpbin.org/get') 'Redirect did not reach target'
        }
        Test-Case 'live weather JSON shape' {
            $weather = Assert-Weather (Invoke-Shim @('weather', 'Bogota'))
            Assert-True ($null -ne $weather.current.temp_C) 'Current temperature missing'
        }
    }
} finally {
    [Environment]::SetEnvironmentVariable('II_HTTP_TEST_RESPONSES', $saved, 'Process')
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $temporary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($temporary, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Output "fetch tests: $script:passed passed, $script:failed failed"
if ($script:failed -ne 0) { exit 1 }
