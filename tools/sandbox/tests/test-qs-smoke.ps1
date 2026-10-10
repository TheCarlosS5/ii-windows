# Smoke test of the Windows-specific QML types of the quickshell-windows fork, with the real
# quickshell.exe built from this tree (preset windows-release). It starts the shell on a tiny config
# that only READS: WlSessionLock (state/secure from the real session; it never sets `locked`, so
# nothing is locked) and MonotonicClock (never goes back, tracks the wall clock, counts through sleep).
# No panel windows are created, so nothing appears on screen and nothing is reserved.
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$exe = @("$repo\quickshell\build\quickshell.exe", "$repo\quickshell\build-r\quickshell.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exe) { Skip-Test 'quickshell.exe not built (cmake --preset windows-release -S quickshell ...)' }
$windeployqt = @("$env:USERPROFILE\dev\Qt\bin\windeployqt.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $windeployqt) { Skip-Test 'windeployqt not found (Qt bin folder): needed to put the Qt runtime next to quickshell.exe' }

$base = Join-Path $env:TEMP ('ii-qs-smoke-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$cfg = Join-Path $base 'cfg'
$dist = Join-Path $base 'qs'
New-Item -ItemType Directory -Force $cfg, $dist | Out-Null
$proc = $null
$cacheId = $null
try {
    Set-Content (Join-Path $cfg 'shell.qml') @'
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Win32

ShellRoot {
    WlSessionLock {
        id: lock
        Component.onCompleted: console.log("SMOKE lock secure=" + lock.secure + " state=" + lock.state + " locked=" + lock.locked + " error='" + lock.lastError + "'")
    }
    Timer {
        interval: 700
        running: true
        property real mono0: MonotonicClock.nowMs()
        property real wall0: Date.now()
        property real last: MonotonicClock.nowMs()
        property bool monotonic: true
        property int samples: 0
        repeat: true
        onTriggered: {
            const now = MonotonicClock.nowMs();
            if (now < last) monotonic = false;
            last = now;
            samples++;
            if (samples === 4) {
                const monoDelta = now - mono0, wallDelta = Date.now() - wall0;
                console.log("SMOKE clock monotonic=" + monotonic + " includesSleep=" + MonotonicClock.includesSleep() + " monoDelta=" + Math.round(monoDelta) + " wallDelta=" + Math.round(wallDelta) + " skew=" + Math.round(Math.abs(monoDelta - wallDelta)));
            }
        }
    }
}
'@
    Copy-Item $exe $dist
    & $windeployqt --release --no-compiler-runtime --no-translations --qmldir $cfg (Join-Path $dist 'quickshell.exe') *> $null

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $dist 'quickshell.exe'
    $psi.Arguments = "-p `"$cfg`""
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['QT_FORCE_STDERR_LOGGING'] = '1'
    $lines = New-Object System.Collections.Concurrent.ConcurrentQueue[string]
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $handler = { if ($EventArgs.Data) { $Event.MessageData.Enqueue($EventArgs.Data) } }
    $e1 = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $handler -MessageData $lines
    $e2 = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action $handler -MessageData $lines
    [void]$proc.Start(); $proc.BeginOutputReadLine(); $proc.BeginErrorReadLine()

    $sw = [Diagnostics.Stopwatch]::StartNew(); $all = ''
    while ($sw.Elapsed.TotalSeconds -lt 45) {
        $l = $null; while ($lines.TryDequeue([ref]$l)) { $all += $l + "`n" }
        if ($all -match 'SMOKE clock') { break }
        Start-Sleep -Milliseconds 200
    }
    Unregister-Event -SourceIdentifier $e1.Name -ErrorAction SilentlyContinue; Unregister-Event -SourceIdentifier $e2.Name -ErrorAction SilentlyContinue
    if ($all -match 'cache/by-shell/([0-9a-f]+)/') { $cacheId = $Matches[1] }

    Assert-True ($all -match 'SMOKE lock secure=false state=unlocked locked=false error=''''') 'WlSessionLock reads the real session: unlocked, not secure, nothing requested'
    Assert-True ($all -match 'SMOKE clock monotonic=true') 'the monotonic clock never went back'
    Assert-True ($all -match 'includesSleep=true') 'and it is QueryInterruptTime (counts through sleep)'
    $skew = [int]([regex]::Match($all, 'skew=(\d+)').Groups[1].Value)
    Assert-True ($skew -lt 150) "and it tracks the wall clock over ~2 s (difference $skew ms)"
}
finally {
    if ($proc -and -not $proc.HasExited) { try { $proc.Kill() } catch {} }
    Start-Sleep -Milliseconds 500
    # Quickshell keeps a compiled-QML cache per config under the user's cache folder: remove the one this
    # throwaway config created (its id is in the log) and no other.
    if ($cacheId -and $cacheId -match '^[0-9a-f]{32}$') {
        $dir = Join-Path $env:LOCALAPPDATA "quickshell\cache\by-shell\$cacheId"
        if (Test-Path $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
