# INSIDE the sandbox: the desktop layout (icons left, clock top right) and the Downloads widget.
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
# Saved positions from earlier runs would hide the new defaults.
$cfg = "$env:LOCALAPPDATA\quickshell\illogical-impulse\config.json"
if (Test-Path $cfg) {
    $json = Get-Content $cfg -Raw | ConvertFrom-Json
    if ($json.background -and $json.background.widgets) { $json.background.PSObject.Properties.Remove('widgets') }
    $json | ConvertTo-Json -Depth 32 | Set-Content $cfg -Encoding UTF8
}
$dl = "$env:USERPROFILE\Downloads"
New-Item -ItemType Directory -Force $dl | Out-Null
$i = 0
foreach ($name in 'factura-octubre.pdf', "Canci$([char]0xF3)n favorita.mp3", 'notas #1.txt', 'instalador.exe', 'captura.png') {
    $f = Join-Path $dl $name
    Set-Content $f "test $name"
    (Get-Item $f).LastWriteTime = (Get-Date).AddMinutes(-7 * $i - 2)
    $i++
}
New-Item -ItemType Directory -Force "$env:USERPROFILE\Desktop" | Out-Null
Set-Content "$env:USERPROFILE\Desktop\Mi documento.txt" 'hola'
$psi = New-Object System.Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $env:USERPROFILE
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 16
Get-Process explorer -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle } | ForEach-Object { $_.CloseMainWindow() | Out-Null }
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\folder-desktop.png" | Out-Null
Stop-Process -Id $p.Id -Force
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Where-Object { $_ -match 'Folder|folder|desktop|ERROR|ReferenceError|TypeError.*(Folder|Desktop)' } | Select-Object -Last 10
