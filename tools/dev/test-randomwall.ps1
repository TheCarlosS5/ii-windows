# Host-only tests. Every child process has applying disabled; no shell processes are launched.
param(
    [string]$Shim = (Join-Path $PSScriptRoot '..\..\host\build\ii-shim.exe'),
    [switch]$Offline
)

$ErrorActionPreference = 'Stop'
$Shim = (Resolve-Path -LiteralPath $Shim).Path
Add-Type -AssemblyName System.Drawing
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('ii-randomwall-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$variables = @('II_RANDOMWALL_NO_APPLY', 'II_RANDOMWALL_TEST_OUT', 'II_RANDOMWALL_TEST_RESPONSE',
    'II_RANDOMWALL_TEST_API_URL', 'II_RANDOMWALL_TEST_CONFIG', 'II_RANDOMWALL_TEST_IMAGE')
$saved = @{}
foreach ($name in $variables) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    [Environment]::SetEnvironmentVariable($name, $null, 'Process')
}
$env:II_RANDOMWALL_NO_APPLY = '1'
$script:passed = 0
$script:failed = 0

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
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(90000)) {
            $process.Kill()
            throw 'ii-shim test timed out'
        }
        [pscustomobject]@{ Code = $process.ExitCode; Out = $stdout.Result.Trim(); Error = $stderr.Result.Trim() }
    } finally { $process.Dispose() }
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

function Assert-Image([string]$Directory) {
    $files = @(Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue)
    Assert-True ($files.Count -eq 1) "Expected one image and no temp files, got $($files.Count) files"
    Assert-True ($files[0].Name -match '^random_wallpaper(-1)?\.(jpg|jpeg|png|webp|gif|bmp)$') 'Unexpected filename'
    $image = [Drawing.Image]::FromFile($files[0].FullName)
    try {
        Assert-True ($image.Width -gt 0 -and $image.Height -gt 0) 'Image has no dimensions'
        $bitmap = [Drawing.Bitmap]::new($image)
        try { $null = $bitmap.GetPixel(0, 0) } finally { $bitmap.Dispose() }
        Write-Output "  image=$($files[0].Name) $($image.Width)x$($image.Height) bytes=$($files[0].Length); temp=0"
    } finally { $image.Dispose() }
}

function Assert-Failure($Result, [string]$Directory, [string]$Reason) {
    Assert-True ($Result.Code -ne 0) 'Expected non-zero exit'
    Assert-True ($Result.Error -match $Reason) "Unexpected error: $($Result.Error)"
    Assert-True (($Result.Error -split '\r?\n').Count -eq 1) 'Expected a one-line error'
    $files = @(Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue)
    Assert-True ($files.Count -eq 0) 'Failure left a file behind'
    Write-Output "  exit=$($Result.Code); $($Result.Error); files=0"
}

function Set-Response([string]$Text) {
    $env:II_RANDOMWALL_TEST_RESPONSE = Join-Path $testRoot 'response.json'
    [IO.File]::WriteAllText($env:II_RANDOMWALL_TEST_RESPONSE, $Text, [Text.UTF8Encoding]::new($false))
}

