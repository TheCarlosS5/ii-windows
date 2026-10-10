# Parses PowerShell scripts without running them and fails on syntax errors.
#   check-ps-syntax.ps1 <file-or-folder>...      (folders: every *.ps1 below them)
# Run it with Windows PowerShell 5.1 (powershell.exe): that is what the installer scripts run under.
param([Parameter(ValueFromRemainingArguments)][string[]]$Path)
$files = foreach ($p in $Path) {
    if (Test-Path -LiteralPath $p -PathType Container) { Get-ChildItem -LiteralPath $p -Recurse -Filter *.ps1 -File | ForEach-Object { $_.FullName } }
    else { (Resolve-Path -LiteralPath $p).Path }
}
$bad = 0
foreach ($f in $files) {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $bad++
        foreach ($e in $errors) { '{0}:{1}: {2}' -f $f, $e.Extent.StartLineNumber, $e.Message }
    }
}
if ($bad -gt 0) { "$bad file(s) with syntax errors"; exit 1 }
"syntax ok ($(@($files).Count) file(s))"
exit 0
