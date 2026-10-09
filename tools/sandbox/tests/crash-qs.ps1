# INSIDE the sandbox: the latest Windows error reports for quickshell.exe (faulting module, offset).
Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000} -MaxEvents 20 -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match 'quickshell' } | Select-Object -First 2 | ForEach-Object {
        "--- $($_.TimeCreated)"
        $_.Message -split "`n" | Where-Object { $_ -match 'Nombre|Name|Desplaz|offset|Offset|excep|Exception|módulo|module' } | ForEach-Object { $_.Trim() }
    }
