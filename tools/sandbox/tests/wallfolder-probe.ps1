# INSIDE the sandbox: is Pictures\Wallpapers there, with ii's wallpaper in it?
$d = [Environment]::GetFolderPath('MyPictures') + '\Wallpapers'
"folder: $d exists=$(Test-Path $d)"
Get-ChildItem $d -ErrorAction SilentlyContinue | Select-Object Name, Length | Format-Table -AutoSize | Out-String
