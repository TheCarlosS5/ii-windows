# INSIDE the sandbox: which first-run condition keeps ii from showing its windows?
$dir = "$env:LOCALAPPDATA\Programs\ii-windows"
if (-not (Test-Path "$dir\quickshell\quickshell.exe")) { $dir = $null }
$dist = if ($dir) { "$dir\quickshell" } else { "$env:USERPROFILE\ii-dist" }
$cfg = if ($dir) { "$dir\ii" } else { "$env:USERPROFILE\qs-config" }
Get-Process ii-host, quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
Add-Type -Namespace FR -Name W -MemberDefinition '[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
public delegate bool EnumProc(IntPtr h, IntPtr l);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
public static int Count(uint pid) { int n = 0; EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) n++; return true; }, IntPtr.Zero); return n; }'

function Run($label, [scriptblock]$prepare) {
    Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
    Remove-Item "$env:LOCALAPPDATA\quickshell" -Recurse -Force -ErrorAction SilentlyContinue
    & $prepare
    $psi = New-Object System.Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
    $psi.Arguments = '-p "' + $cfg + '"'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $env:USERPROFILE
    $p = [System.Diagnostics.Process]::Start($psi)
    Start-Sleep 25
    $log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
    "$label -> visible windows: $([FR.W]::Count([uint32]$p.Id)), log lines: $((Get-Content $log.FullName).Count)"
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
}

Run 'D colors.json only' {
    New-Item -ItemType Directory -Force "$env:LOCALAPPDATA\quickshell\State\user" | Out-Null
    Set-Content "$env:LOCALAPPDATA\quickshell\State\user\first_run.txt" 'x'
    & "$dist\bin\switchwall.exe" --mode dark --image "$cfg\assets\images\default_wallpaper.png" | Out-Null
    Remove-Item "$env:LOCALAPPDATA\quickshell\illogical-impulse\config.json"
}
Run 'E config.json only' {
    New-Item -ItemType Directory -Force "$env:LOCALAPPDATA\quickshell\State\user" | Out-Null
    Set-Content "$env:LOCALAPPDATA\quickshell\State\user\first_run.txt" 'x'
    & "$dist\bin\switchwall.exe" --mode dark --image "$cfg\assets\images\default_wallpaper.png" | Out-Null
    Remove-Item "$env:LOCALAPPDATA\quickshell\State\user\generated\colors.json"
}
Run 'A real first run' { }
Run 'B first run skipped (first_run.txt present)' {
    New-Item -ItemType Directory -Force "$env:LOCALAPPDATA\quickshell\State\user" | Out-Null
    Set-Content "$env:LOCALAPPDATA\quickshell\State\user\first_run.txt" 'x'
}
Run 'C config + colors present, first run skipped' {
    New-Item -ItemType Directory -Force "$env:LOCALAPPDATA\quickshell\State\user" | Out-Null
    Set-Content "$env:LOCALAPPDATA\quickshell\State\user\first_run.txt" 'x'
    & "$dist\bin\switchwall.exe" --mode dark --image "$cfg\assets\images\default_wallpaper.png" | Out-Null
}
