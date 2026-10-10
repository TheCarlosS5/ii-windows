# Changes ii makes to values it does not own, recorded so they can be undone without stepping on
# anyone's later choice (R08). Dot-sourced by install.ps1, uninstall.ps1 and the tests.
#
# A change records: the original (existed? kind, value), what ii applied, and its owner. The rules:
#   Set      a value that is absent is created and recorded as ours; a value that already exists is
#            NOT taken (it is the user's, or another program's, even if it equals what ii would
#            write) unless the caller asks to take it over, in which case the original is recorded
#            first. A value ii already owns is kept as it is and keeps its true original: an upgrade
#            never mistakes ii's own value for the user's original.
#            If the user changed an owned value since, their choice stands (status user-modified).
#   Restore  if the value still equals what ii applied, the original is put back (or the value
#            deleted if it did not exist); if it differs, it is the user's now and is left alone.
#            Either way the record is dropped. Repeating install/uninstall changes nothing more.
# Registry access goes through [Microsoft.Win32.Registry]::CurrentUser with a path below HKCU,
# so tests can point it at a throwaway key.

function Read-IiRegValue([string]$SubKey, [string]$Name) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($SubKey, $false)
    if (-not $key) { return [pscustomobject]@{ Exists = $false; Kind = $null; Value = $null } }
    try {
        if ($key.GetValueNames() -notcontains $Name) { return [pscustomobject]@{ Exists = $false; Kind = $null; Value = $null } }
        $kind = [string]$key.GetValueKind($Name)
        # Raw value: %VARIABLES% stay unexpanded, so what is compared and restored is what is stored.
        $value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        [pscustomobject]@{ Exists = $true; Kind = $kind; Value = $value }
    } finally { $key.Close() }
}

function Write-IiRegValue([string]$SubKey, [string]$Name, $Value, [string]$Kind) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($SubKey)
    try { $key.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]$Kind) } finally { $key.Close() }
}

function Remove-IiRegValue([string]$SubKey, [string]$Name) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($SubKey, $true)
    if (-not $key) { return }
    try { $key.DeleteValue($Name, $false) } finally { $key.Close() }
}

function Test-IiSameRegValue($A, [string]$KindB, $ValueB) {
    if (-not $A.Exists -or $A.Kind -ne $KindB) { return $false }
    if ($A.Value -is [byte[]]) { return ($ValueB -is [byte[]]) -and ([Convert]::ToBase64String($A.Value) -eq [Convert]::ToBase64String($ValueB)) }
    return ([string]$A.Value) -ceq ([string]$ValueB)
}

# What the manifest stores for a value (JSON-safe: bytes as base64).
function ConvertTo-IiStored($Kind, $Value) {
    if ($Value -is [byte[]]) { return [ordered]@{ kind = $Kind; value = [Convert]::ToBase64String($Value); bytes = $true } }
    [ordered]@{ kind = $Kind; value = $Value; bytes = $false }
}

function ConvertFrom-IiStored($Stored) {
    # The leading comma keeps the byte[] a single value (a function's output is otherwise unrolled).
    if ($Stored.bytes) { return , [Convert]::FromBase64String([string]$Stored.value) }
    switch ($Stored.kind) {
        'DWord' { return [int]$Stored.value }
        'QWord' { return [long]$Stored.value }
        default { return [string]$Stored.value }
    }
}

# $Manifest.changes is an array of records; this returns the one with that id, or $null.
function Get-IiChange($Manifest, [string]$Id) {
    @($Manifest.changes) | Where-Object { $_ -and $_.id -eq $Id } | Select-Object -First 1
}

function Set-IiChange($Manifest, $Change) {
    $others = @(@($Manifest.changes) | Where-Object { $_ -and $_.id -ne $Change.id })
    $Manifest.changes = @($others) + @($Change)
}

