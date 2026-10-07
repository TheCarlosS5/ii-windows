Add-Type -Namespace D -Name W -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern System.IntPtr FindWindowEx(System.IntPtr p, System.IntPtr a, string c, string t);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);
[DllImport("user32.dll")] public static extern System.IntPtr GetParent(System.IntPtr h);
'@
$pm = [D.W]::FindWindowEx(0, 0, 'Progman', $null); "progman $pm"
$dv = [D.W]::FindWindowEx($pm, 0, 'SHELLDLL_DefView', $null); "defview under progman: $dv visible=$([D.W]::IsWindowVisible($dv))"
$h = [IntPtr]::Zero
while (($h = [D.W]::FindWindowEx([IntPtr]::Zero, $h, 'WorkerW', $null)) -ne [IntPtr]::Zero) { $d = [D.W]::FindWindowEx($h, 0, 'SHELLDLL_DefView', $null); if ($d -ne 0) { "defview under workerw $h : $d" } }
$c = [D.W]::FindWindowEx($pm, 0, $null, $null); while ($c -ne [IntPtr]::Zero) { "progman child $c"; $c = [D.W]::FindWindowEx($pm, $c, $null, $null) }
if ($dv -ne 0) { $lv = [D.W]::FindWindowEx($dv, 0, 'SysListView32', $null); "listview $lv visible=$([D.W]::IsWindowVisible($lv))" }
'--- rescue again'
& powershell -NoProfile -ExecutionPolicy Bypass -File C:\ii\tools\rescue\ii-rescue.ps1
if ($dv -ne 0) { "listview visible now=$([D.W]::IsWindowVisible($lv))" }
