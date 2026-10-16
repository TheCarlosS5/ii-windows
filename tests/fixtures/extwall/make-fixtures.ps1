# Rebuilds the sample Wallpaper Engine / Lively folders `ii-shim extwall status` is tested with (no real install
# needed): small JSON files in the shape of the real ones, and two preview pictures with clearly different colours.
#   pwsh tests/fixtures/extwall/make-fixtures.ps1
$root = $PSScriptRoot
Add-Type -AssemblyName System.Drawing

function New-Picture($path, $c1, $c2, $format) {
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    $bmp = New-Object System.Drawing.Bitmap 320, 180
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush ([System.Drawing.Point]::new(0, 0)), ([System.Drawing.Point]::new(320, 180)), $c1, $c2
    $g.FillRectangle($brush, 0, 0, 320, 180)
    $g.Dispose(); $brush.Dispose()
    $bmp.Save($path, $format)
    $bmp.Dispose()
}
function Write-Json($path, $text) {
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))
}

# Wallpaper Engine: <install>\config.json -> selectedwallpapers -> project.json -> preview
$we = Join-Path $root 'we'
New-Picture "$we\projects\demo wallpaper\preview.jpg" ([System.Drawing.Color]::FromArgb(255, 20, 90, 200)) ([System.Drawing.Color]::FromArgb(255, 20, 170, 120)) ([System.Drawing.Imaging.ImageFormat]::Jpeg)
Write-Json "$we\projects\demo wallpaper\project.json" '{"title":"Atardecer de prueba","type":"Scene","preview":"preview.jpg","file":"scene.pkg"}'
Write-Json "$we\config.json" '{"SteamUser":{"general":{"language":"es"},"wallpaperconfig":{"selectedwallpapers":{"Monitor0":{"file":"projects/demo wallpaper/project.json","playlist":null}}}}}'

# Lively: <data>\WallpaperLayout.json -> LivelyInfo.json -> Thumbnail
$lively = Join-Path $root 'lively'
New-Picture "$lively\Library\wallpapers\demo\thumbnail.png" ([System.Drawing.Color]::FromArgb(255, 220, 90, 20)) ([System.Drawing.Color]::FromArgb(255, 160, 20, 60)) ([System.Drawing.Imaging.ImageFormat]::Png)
Write-Json "$lively\Library\wallpapers\demo\LivelyInfo.json" '{"AppVersion":"2.0.0.0","Title":"Olas de prueba","Type":1,"FileName":"index.html","Thumbnail":"thumbnail.png","Preview":"preview.gif"}'
Write-Json "$lively\WallpaperLayout.json" '[{"LivelyInfoFolderPath":"Library/wallpapers/demo","Arguments":null}]'
'fixtures written under ' + $root
