# R06: the logon task is owned per user. Uses the real Task Scheduler, but only inside a throwaway
# folder (\ii-windows-test\<guid>\); the real \ii-windows task and folder are never touched. The tasks
# have a logon trigger and are never started. "Another user" is simulated by a task with another
# SID's marker; a second real account is needed to prove it end to end (see the log entry).
. "$PSScriptRoot\..\lib\ii-test.ps1"
. "$PSScriptRoot\..\..\package\ii-autostart.ps1"

$sid = Get-IiUserSid
$user = "$env:USERDOMAIN\$env:USERNAME"
$run = [guid]::NewGuid().ToString('N').Substring(0, 8)
$folder = "\ii-windows-test\$run\"
$legacyFolder = "\ii-windows-test\$run-legacy\"
$nestParent = "\ii-windows-test\$run-c\"
$nestFolder = "\ii-windows-test\$run-c\nest\"
$install = "C:\Users\Prüfung ü\AppData\Local\Programs\ii-windows"      # non-ASCII profile path, never created
$hostExe = "$install\ii-host.exe"
$args1 = "--boot --shell `"$install\quickshell\quickshell.exe`" --config `"$install\ii`""

# Through COM like ii-autostart.ps1 (Get-ScheduledTask fails for every task when one of the PC is broken).
function Get-Tasks([string]$Path) {
    $f = Get-IiTaskFolderObject $Path
    if (-not $f) { return @() }
    @($f.GetTasks(1) | ForEach-Object { [pscustomobject]@{ TaskName = $_.Name } })
}
function New-FakeTask([string]$Path, [string]$Name, [string]$Description, [string]$Exe, [string]$Account = $user) {
    $a = New-ScheduledTaskAction -Execute $Exe
    $t = New-ScheduledTaskTrigger -AtLogOn -User $Account
    $p = New-ScheduledTaskPrincipal -UserId $Account -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $Name -TaskPath $Path -Action $a -Trigger $t -Principal $p -Description $Description -ErrorAction Stop | Out-Null
}

