# INSIDE the sandbox: ii-shim's Windows versions of Linux tools ii uses.
#   cliphist  (Windows clipboard history: list, copy, delete; ii's Win+V view)
#   ydotool   (on-screen keyboard: key codes and typed text reach the focused app)
#   secret-tool (API keys, DPAPI)
param([string]$Clicks = '')
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$bin = "$dist\bin"
$script:fails = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS $name $detail" } else { "FAIL $name $detail"; $script:fails++ } }

# --- clipboard history
New-Item -Force 'HKCU:\Software\Microsoft\Clipboard' | Out-Null
Set-ItemProperty 'HKCU:\Software\Microsoft\Clipboard' -Name EnableClipboardHistory -Value 1 -Type DWord
# Windows' clipboard service reads the setting when it starts (Settings notifies it; we restart it).
Get-Service cbdhsvc_* -ErrorAction SilentlyContinue | Restart-Service -Force -ErrorAction SilentlyContinue
Start-Sleep 3
& "$bin\cliphist.exe" enabled; Check 'clipboard history on' ($LASTEXITCODE -eq 0)
foreach ($t in 'primero ñandú', 'segundo', "tercero`ncon dos líneas") { Set-Clipboard -Value $t; Start-Sleep -Milliseconds 900 }
$list = @(& "$bin\cliphist.exe" list)
"list: $($list -join ' | ')"
Check 'cliphist list shows the copies, newest first' ($list.Count -ge 3 -and $list[0] -match "^\d+`ttercero con dos líneas" -and $list[2] -match 'primero ñandú')
& "$bin\cliphist.exe" copy $list[2]
Start-Sleep 1
Check 'cliphist copy makes an old entry the clipboard' ((Get-Clipboard) -eq 'primero ñandú') "($(Get-Clipboard))"
$list = @(& "$bin\cliphist.exe" list)
$before = $list.Count
$segundo = $list | Where-Object { $_ -match "`tsegundo$" } | Select-Object -First 1
& "$bin\cliphist.exe" delete-id $segundo
Start-Sleep 1
Check 'cliphist delete removes it' (@(& "$bin\cliphist.exe" list | Where-Object { $_ -match "`tsegundo$" }).Count -eq 0)

# ii's clipboard view (Win+V).
$psi = New-Object Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$p = [Diagnostics.Process]::Start($psi)
Start-Sleep 14
& "$dev\send-shortcut.ps1" -Name overviewClipboardToggle | Out-Null
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\tools-1-clipboard.png" | Out-Null
& "$dev\send-shortcut.ps1" -Name overviewClipboardToggle | Out-Null
Start-Sleep 1

# --- ydotool into a real text box
$form = Start-Process powershell -PassThru -ArgumentList '-NoProfile', '-Command', @'
Add-Type -AssemblyName System.Windows.Forms
$f = New-Object Windows.Forms.Form; $f.Text = 'ydotool-target'; $f.TopMost = $true
$tb = New-Object Windows.Forms.TextBox; $tb.Dock = 'Fill'; $tb.Multiline = $true; $f.Controls.Add($tb)
$f.Add_Shown({ $f.Activate(); $tb.Focus() })
$t = New-Object Windows.Forms.Timer; $t.Interval = 300
$t.Add_Tick({ Set-Content 'C:\xchg\outbox\ydotool-text.txt' $tb.Text -Encoding UTF8 })
$t.Start(); [void]$f.ShowDialog()
'@
Start-Sleep 4
Add-Type -Namespace YT -Name W -MemberDefinition '[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern System.IntPtr FindWindow(string c, string t); [DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr h);'
[void][YT.W]::SetForegroundWindow([YT.W]::FindWindow([NullString]::Value, 'ydotool-target'))
Start-Sleep 1
& "$bin\ydotool.exe" key --key-delay 0 42:1 30:1 30:0 42:0 46:1 46:0 57:1 57:0   # Shift+a c space -> "Ac "
$word = "ñandú ok"
& "$bin\ydotool.exe" type $word
& "$bin\ydotool.exe" key --key-delay 0 14:1 14:0 14:1 14:0                       # two backspaces
Start-Sleep 1
$typed = (Get-Content "$out\ydotool-text.txt" -Raw -Encoding UTF8).Trim()
Check 'ydotool keys and text reach the app' ($typed -eq ('Ac ' + $word.Substring(0, $word.Length - 2)).Trim()) "('$typed')"
# Releasing all keys (as ii does) must not leave anything pressed or open Start.
& "$bin\ydotool.exe" key --key-delay 0 @(0..248 | ForEach-Object { "${_}:0" })
Start-Sleep 1
Add-Type -Namespace YT2 -Name W -MemberDefinition '[DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk); [DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow(); [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(System.IntPtr h, System.Text.StringBuilder s, int n);'
$sb = New-Object Text.StringBuilder 100; [void][YT2.W]::GetClassNameW([YT2.W]::GetForegroundWindow(), $sb, 100)
Check 'release-all leaves Start closed' ($sb.ToString() -notmatch 'Windows.UI.Core.CoreWindow') "(fg=$sb)"
$form | Stop-Process -Force -ErrorAction SilentlyContinue

# --- secret-tool
'{"k":"v"}' | & "$bin\secret-tool.exe" store --label=x application ii-test
Check 'secret-tool round trip' ((& "$bin\secret-tool.exe" lookup application ii-test) -eq '{"k":"v"}')
& "$bin\secret-tool.exe" lookup application nothing-here; Check 'secret-tool missing entry exits 1' ($LASTEXITCODE -eq 1)

$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Select-String 'Cliphist|Keyring|cliphist' | ForEach-Object { $_.Line.Substring([Math]::Min(11, $_.Line.Length)) } | Select-Object -Last 8
Stop-Process -Id $p.Id -Force
"fails: $script:fails"
