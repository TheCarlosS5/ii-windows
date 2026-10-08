# INSIDE the sandbox: native switchwall vs the Python generator's palette for the same wallpaper.
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$wall = "$env:USERPROFILE\Pictures\ii-wallpaper.jpg"
$colors = "$env:LOCALAPPDATA\quickshell\State\user\generated\colors.json"
$cfg = "$env:LOCALAPPDATA\quickshell\illogical-impulse\config.json"
"wallpaper exists: $(Test-Path $wall)"
$t = Measure-Command { $out = & "$dist\bin\switchwall.exe" --mode dark --type scheme-tonal-spot --image $wall }
"switchwall: $out ($([int]$t.TotalMilliseconds) ms, exit $LASTEXITCODE)"
$mine = Get-Content $colors -Raw | ConvertFrom-Json
$ref = Get-Content C:\xchg\seed-colors.json -Raw | ConvertFrom-Json
$diff = 0; $same = 0
foreach ($p in $ref.PSObject.Properties) {
    if ($mine.($p.Name) -eq $p.Value) { $same++ } else { $diff++; if ($diff -le 8) { "  differs: $($p.Name) native=$($mine.($p.Name)) python=$($p.Value)" } }
}
"same: $same  different: $diff  keys: $(@($mine.PSObject.Properties).Count)"
"config wallpaperPath: $((Get-Content $cfg -Raw | ConvertFrom-Json).background.wallpaperPath)"
"--- auto / light / noswitch"
& "$dist\bin\switchwall.exe" --image $wall --mode light
& "$dist\bin\switchwall.exe" --noswitch --mode dark
"--- via the restricted bash, as ii's toggles call it"
& "$dist\bin\bash.exe" -c "switchwall --mode light --noswitch"; "bash exit $LASTEXITCODE"
