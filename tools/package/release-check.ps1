# Plan 1.4: what an antivirus and SmartScreen look at, checked on a built package before it is published.
#
#   release-check.ps1 [-Package out\ii-windows-<version>] [-Strict]
#
# For every program in the package:
#   - version information: product name, description, company, version (an executable without them looks like
#     malware to heuristics and to NVIDIA's profiles alike);
#   - no executable packer (UPX and the like: a classic false-positive trigger, and ii never uses one);
#   - its Authenticode signature (only ii-windows' own programs are expected to carry ii's);
#   - its SHA-256, with the VirusTotal link. With VT_API_KEY set, VirusTotal is asked for each hash (read-only:
#     nothing is uploaded) and the detections are listed.
# Writes <package>\release-check.md. -Strict fails (exit 1) on anything a release must not have: missing version
# information, a packer, an unsigned own program, a VirusTotal detection.
param([string]$Package = '', [switch]$Strict)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot)
if (-not $Package) {
    $Package = Get-ChildItem (Join-Path $root 'out') -Directory -Filter 'ii-windows-*' | Sort-Object LastWriteTime | Select-Object -Last 1 -ExpandProperty FullName
}
if (-not $Package -or -not (Test-Path $Package)) { throw 'no package (tools\package\make-package.ps1 first)' }

$own = @('ii-host.exe', 'ii-launcher.exe', 'ii-shim.exe', 'quickshell.exe')
$problems = New-Object System.Collections.Generic.List[string]
$rows = New-Object System.Collections.Generic.List[string]
# ii-windows' own programs first, so a program copied under other names (ii-shim as notify-send.exe...) is listed,
# and judged, under its own name.
$programs = Get-ChildItem $Package -Recurse -File | Where-Object { $_.Extension -in '.exe', '.dll' } |
    Sort-Object @{ Expression = { $_.Name -notin $own } }, FullName
$seen = @{}
foreach ($f in $programs) {
    $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()
    $rel = $f.FullName.Substring($Package.Length + 1)
    if ($seen.ContainsKey($hash)) { continue } # the same file under another name
    $seen[$hash] = $rel
    $info = $f.VersionInfo
    $isOwn = $f.Name -in $own
    $notes = @()
    if (-not $info.ProductName -or -not $info.FileDescription -or -not $info.CompanyName -or -not $info.FileVersion) {
        $notes += 'sin datos de versión'
        if ($isOwn -or $f.Extension -eq '.exe') { $problems.Add("${rel}: missing version information") }
    }
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    $head = [Text.Encoding]::ASCII.GetString($bytes, 0, [Math]::Min($bytes.Length, 4096))
    if ($head -match 'UPX[0-9!]' -or $head -match '\.MPRESS|\.aspack|PEC2') {
        $notes += 'EMPAQUETADO'
        $problems.Add("${rel}: packed executable")
    }
    $sig = Get-AuthenticodeSignature -LiteralPath $f.FullName
    $signer = if ($sig.SignerCertificate) { $sig.SignerCertificate.GetNameInfo('SimpleName', $false) } else { '' }
    if ($isOwn -and $sig.Status -ne 'Valid') { $problems.Add("${rel}: not signed") }
    $vt = ''
    if ($env:VT_API_KEY -and $f.Extension -eq '.exe') {
        try {
            $r = Invoke-RestMethod -Uri "https://www.virustotal.com/api/v3/files/$hash" -Headers @{ 'x-apikey' = $env:VT_API_KEY }
            $s = $r.data.attributes.last_analysis_stats
            $vt = "$($s.malicious) malicioso, $($s.suspicious) sospechoso"
            if ($s.malicious -gt 0 -or $s.suspicious -gt 0) { $problems.Add("${rel}: VirusTotal $vt") }
        } catch {
            $vt = 'sin análisis (súbelo en la web)'
        }
    }
    $rows.Add("| ``$rel`` | $($info.FileDescription) | $($info.FileVersion) | $(if ($sig.Status -eq 'Valid') { "firmado ($signer)" } else { 'sin firma' }) | $($notes -join ', ') | [$($hash.Substring(0, 12))…](https://www.virustotal.com/gui/file/$hash) $vt |")
}

$report = @"
# Comprobación de publicación

Paquete: ``$(Split-Path $Package -Leaf)``, $((Get-Date).ToString('yyyy-MM-dd HH:mm')).

| Archivo | Descripción | Versión | Firma | Notas | VirusTotal |
|---|---|---|---|---|---|
$($rows -join "`n")

## Problemas para una publicación

$(if ($problems.Count) { ($problems | ForEach-Object { "- $_" }) -join "`n" } else { 'Ninguno.' })
"@
$out = Join-Path $Package 'release-check.md'
Set-Content -LiteralPath $out -Value $report -Encoding UTF8
Write-Host "release-check: $($seen.Count) programs, $($problems.Count) problem(s) -> $out"
if ($Strict -and $problems.Count) { $problems | ForEach-Object { Write-Host "  $_" }; exit 1 }
