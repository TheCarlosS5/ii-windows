# INSIDE the sandbox: ii-host's watchdog. A shell that freezes while loading (no wallpaper in
# 45 s) or after loading (windows not responding for 20 s) is replaced by a new one. Freezing is
# simulated by suspending the quickshell process.
$out = 'C:\xchg\outbox'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$hostDir = "$env:USERPROFILE\ii-hostbin"
New-Item -ItemType Directory -Force $hostDir | Out-Null
Copy-Item C:\ii\host\build\ii-host.exe $hostDir -Force
$script:fails = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS $name $detail" } else { "FAIL $name $detail"; $script:fails++ } }
Add-Type -Namespace WD -Name N -MemberDefinition '[DllImport("ntdll.dll")] public static extern int NtSuspendProcess(System.IntPtr h);'
# The shell ii-host started (not the welcome screen, also a quickshell process): its last log line.
function Shell {
    $line = Get-Content $hostLog -ErrorAction SilentlyContinue | Select-String 'shell: started pid (\d+)' | Select-Object -Last 1
    if ($line) { Get-Process -Id ([int]$line.Matches[0].Groups[1].Value) -ErrorAction SilentlyContinue }
}
$hostLog = "$env:LOCALAPPDATA\ii-windows\host.log"
$logStart = if (Test-Path $hostLog) { (Get-Content $hostLog).Count } else { 0 }

Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
# 1. Frozen while loading: suspend it right away.
$first = $null
for ($i = 0; $i -lt 40 -and -not $first; $i++) { Start-Sleep -Milliseconds 100; $first = Shell }
[void][WD.N]::NtSuspendProcess($first.Handle)
"suspended loading shell $($first.Id)"
Start-Sleep 105
$second = Shell
Check 'frozen while loading: replaced within ~95 s' ($second -and $second.Id -ne $first.Id) "($($first.Id) -> $($second.Id))"
Start-Sleep 20
Check 'new shell got ready' ((Get-Content $hostLog | Select-Object -Skip $logStart | Select-String 'shell: ready after').Count -ge 1)

# 2. Frozen after loading: suspend the ready shell.
[void][WD.N]::NtSuspendProcess($second.Handle)
"suspended ready shell $($second.Id)"
Start-Sleep 40
$third = Shell
Check 'frozen after loading: replaced within ~30 s' ($third -and $third.Id -ne $second.Id) "($($second.Id) -> $($third.Id))"
Get-Content $hostLog | Select-Object -Skip $logStart | Select-String 'shell:' | ForEach-Object { $_.Line }
Get-Process quickshell -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $third.Id } | Stop-Process -Force -ErrorAction SilentlyContinue
& "$hostDir\ii-host.exe" --rescue
"fails: $script:fails"