# Returns one of: applied | taken-over | kept-ours | updated-ours | user-choice | foreign-existing
function Set-IiOwnedRegValue {
    param($Manifest, [string]$Id, [string]$SubKey, [string]$Name, $Value, [string]$Kind, [switch]$TakeOver)
    $current = Read-IiRegValue $SubKey $Name
    $change = Get-IiChange $Manifest $Id

    if ($change) {
        $applied = $change.applied
        $ours = $current.Exists -and (Test-IiSameRegValue $current $applied.kind (ConvertFrom-IiStored $applied))
        if (-not $ours) {
            $change.status = 'user-modified'
            return 'user-choice'
        }
        if (Test-IiSameRegValue $current $Kind $Value) { return 'kept-ours' }
        Write-IiRegValue $SubKey $Name $Value $Kind
        $change.applied = ConvertTo-IiStored $Kind $Value
        return 'updated-ours'
    }

    if ($current.Exists -and -not $TakeOver) { return 'foreign-existing' }
    $record = [ordered]@{
        id = $Id; key = $SubKey; name = $Name; owner = 'ii-windows'; status = 'applied'; appliedAt = (Get-Date).ToString('s')
        original = if ($current.Exists) { ConvertTo-IiStored $current.Kind $current.Value } else { [ordered]@{ exists = $false } }
        applied  = ConvertTo-IiStored $Kind $Value
    }
    Write-IiRegValue $SubKey $Name $Value $Kind
    Set-IiChange $Manifest ([pscustomobject]$record)
    if ($current.Exists) { return 'taken-over' }
    return 'applied'
}

# Returns restored | deleted | user-changed | nothing-recorded
function Restore-IiOwnedRegValue {
    param($Manifest, [string]$Id)
    $change = Get-IiChange $Manifest $Id
    if (-not $change) { return 'nothing-recorded' }
    $current = Read-IiRegValue $change.key $change.name
    $applied = $change.applied
    $result = 'user-changed'
    if ($current.Exists -and (Test-IiSameRegValue $current $applied.kind (ConvertFrom-IiStored $applied))) {
        if ($change.original.PSObject.Properties.Name -contains 'exists' -and -not $change.original.exists) {
            Remove-IiRegValue $change.key $change.name
            $result = 'deleted'
        } else {
            Write-IiRegValue $change.key $change.name (ConvertFrom-IiStored $change.original) ([string]$change.original.kind)
            $result = 'restored'
        }
    }
    $Manifest.changes = @(@($Manifest.changes) | Where-Object { $_ -and $_.id -ne $Id })
    $result
}

# Old manifests (before changes[]) knew only the GPU preference path: if that value is still what
# ii wrote, it becomes an owned change whose original is "absent" (the installer never wrote it
# over an existing one).
function Import-IiLegacyChanges($Manifest, [string]$GpuKey = 'Software\Microsoft\DirectX\UserGpuPreferences') {
    if (-not ($Manifest.PSObject.Properties.Name -contains 'changes')) { $Manifest | Add-Member -NotePropertyName changes -NotePropertyValue @() }
    if (($Manifest.PSObject.Properties.Name -contains 'gpuPreference') -and $Manifest.gpuPreference) {
        $exe = [string]$Manifest.gpuPreference
        $id = "gpu:$exe"
        if (-not (Get-IiChange $Manifest $id)) {
            $cur = Read-IiRegValue $GpuKey $exe
            if ($cur.Exists -and $cur.Kind -eq 'String' -and $cur.Value -eq 'GpuPreference=1;') {
                Set-IiChange $Manifest ([pscustomobject][ordered]@{
                    id = $id; key = $GpuKey; name = $exe; owner = 'ii-windows'; status = 'applied'; appliedAt = $null
                    original = [ordered]@{ exists = $false }; applied = (ConvertTo-IiStored 'String' 'GpuPreference=1;')
                })
            }
        }
    }

    # The Run-key entry of installs without the logon task: a value named ii-windows that the
    # old manifest lists is ours; it did not exist before ii.
    $runKey = 'Software\Microsoft\Windows\CurrentVersion\Run'
    if (@($Manifest.registry) -match [regex]::Escape('CurrentVersion\Run\ii-windows') -and -not (Get-IiChange $Manifest 'run:ii-windows')) {
        $cur = Read-IiRegValue $runKey 'ii-windows'
        if ($cur.Exists -and $cur.Kind -eq 'String') {
            Set-IiChange $Manifest ([pscustomobject][ordered]@{
                id = 'run:ii-windows'; key = $runKey; name = 'ii-windows'; owner = 'ii-windows'; status = 'applied'; appliedAt = $null
                original = [ordered]@{ exists = $false }; applied = (ConvertTo-IiStored 'String' $cur.Value)
            })
        }
    }
}
