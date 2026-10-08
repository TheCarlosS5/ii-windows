# INSIDE the sandbox: what is left of the install folder after uninstalling, and why.
$dir = "$env:LOCALAPPDATA\Programs\ii-windows"
"left: $((Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue).Count) files"
Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 5 | ForEach-Object { "  $($_.FullName)" }
"cleanup script still there: $(Test-Path "$env:TEMP\ii-windows-cleanup.cmd")"
if (Test-Path "$env:TEMP\ii-windows-cleanup.cmd") { Get-Content "$env:TEMP\ii-windows-cleanup.cmd" }
"processes using it:"; Get-Process | Where-Object { $_.Path -like "$dir*" } | ForEach-Object { "  $($_.Name) $($_.Id)" }
cmd /c "rmdir /s /q `"$dir`"" 2>&1
"after manual rmdir: exists=$(Test-Path $dir)"
