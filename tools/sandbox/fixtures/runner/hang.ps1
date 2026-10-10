# A child that outlives its parent unless the whole tree is killed. The marker lets the
# self-test find that child afterwards.
Start-Process -FilePath powershell.exe -ArgumentList '-NoProfile', '-Command', '$host.UI.RawUI.WindowTitle = "ii-runner-fixture-child"; Start-Sleep 600' -WindowStyle Hidden
Start-Sleep 600
