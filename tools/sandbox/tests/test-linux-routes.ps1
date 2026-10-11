# B00/C12: the Linux commands the staged QML still starts, by who answers them on Windows
# (tools/dev/scan-linux-routes.py; docs/INVENTARIO-RUTAS-LINUX.md is the human-readable result).
# The point is to notice a NEW command with no provider appearing (a patch, a new upstream commit):
# the only ones with no provider today are listed here with the reason they are still there.
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if (-not (Test-Path (Join-Path $repo 'upstream\dots\.config\quickshell\ii'))) { Skip-Test 'upstream checkout missing' }
$dest = Join-Path $env:TEMP ('ii-routes-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\dev\stage-ii.ps1') -Dest $dest | Out-Null
    Assert-Equal $LASTEXITCODE 0 'staging works'
    $json = Join-Path $dest 'routes.json'
    & python -I (Join-Path $repo 'tools\dev\scan-linux-routes.py') $dest --json $json | Out-Null
    $routes = Get-Content $json -Raw | ConvertFrom-Json
    $names = @($routes.PSObject.Properties.Name)
    Assert-True ($names.Count -gt 15) "the scan found $($names.Count) distinct commands"

    # No provider on a stock Windows. Each stays until its task replaces it.
    $knownUnbacked = @{
        'file'     = 'AI chat attachments and folder icons (C08 / P08): MIME sniffing is not available yet'
        'identify' = 'AI chat attachments (C08): image dimensions'
        'hyprctl'  = 'the game-mode quick toggle (U05): Hyprland animation switch with no Windows meaning'
    }
    $unbacked = @($names | Where-Object { $routes.$_.class -eq 'unbacked' })
    $unexpected = @($unbacked | Where-Object { -not $knownUnbacked.ContainsKey($_) })
    Assert-True ($unexpected.Count -eq 0) ("no new Linux command without a provider" + $(if ($unexpected.Count) { ": $($unexpected -join ', ') (add a provider to ii-shim, or list it here with its task)" } else { '' }))

    # What C12 removed must stay removed.
    Assert-True ($names -notcontains 'find') 'find is no longer started (the language list is read by Qt)'
    $hypr = $routes.hyprctl
    Assert-True ($hypr.sites.Count -eq 1 -and $hypr.sites[0] -like '*GameMode.qml*') 'the sidebar pin no longer calls hyprctl (only the game-mode toggle does)'
    foreach ($provided in 'mkdir', 'rm', 'which') {
        if ($routes.PSObject.Properties.Name -contains $provided) { Assert-Equal $routes.$provided.class 'shim' "$provided is answered by ii-shim" }
    }
}
finally {
    Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
