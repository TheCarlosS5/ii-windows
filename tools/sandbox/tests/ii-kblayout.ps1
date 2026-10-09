# INSIDE the sandbox: with two input languages installed, ii's bar shows the layout of the app in
# front, and follows a switch (Win+Space).
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$langs = Get-WinUserLanguageList
if (-not ($langs | Where-Object LanguageTag -eq 'en-US')) { $langs.Add('en-US'); Set-WinUserLanguageList $langs -Force }
"languages: $((Get-WinUserLanguageList).LanguageTag -join ', ')"
# New languages load at the next sign-in; load the US layout into this session now.
Add-Type -Namespace KB -Name W -MemberDefinition '[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern System.IntPtr LoadKeyboardLayout(string id, uint flags); [DllImport("user32.dll")] public static extern int GetKeyboardLayoutList(int n, System.IntPtr[] l);'
[void][KB.W]::LoadKeyboardLayout('00000409', 0)
"session layouts: $([KB.W]::GetKeyboardLayoutList(0, $null))"
$psi = New-Object Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$p = [Diagnostics.Process]::Start($psi)
Start-Sleep 14
Start-Process explorer.exe C:\
Start-Sleep 3
& "$dev\screenshot.ps1" -Out "$out\kb-1.png" -X 760 -W 760 -H 40 | Out-Null
# Next layout for the window in front: Alt+Shift (Windows' language hotkey).
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait('%+')
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\kb-2.png" -X 760 -W 760 -H 40 | Out-Null
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Select-String 'Xkb|KeyboardLayouts' | Select-Object -Last 5 | ForEach-Object { $_.Line }
(New-Object -ComObject Shell.Application).Windows() | ForEach-Object { $_.Quit() }
Stop-Process -Id $p.Id -Force
