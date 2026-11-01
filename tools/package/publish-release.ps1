# Publishes a built package as a GitHub release the updater can install (plan 2026-10-31, B1). PowerShell 7.
#
#   publish-release.ps1 [-Package out\ii-windows-<id>] [-Beta] [-Critical] [-NeedsInstaller] [-Fixes 'quickshell.exe+0x19ed74,...']
#                       [-Notes docs\RELEASE-x.y.z.md] [-DryRun]
#
# 1. completes the release.json draft make-package.ps1 wrote (channel, publication date, the Setup if there is one,
#    critical, needsInstaller, the crash signatures this version fixes) and checks every hash against the files;
# 2. signs it (sign-release.ps1: the private key never leaves %USERPROFILE%\.ii-release-key) and verifies the signature;
# 3. creates the release v<version> (a prerelease with -Beta) and uploads: the zip, the Setup, release.json,
#    release.json.sig, the symbols zip and release-check.md.
# The GitHub token comes from git's credential store (`git credential fill`), as for the earlier releases.
# -DryRun does 1 and 2 and lists what it would upload, without touching GitHub.
# Ask the author before running it without -DryRun: a release reaches every installed copy.
param([string]$Package = '', [switch]$Beta, [switch]$Critical, [switch]$NeedsInstaller, [string]$Fixes = '', [string]$Notes = '', [switch]$DryRun,
      [string]$Repo = 'TheCarlosS5/ii-windows')
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'run with pwsh (PowerShell 7)' }
$root = Split-Path (Split-Path $PSScriptRoot)
$out = Join-Path $root 'out'
if (-not $Package) {
    $Package = Get-ChildItem $out -Directory -Filter 'ii-windows-*' | Where-Object { $_.Name -notlike '*-symbols' } |
        Sort-Object LastWriteTime | Select-Object -Last 1 -ExpandProperty FullName
}
if (-not $Package -or -not (Test-Path $Package)) { throw 'no package (tools\package\make-package.ps1 first)' }
$name = Split-Path $Package -Leaf
$id = $name -replace '^ii-windows-', ''
$zip = Join-Path $out "$name.zip"
$draft = Join-Path $out "$name-release.json"
$symbols = Join-Path $out "$name-symbols.zip"
$check = Join-Path $Package 'release-check.md'
foreach ($f in $zip, $draft) { if (-not (Test-Path $f)) { throw "missing $f" } }

# --- 1. release.json ------------------------------------------------------------------------------------------------
$release = Get-Content $draft -Raw | ConvertFrom-Json -AsHashtable
if ($release.id -ne $id) { throw "release.json is for $($release.id), the package is $id" }
$zipHash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
if ($release.package.sha256 -ne $zipHash -or $release.package.size -ne (Get-Item $zip).Length) { throw 'the zip changed after make-package.ps1: build the package again' }
$base = $release.version
$setup = Get-ChildItem $out -Filter "ii-windows-Setup-$id.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($setup) {
    $release.setup = [ordered]@{ name = $setup.Name; size = $setup.Length; sha256 = (Get-FileHash $setup.FullName -Algorithm SHA256).Hash.ToLower() }
}
$release.channel = if ($Beta) { 'beta' } else { 'stable' }
$release.critical = [bool]$Critical
$release.needsInstaller = [bool]$NeedsInstaller
$release.publishedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
if ($Fixes) { $release.fixes = @($Fixes -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
$notesFile = if ($Notes) { $Notes } else { Join-Path $root "docs\RELEASE-$base.md" }
if (Test-Path $notesFile) { $release.notes = [ordered]@{ es = [IO.File]::ReadAllText($notesFile) } }
$final = Join-Path $out "$name-release.final.json"
[IO.File]::WriteAllText($final, ($release | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))

# --- 2. signature ---------------------------------------------------------------------------------------------------
& (Join-Path $PSScriptRoot 'sign-release.ps1') -File $final
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) { throw 'signing failed' }
& (Join-Path $PSScriptRoot 'sign-release.ps1') -File $final -Verify
if ($LASTEXITCODE -ne 0) { throw 'the signature does not verify' }

$assets = [ordered]@{}
$assets[(Split-Path $zip -Leaf)] = $zip
if ($setup) { $assets[$setup.Name] = $setup.FullName }
$assets['release.json'] = $final
$assets['release.json.sig'] = "$final.sig"
if (Test-Path $symbols) { $assets[(Split-Path $symbols -Leaf)] = $symbols }
if (Test-Path $check) { $assets['release-check.md'] = $check }
"release v$base ($($release.channel)$(if ($Critical) { ', critical' })): $id"
$assets.GetEnumerator() | ForEach-Object { "  {0,-58} {1,8:N1} MB" -f $_.Key, ((Get-Item $_.Value).Length / 1MB) }
if ($DryRun) { 'dry run: nothing published'; exit 0 }

# --- 3. GitHub ------------------------------------------------------------------------------------------------------
$credential = "protocol=https`nhost=github.com`n`n" | git credential fill
$token = ($credential | Where-Object { $_ -like 'password=*' }) -replace '^password=', ''
if (-not $token) { throw 'no GitHub token in git''s credential store' }
$headers = @{ Authorization = "Bearer $token"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
$body = @{ tag_name = "v$base"; name = "ii-windows $base$(if ($Beta) { ' (beta)' })"; body = $release.notes.es; prerelease = [bool]$Beta; draft = $false } | ConvertTo-Json
$created = Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/$Repo/releases" -Headers $headers -Body $body -ContentType 'application/json'
$uploadBase = $created.upload_url -replace '\{.*$', ''
foreach ($asset in $assets.GetEnumerator()) {
    $type = if ($asset.Key -like '*.json' -or $asset.Key -like '*.sig' -or $asset.Key -like '*.md') { 'text/plain' } else { 'application/octet-stream' }
    Invoke-RestMethod -Method Post -Uri "$uploadBase`?name=$([uri]::EscapeDataString($asset.Key))" -Headers $headers -InFile $asset.Value -ContentType $type | Out-Null
    "uploaded $($asset.Key)"
}
"published: $($created.html_url)"
