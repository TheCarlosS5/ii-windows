# R05 (PowerShell rescue): stops the shell/host of THIS installation, never a look-alike.
# The rescue runs with II_NO_UI=1 and an isolated II_DATA_DIR, so it only decides which processes
# to stop; it does not touch Explorer, the registry or the displays.
. "$PSScriptRoot\..\lib\ii-test.ps1"
. "$PSScriptRoot\..\lib\ii-host.ps1"
Require-IiHostBuild

$base = New-IiTestDir 'ii-rescueps'
$cleanup = @()
function Invoke-Rescue([string]$InstallDir, [string]$DataDir) {
    $script = Join-Path $InstallDir 'rescue\ii-rescue.ps1'
    $p = Start-IiProcess 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script) $DataDir
    [void]$p.WaitForExit(60000)
    $p.ExitCode
}
try {
    # An "installation": <inst>\rescue\ii-rescue.ps1, <inst>\quickshell\quickshell.exe
    $inst = Join-Path $base 'inst'
    New-Item -ItemType Directory -Force (Join-Path $inst 'rescue') | Out-Null
    Copy-Item (Join-Path $script:IiRepo 'tools\rescue\ii-rescue.ps1') (Join-Path $inst 'rescue\ii-rescue.ps1')
    $ours = New-IiFakeShell (Join-Path $inst 'quickshell')
    $decoy = New-IiFakeShell (Join-Path $base 'elsewhere')        # a quickshell.exe from another folder
    $cleanup += $ours; $cleanup += $decoy
    $data = Join-Path $base 'data'
    New-Item -ItemType Directory -Force $data | Out-Null

    # --- no record: only the executable under the installation folder goes --------------------
    $oursProc = Start-IiProcess $ours @('-p', 'hang') $data
    $decoyProc = Start-IiProcess $decoy @('-p', 'hang') $data
    Start-Sleep -Milliseconds 800
    Assert-Equal (Invoke-Rescue $inst $data) 0 'the rescue finishes'
    Start-Sleep -Milliseconds 500
    Assert-True $oursProc.HasExited 'the shell inside this installation was stopped'
    Assert-True (-not $decoyProc.HasExited) 'a quickshell.exe from another folder was left alone'

    # --- a record that is stale (right PID, wrong creation time) authorises nothing -------------
    $ini = "[instance]`r`nshellPid=$($decoyProc.Id)`r`nshellCreated=1`r`nshellPath=$decoy`r`n"
    [IO.File]::WriteAllText((Join-Path $data 'state.ini'), $ini, [Text.Encoding]::ASCII)
    Assert-Equal (Invoke-Rescue $inst $data) 0 'rescue with a stale record finishes'
    Assert-True (-not $decoyProc.HasExited) 'a reused PID with a stale record is not killed'
    Assert-True ((Get-Content (Join-Path $data 'host.log') -Raw) -match 'not running any more \(or its PID was reused\)') 'and the log says why'

    # --- a valid record is honoured even outside the installation folder -----------------------
    $created = (Get-Process -Id $decoyProc.Id).StartTime.ToFileTimeUtc()
    $ini = "[instance]`r`nshellPid=$($decoyProc.Id)`r`nshellCreated=$created`r`nshellPath=$decoy`r`n"
    [IO.File]::WriteAllText((Join-Path $data 'state.ini'), $ini, [Text.Encoding]::ASCII)
    Assert-Equal (Invoke-Rescue $inst $data) 0 'rescue with a valid record finishes'
    Start-Sleep -Milliseconds 500
    Assert-True $decoyProc.HasExited 'a process whose pid, creation time and path match the record is the supervised shell and is stopped'
}
finally {
    Stop-IiStragglers $cleanup
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
