# Runs INSIDE Windows Sandbox. Executes every script dropped in C:\xchg\inbox (one at a time,
# in name order) and writes its transcript to C:\xchg\outbox\<name>.txt, then a <name>.done marker.
# The sandbox is disposable: closing it throws everything away.
$ErrorActionPreference = 'Continue'
$x = 'C:\xchg'
New-Item -ItemType Directory -Force "$x\inbox", "$x\outbox", "$x\done" | Out-Null
"agent started $(Get-Date -Format o) as $env:USERNAME on $([Environment]::OSVersion.VersionString)" | Set-Content "$x\outbox\_agent.txt"

while ($true) {
    Set-Content "$x\outbox\_heartbeat.txt" (Get-Date -Format o)
    $next = Get-ChildItem "$x\inbox\*.ps1" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1
    if ($next) {
        $name = $next.BaseName
        $run = "$x\done\$($next.Name)"
        Move-Item $next.FullName $run -Force
        $out = "$x\outbox\$name.txt"
        # The script's own exit code travels back in <name>.exit; a crash of the agent itself is -1.
        $code = -1
        try {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $run *>&1 | Out-File -Encoding utf8 $out
            $code = $LASTEXITCODE
        } catch {
            "AGENT ERROR: $_" | Out-File -Append -Encoding utf8 $out
        }
        Set-Content "$x\outbox\$name.exit" $code
        Set-Content "$x\outbox\$name.done" (Get-Date -Format o)
    }
    Start-Sleep -Milliseconds 700
}
