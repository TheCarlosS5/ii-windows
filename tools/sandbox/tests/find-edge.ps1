Get-ChildItem 'C:\Program Files (x86)\Microsoft', 'C:\Program Files\Microsoft' -Recurse -Filter msedge.exe -ErrorAction SilentlyContinue | Select-Object -First 3 FullName
Get-AppxPackage *Edge* | Select-Object Name, InstallLocation
Get-ChildItem C:\Windows\SystemApps -Directory | Select-Object -First 30 Name