try {
    Test-Case 'reject invalid provider' {
        $result = Invoke-Shim @('randomwall', 'invalid', '--no-apply', '--out', (Join-Path $testRoot 'invalid'))
        Assert-Failure $result (Join-Path $testRoot 'invalid') 'usage: randomwall'
    }
    Test-Case 'reject unknown option' {
        $result = Invoke-Shim @('randomwall', 'osu', '--no-apply', '--unknown')
        Assert-Failure $result (Join-Path $testRoot 'invalid') 'usage: randomwall'
    }
    Test-Case 'reject missing output directory' {
        $result = Invoke-Shim @('randomwall', 'osu', '--no-apply', '--out')
        Assert-Failure $result (Join-Path $testRoot 'invalid') 'usage: randomwall'
    }
    Test-Case 'output option cannot consume no-apply flag' {
        $result = Invoke-Shim @('randomwall', 'osu', '--out', '--no-apply')
        Assert-Failure $result (Join-Path $testRoot 'invalid') 'usage: randomwall'
    }

    if ($Offline) {
        # Generate an image with Windows' existing decoder, without fetching a dependency.
        $env:II_RANDOMWALL_TEST_IMAGE = Join-Path $testRoot 'fixture.png'
        $bitmap = [Drawing.Bitmap]::new(3, 2)
        try {
            $bitmap.SetPixel(0, 0, [Drawing.Color]::CornflowerBlue)
            $bitmap.Save($env:II_RANDOMWALL_TEST_IMAGE, [Drawing.Imaging.ImageFormat]::Png)
        } finally { $bitmap.Dispose() }
        foreach ($provider in @('konachan', 'osu')) {
            Test-Case "fixture $provider download" {
                if ($provider -eq 'konachan') { Set-Response '[{"file_url":"https://example.com/image.png"}]' }
                else { Set-Response '{"backgrounds":[{"url":"https://example.com/image.png"}]}' }
                $directory = Join-Path $testRoot $provider
                $result = Invoke-Shim @('randomwall', $provider, '--no-apply', '--out', $directory)
                Write-Output $result.Out
                Assert-True ($result.Code -eq 0) "exit=$($result.Code): $($result.Error)"
                Assert-Image $directory
            }
        }
        Test-Case 'image format follows response bytes' {
            Set-Response '{"backgrounds":[{"url":"https://example.com/image.jpg"}]}'
            $directory = Join-Path $testRoot 'changed-format'
            $result = Invoke-Shim @('randomwall', 'osu', '--no-apply', '--out', $directory)
            Assert-True ($result.Code -eq 0) "exit=$($result.Code): $($result.Error)"
            Assert-True (Test-Path -LiteralPath (Join-Path $directory 'random_wallpaper.png')) 'Response format was ignored'
            Assert-Image $directory
        }
        foreach ($current in @('plain', 'file URI')) {
            Test-Case "current wallpaper alternates filename ($current)" {
                Set-Response '{"backgrounds":[{"url":"https://example.com/image.PNG?token=1"}]}'
                $directory = Join-Path $testRoot ('alternate-' + $script:passed)
                [IO.Directory]::CreateDirectory($directory) | Out-Null
                $path = Join-Path $directory 'random_wallpaper.png'
                [IO.File]::WriteAllText($path, 'current wallpaper')
                $configuredPath = $path.Replace('\', '/').ToUpperInvariant()
                if ($current -eq 'file URI') { $configuredPath = 'file:///' + $configuredPath }
                $env:II_RANDOMWALL_TEST_CONFIG = Join-Path $testRoot 'config.json'
                $config = @{ background = @{ wallpaperPath = $configuredPath }; networking = @{ userAgent = 'ii-test/1' } }
                [IO.File]::WriteAllText($env:II_RANDOMWALL_TEST_CONFIG, ($config | ConvertTo-Json -Depth 4))
                $result = Invoke-Shim @('randomwall', 'osu', '--no-apply', '--out', $directory)
                Assert-True ($result.Code -eq 0) "exit=$($result.Code): $($result.Error)"
                Assert-True ([IO.File]::ReadAllText($path) -eq 'current wallpaper') 'Current wallpaper was overwritten'
                Assert-True (Test-Path -LiteralPath (Join-Path $directory 'random_wallpaper-1.png')) 'Alternate image missing'
                Assert-True (@(Get-ChildItem -LiteralPath $directory -File).Count -eq 2) 'Temporary file was left'
            }
        }
        Test-Case 'malformed config falls back to defaults' {
            [IO.File]::WriteAllText($env:II_RANDOMWALL_TEST_CONFIG, '{broken')
            Set-Response '{"backgrounds":[{"url":"https://example.com/image.png"}]}'
            $directory = Join-Path $testRoot 'bad-config'
            $result = Invoke-Shim @('randomwall', 'osu', '--no-apply', '--out', $directory)
            Assert-True ($result.Code -eq 0) "exit=$($result.Code): $($result.Error)"
            Assert-Image $directory
        }
        $env:II_RANDOMWALL_TEST_CONFIG = $null
        Test-Case 'rename failure removes temporary file' {
            Set-Response '{"backgrounds":[{"url":"https://example.com/image.png"}]}'
            $directory = Join-Path $testRoot 'rename-failure'
            [IO.Directory]::CreateDirectory((Join-Path $directory 'random_wallpaper.png')) | Out-Null
            $result = Invoke-Shim @('randomwall', 'osu', '--no-apply', '--out', $directory)
            Assert-Failure $result $directory 'cannot rename wallpaper'
        }
        Test-Case 'non-image response leaves no files' {
            [IO.File]::WriteAllText($env:II_RANDOMWALL_TEST_IMAGE, '<html>not an image</html>')
            Set-Response '{"backgrounds":[{"url":"https://example.com/image.png"}]}'
            $directory = Join-Path $testRoot 'not-image'
            $result = Invoke-Shim @('randomwall', 'osu', '--no-apply', '--out', $directory)
            Assert-Failure $result $directory 'not a supported image'
        }
        Test-Case 'image size cap leaves no files' {
            $stream = [IO.File]::OpenWrite($env:II_RANDOMWALL_TEST_IMAGE)
            try { $stream.SetLength(40 * 1024 * 1024 + 1) } finally { $stream.Dispose() }
            Set-Response '{"backgrounds":[{"url":"https://example.com/image.png"}]}'
            $directory = Join-Path $testRoot 'too-large'
            $result = Invoke-Shim @('randomwall', 'osu', '--no-apply', '--out', $directory)
            Assert-Failure $result $directory 'size limit'
        }
        # Restore the valid fixture for the bash dispatch tests below.
        $bitmap = [Drawing.Bitmap]::new(3, 2)
        try { $bitmap.Save($env:II_RANDOMWALL_TEST_IMAGE, [Drawing.Imaging.ImageFormat]::Png) }
        finally { $bitmap.Dispose() }
    } else {
        foreach ($provider in @('konachan', 'osu')) {
            Test-Case "live $provider download" {
                $directory = Join-Path $testRoot $provider
                $result = Invoke-Shim @('randomwall', $provider, '--no-apply', '--out', $directory)
                Write-Output $result.Out
                Assert-True ($result.Code -eq 0) "exit=$($result.Code): $($result.Error)"
                Assert-True ($result.Out -match 'Saved:') 'Missing saved status'
                Assert-Image $directory
            }
        }
    }
    foreach ($command in @('C:/x/scripts/colors/random/random_osu_wall.sh',
        '/C:/x/scripts/colors/random/random_osu_wall.sh',
        '"C:\x with spaces\scripts\random_osu_wall.sh"',
        '"C:/x O''Brien & $safe/random_osu_wall.sh"',
        "'C:/x with spaces/random_konachan_wall.sh'")) {
        Test-Case "bash dispatch $command" {
            if ($Offline) {
                if ($command -match 'konachan') { Set-Response '[{"file_url":"https://example.com/image.png"}]' }
                else { Set-Response '{"backgrounds":[{"url":"https://example.com/image.png"}]}' }
            }
            $env:II_RANDOMWALL_TEST_OUT = Join-Path $testRoot ('bash-' + $script:passed)
            $result = Invoke-Shim @('bash', '-c', $command)
            Write-Output $result.Out
            Assert-True ($result.Code -eq 0) "exit=$($result.Code): $($result.Error)"
            Assert-True ($result.Out -match 'Not applied') 'No-apply env was ignored'
            Assert-Image $env:II_RANDOMWALL_TEST_OUT
        }
    }
    $env:II_RANDOMWALL_TEST_OUT = $null
    $env:II_RANDOMWALL_TEST_RESPONSE = $null
    $env:II_RANDOMWALL_TEST_IMAGE = $null

    foreach ($command in @('C:/x/random_osu_wall.sh;whoami',
        'C:/x/random_osu_wall.sh --no-apply', '"C:/x/random_osu_wall.sh" && whoami',
        'C:/x/random_osu_wall.sh && whoami', 'switchwall --mode dark;whoami',
        'echo hello | whoami')) {
        Test-Case "restricted bash $command" {
            $result = Invoke-Shim @('bash', '-c', $command)
            Assert-True ($result.Code -eq 127) "Expected 127, got $($result.Code)"
        }
    }

    # Reserve a port without listening: WinHTTP must fail without disconnecting this PC.
    $socket = [Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::InterNetwork,
        [Net.Sockets.SocketType]::Stream, [Net.Sockets.ProtocolType]::Tcp)
    $socket.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Loopback, 0))
    $unreachable = "https://127.0.0.1:$($socket.LocalEndPoint.Port)"
    try {
        Test-Case 'unreachable API' {
            $env:II_RANDOMWALL_TEST_API_URL = "$unreachable/api"
            $directory = Join-Path $testRoot 'no-network'
            $result = Invoke-Shim @('randomwall', 'osu', '--no-apply', '--out', $directory)
            Assert-Failure $result $directory 'HTTP request failed'
        }
        $env:II_RANDOMWALL_TEST_API_URL = $null
        foreach ($case in @(
            @{ Name = 'bad JSON'; Provider = 'osu'; Body = '{broken'; Reason = 'invalid JSON' },
            @{ Name = 'bad Konachan JSON'; Provider = 'konachan'; Body = '{broken'; Reason = 'invalid JSON' },
            @{ Name = 'wrong backgrounds type'; Provider = 'osu'; Body = '{"backgrounds":{}}'; Reason = 'invalid JSON' },
            @{ Name = 'wrong entry type'; Provider = 'osu'; Body = '{"backgrounds":[null]}'; Reason = 'invalid JSON' },
            @{ Name = 'empty osu list'; Provider = 'osu'; Body = '{"backgrounds":[]}'; Reason = 'no wallpapers' },
            @{ Name = 'empty Konachan list'; Provider = 'konachan'; Body = '[]'; Reason = 'no wallpapers' },
            @{ Name = 'missing image URL'; Provider = 'konachan'; Body = '[{}]'; Reason = 'missing image URL' },
            @{ Name = 'non-image URL'; Provider = 'osu'; Body = '{"backgrounds":[{"url":"https://example.com/payload.exe"}]}'; Reason = 'image extension' },
            @{ Name = 'HTTP image URL'; Provider = 'konachan'; Body = '[{"file_url":"http://example.com/image.jpg"}]'; Reason = 'HTTPS' },
            @{ Name = 'unreachable image'; Provider = 'osu'; Body = "{`"backgrounds`": [{`"url`": `"$unreachable/image.jpg`"}]}"; Reason = 'HTTP request failed' }
        )) {
            Test-Case $case.Name {
                Set-Response $case.Body
                $directory = Join-Path $testRoot ('failure-' + $script:passed)
                $result = Invoke-Shim @('randomwall', $case.Provider, '--no-apply', '--out', $directory)
                Assert-Failure $result $directory $case.Reason
            }
        }
        Test-Case 'failed download preserves existing wallpaper' {
            Set-Response "{`"backgrounds`": [{`"url`": `"$unreachable/image.jpg`"}]}"
            $directory = Join-Path $testRoot 'preserve'
            [IO.Directory]::CreateDirectory($directory) | Out-Null
            $path = Join-Path $directory 'random_wallpaper.jpg'
            [IO.File]::WriteAllText($path, 'existing wallpaper')
            $result = Invoke-Shim @('randomwall', 'osu', '--no-apply', '--out', $directory)
            Assert-True ($result.Code -ne 0) 'Expected non-zero exit'
            Assert-True ([IO.File]::ReadAllText($path) -eq 'existing wallpaper') 'Existing file was changed'
            Assert-True (@(Get-ChildItem -LiteralPath $directory -File).Count -eq 1) 'Temporary file was left'
        }
    } finally { $socket.Dispose() }
} finally {
    foreach ($name in $variables) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    # Only remove the unique directory created by this invocation.
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $temporary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($temporary, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Output "randomwall tests: $script:passed passed, $script:failed failed"
if ($script:failed -ne 0) { exit 1 }
