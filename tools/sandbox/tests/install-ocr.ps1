# INSIDE the sandbox: install an OCR language (Sandbox only; it is thrown away on close).
$cap = Get-WindowsCapability -Online | Where-Object { $_.Name -like "Language.OCR~~~en-US*" }
"before: $($cap.Name) $($cap.State)"
if ($cap.State -ne "Installed") { Add-WindowsCapability -Online -Name $cap.Name | Out-Null }
"after: $((Get-WindowsCapability -Online -Name $cap.Name).State)"
