# INSIDE the sandbox: close leftover File Explorer windows from earlier tests.
(New-Object -ComObject Shell.Application).Windows() | ForEach-Object { $_.Quit() }
Start-Sleep 1
"explorer windows left: $(@((New-Object -ComObject Shell.Application).Windows()).Count)"