try {
    # --- install -------------------------------------------------------------------------------
    $r = Install-IiAutostart -Sid $sid -User $user -HostExe $hostExe -Arguments $args1 -InstallDir $install -Version '1.0' `
        -TaskPath $folder -LegacyTaskPath $legacyFolder -LegacyTaskName 'ii-windows'
    Assert-True ($r.Registered -and -not $r.Migrated -and $r.Conflicts.Count -eq 0) 'installing registers the task, with nothing to migrate or report'
    $task = Get-IiLogonTask $folder "Logon-$sid"
    Assert-True ($null -ne $task) 'the task is named after the SID and lives in its own folder'
    Assert-True ($task.Description.Contains((Get-IiOwnerMarker $sid))) 'it says whose it is'
    Assert-Equal ([string]$task.Principal.RunLevel) 'Limited' 'it runs without elevation'
    Assert-Equal ([string]@($task.Triggers)[0].Kind) 'Logon' 'it triggers at logon'
    Assert-Equal @($task.Actions)[0].Execute $hostExe 'it starts ii-host from the install folder (non-ASCII path kept)'
    Assert-Equal ([string]$task.Settings.MultipleInstances) 'IgnoreNew' 'one instance at most'

    # --- upgrade: the same task is updated, not duplicated -----------------------------------------
    $r = Install-IiAutostart -Sid $sid -User $user -HostExe $hostExe -Arguments $args1 -InstallDir $install -Version '2.0' `
        -TaskPath $folder -LegacyTaskPath $legacyFolder -LegacyTaskName 'ii-windows'
    Assert-True $r.Registered 'a second install registers again'
    Assert-Equal @(Get-Tasks $folder).Count 1 'still exactly one task of ours'
    Assert-True ((Get-IiLogonTask $folder "Logon-$sid").Description -match 'version:2\.0') 'and it now carries the new version'

    # --- another user's task is left alone, on install and on remove ---------------------------------
    $otherSid = 'S-1-5-21-1111111111-2222222222-3333333333-1001'
    New-FakeTask $folder "Logon-$otherSid" "ii-windows [ii-windows-owner:$otherSid]" "C:\Users\Other\ii-host.exe"
    $r = Install-IiAutostart -Sid $sid -User $user -HostExe $hostExe -Arguments $args1 -InstallDir $install -Version '2.1' `
        -TaskPath $folder -LegacyTaskPath $legacyFolder -LegacyTaskName 'ii-windows'
    Assert-True ($null -ne (Get-IiLogonTask $folder "Logon-$otherSid")) "the other user's task survived our install"
    Assert-Equal (Get-IiLogonTask $folder "Logon-$otherSid").Actions[0].Execute 'C:\Users\Other\ii-host.exe' "and was not modified"

    # --- a task that has our name but not our marker is a conflict, not something to overwrite -------
    $squat = 'S-1-5-21-9999999999-9999999999-9999999999-500'
    New-FakeTask $folder "Logon-$squat" 'someone else made this' 'C:\evil.exe'
    $squatResult = Install-IiAutostart -Sid $squat -User $user -HostExe $hostExe -Arguments $args1 -InstallDir $install `
        -TaskPath $folder -LegacyTaskPath $legacyFolder -LegacyTaskName 'ii-windows'
    Assert-True (-not $squatResult.Registered -and $squatResult.Conflicts.Count -eq 1) 'a same-name task without the owner marker is reported, not replaced'
    Assert-Equal (Get-IiLogonTask $folder "Logon-$squat").Actions[0].Execute 'C:\evil.exe' 'and kept exactly as it was'

    # --- the old flat task ----------------------------------------------------------------------
    New-FakeTask $legacyFolder 'ii-windows' 'old ii task' $hostExe                  # ours: our account, inside our install
    $r = Install-IiAutostart -Sid $sid -User $user -HostExe $hostExe -Arguments $args1 -InstallDir $install `
        -TaskPath $folder -LegacyTaskPath $legacyFolder -LegacyTaskName 'ii-windows'
    Assert-True $r.Migrated 'a provably-ours old task is migrated'
    Assert-Equal @(Get-Tasks $legacyFolder).Count 0 'and gone'
    New-FakeTask $legacyFolder 'ii-windows' 'someone elses' 'D:\other\ii-host.exe'  # same name, another installation
    $r = Install-IiAutostart -Sid $sid -User $user -HostExe $hostExe -Arguments $args1 -InstallDir $install `
        -TaskPath $folder -LegacyTaskPath $legacyFolder -LegacyTaskName 'ii-windows'
    Assert-True (-not $r.Migrated -and $r.Conflicts.Count -eq 1) 'an old task from another installation is not migrated, and the conflict is explained'
    Assert-Equal @(Get-Tasks $legacyFolder).Count 1 'it is still there'

    # --- the old flat task named like the new folder (\ii-windows and \ii-windows\ on real PCs) -----------------
    # Registering the folder first and removing the old task after broke the Task Scheduler of PCs that came from
    # 0.1.x: the new task could not be loaded and Get-ScheduledTask failed for every task.
    New-FakeTask $nestParent 'nest' 'old ii task' $hostExe
    $r = Install-IiAutostart -Sid $sid -User $user -HostExe $hostExe -Arguments $args1 -InstallDir $install `
        -TaskPath $nestFolder -LegacyTaskPath $nestParent -LegacyTaskName 'nest'
    Assert-True ($r.Registered -and $r.Migrated -and $r.Conflicts.Count -eq 0) "an old task with the new folder's name goes first, then the new one is registered ($($r.Conflicts -join ' '))"
    Assert-True ($null -eq (Get-IiLogonTask $nestParent 'nest')) 'the old one is gone'
    Assert-True ($null -ne (Get-IiLogonTask $nestFolder "Logon-$sid")) 'the new one can be read'
    & schtasks.exe /query /tn "$($nestFolder)Logon-$sid" 2>&1 | Out-Null
    Assert-Equal $LASTEXITCODE 0 'and Windows can load it'
    Remove-IiLogonTask $nestFolder "Logon-$sid"
    (Get-IiTaskFolderObject $nestParent).DeleteFolder('nest', 0)
    New-FakeTask $nestParent 'nest' 'someone elses' 'D:\other\ii-host.exe'
    $r = Install-IiAutostart -Sid $sid -User $user -HostExe $hostExe -Arguments $args1 -InstallDir $install `
        -TaskPath $nestFolder -LegacyTaskPath $nestParent -LegacyTaskName 'nest'
    Assert-True (-not $r.Registered -and $r.Conflicts.Count -eq 1) "another installation's old task with the folder's name is reported, and nothing is registered over it"
    Assert-Equal (Get-IiLogonTask $nestParent 'nest').Actions[0].Execute 'D:\other\ii-host.exe' 'it is kept as it was'

    # --- remove: exactly ours ---------------------------------------------------------------------
    $rm = Remove-IiAutostart -Sid $sid -InstallDir $install -TaskPath $folder -LegacyTaskPath $legacyFolder -LegacyTaskName 'ii-windows'
    Assert-True ($rm.Removed.Count -eq 1 -and $rm.Removed[0] -eq "$folder" + "Logon-$sid") 'uninstall removes only our task'
    Assert-True ($null -eq (Get-IiLogonTask $folder "Logon-$sid")) 'it is gone'
    Assert-True ($null -ne (Get-IiLogonTask $folder "Logon-$otherSid")) "the other user's task is still there"
    Assert-True ($null -ne (Get-IiLogonTask $folder "Logon-$squat")) 'the squatter is still there'
    Assert-Equal @(Get-Tasks $legacyFolder).Count 1 "and the other installation's old task too"
    $again = Remove-IiAutostart -Sid $sid -InstallDir $install -TaskPath $folder -LegacyTaskPath $legacyFolder -LegacyTaskName 'ii-windows'
    Assert-Equal $again.Removed.Count 0 'removing twice is harmless'

    # --- the real task is not part of any of this -------------------------------------------------
    Assert-True ($folder -ne $script:IiTaskFolder -and $legacyFolder -ne '\') 'the test never pointed at the real folders'
}
finally {
    foreach ($f in $folder, $legacyFolder, $nestFolder, $nestParent) {
        foreach ($t in Get-Tasks $f) { try { Remove-IiLogonTask $f $t.TaskName } catch {} }
    }
    try {
        $svc = New-Object -ComObject 'Schedule.Service'
        $svc.Connect()
        $root = $svc.GetFolder('\ii-windows-test')
        try { $svc.GetFolder("\ii-windows-test\$run-c").DeleteFolder('nest', 0) } catch {}
        foreach ($name in $run, "$run-legacy", "$run-c") { try { $root.DeleteFolder($name, 0) } catch {} }
        try { $svc.GetFolder('\').DeleteFolder('ii-windows-test', 0) } catch {}
    } catch {}
}
Complete-IiTest
