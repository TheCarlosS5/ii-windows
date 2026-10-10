# Environment manifest for a benchmark run (TASKS_ii_windows 8.1): what the numbers were measured on.
# No user name, no personal paths, no keys, no notification or chat text. Two runs are only
# comparable if their manifests agree on everything except the thing under test.
#   bench-manifest.ps1 [-Out <file.json>] [-Cache cold|warm|unknown] [-Note <text>]
param([string]$Out = '', [ValidateSet('cold', 'warm', 'unknown')][string]$Cache = 'unknown', [string]$Note = '')
$ErrorActionPreference = 'Continue'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path

function Redact([string]$text) {
    if (-not $text) { return $text }
    foreach ($s in @($env:USERPROFILE, $env:USERNAME, $env:COMPUTERNAME) | Where-Object { $_ -and $_.Length -ge 2 } | Sort-Object Length -Descending) {
        $text = $text -ireplace [regex]::Escape($s), '<redacted>'
    }
    $text
}

function GitInfo([string]$dir) {
    if (-not (Test-Path (Join-Path $dir '.git'))) { return $null }
    $head = (git -C $dir rev-parse HEAD 2>$null)
    $dirty = [bool](git -C $dir status --porcelain 2>$null)
    [ordered]@{ head = "$head".Trim(); dirty = $dirty }
}

Add-Type -Namespace IiBench -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern uint GetDpiForSystem();
[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct DEVMODE {
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
  public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields;
  public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
  public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
  public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
  public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight; }
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool EnumDisplaySettings(string device, int mode, ref DEVMODE dm);
'@
Add-Type -AssemblyName System.Windows.Forms

$os = Get-CimInstance Win32_OperatingSystem
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$displays = @([System.Windows.Forms.Screen]::AllScreens | ForEach-Object {
    $dm = New-Object IiBench.Native+DEVMODE
    $dm.dmSize = [int][Runtime.InteropServices.Marshal]::SizeOf($dm)
    $hz = $null
    if ([IiBench.Native]::EnumDisplaySettings($_.DeviceName, -1, [ref]$dm)) { $hz = $dm.dmDisplayFrequency }
    [ordered]@{ primary = $_.Primary; widthPx = $_.Bounds.Width; heightPx = $_.Bounds.Height; refreshHz = $hz }
})
$battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
$plan = (powercfg /getactivescheme 2>$null) -replace '^.*\(([^)]*)\).*$', '$1'
$qsBuild = Join-Path $repo 'quickshell\build\CMakeCache.txt'
if (-not (Test-Path $qsBuild)) { $qsBuild = Join-Path $repo 'quickshell\build-r\CMakeCache.txt' }
$buildType = if (Test-Path $qsBuild) { ((Select-String -Path $qsBuild -Pattern '^CMAKE_BUILD_TYPE:STRING=(.*)$' | Select-Object -First 1).Matches.Groups[1].Value) } else { $null }
$qtDll = Get-ChildItem -Path @("$repo\dist\quickshell\Qt6Core.dll", "$env:USERPROFILE\dev\Qt\bin\Qt6Core.dll") -ErrorAction SilentlyContinue | Select-Object -First 1

$manifest = [ordered]@{
    id        = '{0:yyyyMMdd-HHmmss}-{1}' -f (Get-Date), ([guid]::NewGuid().ToString('N').Substring(0, 6))
    date      = (Get-Date).ToString('o')
    commits   = [ordered]@{ ii = GitInfo $repo; quickshellWindows = GitInfo (Join-Path $repo 'quickshell'); upstream = GitInfo (Join-Path $repo 'upstream') }
    build     = [ordered]@{
        quickshellBuildType = $buildType
        qtCoreVersion       = if ($qtDll) { $qtDll.VersionInfo.ProductVersion } else { $null }
        hostExeSha256       = if (Test-Path "$repo\host\build\ii-host.exe") { (Get-FileHash "$repo\host\build\ii-host.exe" -Algorithm SHA256).Hash } else { $null }
        renderLoop          = if ($env:QSG_RENDER_LOOP) { $env:QSG_RENDER_LOOP } else { 'default (basic, set by init.cpp)' }
    }
    windows   = [ordered]@{ caption = $os.Caption; displayVersion = $cv.DisplayVersion; build = "$($cv.CurrentBuild).$($cv.UBR)" }
    hardware  = [ordered]@{
        cpu    = $cpu.Name
        cores  = $cpu.NumberOfCores
        ramGiB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        gpus   = @(Get-CimInstance Win32_VideoController | ForEach-Object { [ordered]@{ name = $_.Name; driver = $_.DriverVersion } })
        dpi    = [IiBench.Native]::GetDpiForSystem()
        displays = $displays
    }
    power     = [ordered]@{ plan = $plan; onBattery = [bool]($battery -and $battery.BatteryStatus -eq 1) }
    protocol  = [ordered]@{ cache = $Cache; note = $Note }
    privacy   = 'No user name, personal paths, keys or notification/chat text are recorded.'
}
$json = Redact ($manifest | ConvertTo-Json -Depth 8)
if ($Out) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $Out) | Out-Null
    $json | Set-Content -LiteralPath $Out -Encoding UTF8
    "manifest written: $Out"
} else { $json }
