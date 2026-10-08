# INSIDE the sandbox: what the installer's cursor backup looks like (Windows PowerShell 5.1).
$key = Get-Item 'HKCU:\Control Panel\Cursors'
$saved = @(foreach ($name in $key.GetValueNames()) {
    $kind = $key.GetValueKind($name)
    $value = $key.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
    if ($value -is [byte[]]) { $value = [Convert]::ToBase64String($value) }
    [ordered]@{ name = $name; kind = "$kind"; value = $value }
})
ConvertTo-Json -InputObject $saved -Depth 3
