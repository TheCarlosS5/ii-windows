$f = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\ii-windows\ii-windows.json"
"exists: $(Test-Path $f)"
$j = Get-Content $f -Raw | ConvertFrom-Json
"scheme: $($j.schemes[0].name) bg=$($j.schemes[0].background) fg=$($j.schemes[0].foreground) red=$($j.schemes[0].red) blue=$($j.schemes[0].blue) keys=$(@($j.schemes[0].PSObject.Properties).Count)"
