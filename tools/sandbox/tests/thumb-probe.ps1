# INSIDE the sandbox: did ThumbnailImage produce thumbnails, and does ii-shim thumbnail work?
$dist = "$env:USERPROFILE\ii-dist"
"cache dir listing:"; Get-ChildItem "$env:LOCALAPPDATA\cache\thumbnails" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 6 | ForEach-Object { "  $($_.FullName) $($_.Length)" }
$src = "$env:USERPROFILE\Pictures\Wallpapers\sunset.png"
$dst = "$env:TEMP\thumb-test\t.png"
Remove-Item $dst -ErrorAction SilentlyContinue
& "$dist\bin\ii-shim.exe" thumbnail ($src.Replace('\','/')) 256 ($dst.Replace('\','/')); "first exit $LASTEXITCODE"
& "$dist\bin\ii-shim.exe" thumbnail ($src.Replace('\','/')) 256 ($dst.Replace('\','/')); "second exit $LASTEXITCODE"
if (Test-Path $dst) { Add-Type -AssemblyName System.Drawing; $i = [System.Drawing.Image]::FromFile($dst); "thumb $($i.Width)x$($i.Height)"; $i.Dispose() }
& "$dist\bin\magick.exe" identify -format "%w %h" ($src.Replace('\','/')); ""
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Where-Object { $_ -match 'thumbnail|Process failed' } | Select-Object -Last 5
