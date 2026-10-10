# R11: the problem report (ii-report.ps1) carries no credentials, no notification/chat text and no
# identity unless asked with -IncludePrivate. Sentinel strings go into fake host and shell logs; the
# report is produced from those folders only. Nothing from the real logs or the real Desktop is read
# or written.
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$report = Join-Path $repo 'tools\rescue\ii-report.ps1'

$base = Join-Path $env:TEMP ('ii-report-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$data = Join-Path $base 'data'
$qs = Join-Path $base 'qs\by-id\abc'
New-Item -ItemType Directory -Force $data, $qs | Out-Null
try {
    $user = $env:USERNAME
    Set-Content (Join-Path $data 'host.log') @"
2026-10-10 10:00:00.000 [1] shell: started pid 4242
2026-10-10 10:00:01.000 [1] request header Authorization: Bearer SENTINEL-BEARER-1234567890
2026-10-10 10:00:02.000 [1] config "apiKey": "SENTINEL-APIKEY-ABCDEF"
2026-10-10 10:00:03.000 [1] GET https://gelbooru.example/index.php?api_key=SENTINEL-GELBOORU-KEY&user_id=424242&tags=cat
2026-10-10 10:00:04.000 [1] using sk-SENTINELOPENAIKEY1234567890abcd for the chat
2026-10-10 10:00:05.000 [1] profile path C:\Users\$user\AppData\Local\thing
"@
    Set-Content (Join-Path $qs 'log.log') @"
  INFO quickshell.win32.notifications: Notification 7 from Signal : SENTINEL-PRIVATE-MESSAGE see you at 9
  INFO quickshell.win32.notifications: Notification 8 from Mail
 DEBUG qml: [Ai] message: SENTINEL-CHAT-TEXT how do I hide my taskbar
  INFO: Configuration Loaded
"@

    $out = Join-Path $base 'report.txt'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $report -NoBrowser -DataDir $data -QsLogDir (Join-Path $base 'qs') -OutFile $out | Out-Null
    Assert-Equal $LASTEXITCODE 0 'the report script ran'
    $text = Get-Content $out -Raw
    Assert-True ($text -match 'shell: started pid 4242') 'ordinary diagnostic lines are kept'
    Assert-True ($text -match 'Notification 8 from Mail') 'a notification line without text is kept (who, not what)'
    Assert-True ($text -match 'Configuration Loaded') 'and so is the rest of the shell log'
    foreach ($sentinel in 'SENTINEL-BEARER', 'SENTINEL-APIKEY', 'SENTINEL-GELBOORU-KEY', 'SENTINELOPENAIKEY', 'SENTINEL-PRIVATE-MESSAGE', 'SENTINEL-CHAT-TEXT', 'see you at 9', 'hide my taskbar') {
        Assert-True (-not $text.Contains($sentinel)) "not in the report: $sentinel"
    }
    Assert-True (-not ($text -match [regex]::Escape($user))) 'the Windows user name is not in the report'
    Assert-True ($text -match '<redacted') 'redactions are visible as such'

    # Asking for everything brings it back, and only then.
    $outPrivate = Join-Path $base 'report-private.txt'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $report -NoBrowser -DataDir $data -QsLogDir (Join-Path $base 'qs') -OutFile $outPrivate -IncludePrivate | Out-Null
    $textPrivate = Get-Content $outPrivate -Raw
    Assert-True ($textPrivate.Contains('SENTINEL-PRIVATE-MESSAGE') -and $textPrivate.Contains('SENTINEL-GELBOORU-KEY')) '-IncludePrivate keeps the private text'
    Assert-True (-not ($textPrivate -match [regex]::Escape($user))) 'but the user name is still scrubbed'
}
finally {
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
