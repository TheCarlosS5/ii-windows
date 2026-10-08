# Read-only on the real PC: no host, shell, gamma application or power plan changes.
param([string]$Shim = (Join-Path $PSScriptRoot '..\..\host\build\ii-shim.exe'))
$ErrorActionPreference = 'Stop'
function Check($condition, $message) {
    if (-not $condition) { throw "FAIL: $message" }
    Write-Output "PASS: $message"
}
$identity = & $Shim nightlight preview 6500 100 | ConvertFrom-Json
Check ($LASTEXITCODE -eq 0 -and $identity.kelvin -eq 6500) 'identity preview exists'
foreach ($channel in $identity.ramps) {
    Check ($channel.Count -eq 256 -and $channel[0] -eq 0 -and $channel[255] -eq 65535) 'identity endpoints'
    for ($i = 0; $i -lt 256; $i++) { if ($channel[$i] -ne $i * 257) { throw "FAIL: identity $i" } }
}
Write-Output 'PASS: identity values (768 samples)'
$warm = & $Shim nightlight preview 1200 25 | ConvertFrom-Json
Check ($LASTEXITCODE -eq 0 -and $warm.kelvin -gt 1200 -and $warm.gamma -gt 25) 'unsupported intensity is clamped'
foreach ($channel in $warm.ramps) {
    for ($i = 1; $i -lt 256; $i++) {
        if ($channel[$i] -lt $channel[$i - 1] -or [Math]::Abs($channel[$i] - $i * 257) -gt 30000) { throw 'unsafe/nonmonotonic ramp' }
    }
}
Write-Output 'PASS: clamped ramps monotonic and close to identity'
$before = & $Shim power status | ConvertFrom-Json
Check ($LASTEXITCODE -eq 0 -and $before.activeGuid) 'power scheme read-only listing'
Check (@($before.plans | Where-Object { $_.id -notin @('power-saver','balanced','performance') }).Count -eq 0) 'only standard present plans offered'
$info = & $Shim system-info | ConvertFrom-Json
Check ($LASTEXITCODE -eq 0 -and $info.name -match '^Windows' -and $info.build -gt 0) 'Windows edition and build'
& (Join-Path (Split-Path $Shim) 'ii-sidebar-test.exe')
Check ($LASTEXITCODE -eq 0) 'fake gamma backend safety tests'
$after = & $Shim power status | ConvertFrom-Json
Check ($before.activeGuid -eq $after.activeGuid) 'active power plan unchanged'

# Compile only the independent rescue type. Never run the rescue script or Restore().
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$rescueText = [IO.File]::ReadAllText((Join-Path $repo 'tools\rescue\ii-rescue.ps1'))
$rescueType = [regex]::Match($rescueText, "(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@").Groups[1].Value
Check ($rescueType.Length -gt 0) 'independent gamma rescue type extracted'
Add-Type -TypeDefinition $rescueType
Write-Output 'PASS: independent gamma rescue C# compiles (not executed)'

# Run the real service's schedule/edit-index functions in a console JS context.
$env:II_SIDEBAR_TEST_ROOT = $repo
@'
const fs = require('fs'), path = require('path'), vm = require('vm');
const base = process.env.II_SIDEBAR_TEST_ROOT;
const read = p => fs.readFileSync(path.join(base, 'build/ii', p), 'utf8');
function check(ok, message) { if (!ok) throw Error(message); }
function body(text, start) {
    let at = text.indexOf('{', start), n = 1, end = at + 1;
    for (; n && end < text.length; ++end) { if (text[end] === '{') ++n; else if (text[end] === '}') --n; }
    return text.slice(at + 1, end - 1);
}
const source = read('services/Hyprsunset.qml');
const x = { automatic: true, manualActive: undefined, manualActiveHour: 0, manualActiveMinute: 0, firstEvaluation: true,
    fromHour: 19, fromMinute: 0, toHour: 6, toMinute: 30,
    clockHour: 23, clockMinute: 0, requestedTemperature: false };
x.root = x;
x.enableTemperature = () => x.requestedTemperature = true;
x.disableTemperature = () => x.requestedTemperature = false;
let functions = '';
for (const name of ['inBetween','reEvaluate','ensureState','toggleTemperature']) {
    const at = source.indexOf('function ' + name + '(');
    const args = source.slice(at, source.indexOf('{', at));
    functions += args + '{' + body(source, at) + '}\n';
}
vm.runInNewContext(functions, x);
check(x.inBetween(23 * 60, 19 * 60, 6 * 60 + 30), 'night wraps midnight');
check(x.inBetween(4 * 60, 19 * 60, 6 * 60 + 30), 'early morning inside schedule');
check(!x.inBetween(12 * 60, 19 * 60, 6 * 60 + 30), 'noon outside schedule');
check(x.inBetween(12 * 60, 9 * 60, 17 * 60), 'daytime interval');
x.reEvaluate(); check(x.requestedTemperature, 'startup schedule enabled');
x.toggleTemperature(false); x.clockMinute = 1; x.reEvaluate(); x.ensureState();
check(!x.requestedTemperature && x.manualActive === false, 'manual override survives same interval');
x.clockHour = 6; x.clockMinute = 31; x.reEvaluate(); x.ensureState();
check(!x.requestedTemperature && x.manualActive === undefined, 'schedule boundary clears override');
x.clockHour = 19; x.clockMinute = 0; x.reEvaluate(); x.ensureState();
check(x.requestedTemperature, 'next scheduled start');
x.automatic = false; x.requestedTemperature = false; x.ensureState();
check(!x.requestedTemperature, 'automatic disabled respects manual state');
const panel = read('modules/ii/sidebarRight/quickToggles/AndroidQuickPanel.qml');
const types = JSON.parse(panel.match(/availableToggleTypes: (\[[^\n]+\])/)[1]);
for (const type of ['easyEffects','cloudflareWarp','colorPicker','musicRecognition','antiFlashbang']) check(!types.includes(type), 'unsupported type hidden: ' + type);
const Config = {ready: true, options: {sidebar: {quickToggles: {android: {toggles: [
    {type:'network',size:2}, {type:'easyEffects',size:1}, null, {type:'nightLight',size:1}, {type:'audio',size:1}
]}}}}};
const selected = new Function('Config', 'availableToggleTypes', body(panel, panel.indexOf('readonly property list<var> toggles:')))(Config, types);
check(selected.length === 3 && selected[1].configIndex === 3 && selected[1].previousConfigIndex === 0 && selected[1].nextConfigIndex === 4, 'hidden controls preserve edit/resize/reorder Config indices');
const button = read('modules/ii/sidebarRight/quickToggles/androidStyle/AndroidQuickToggleButton.qml');
const editor = { Config, root: {buttonIndex:3, buttonData:selected[1]} };
let editing = '';
for (const name of ['toggleEnabled','toggleSize','movePositionBy']) {
    const at = button.indexOf('function ' + name + '(');
    editing += button.slice(at, button.indexOf('{', at)) + '{' + body(button, at) + '}\n';
}
vm.runInNewContext(editing, editor);
const list = Config.options.sidebar.quickToggles.android.toggles;
editor.toggleSize(); check(list[3].size === 2 && list[1].type === 'easyEffects', 'resize with hidden/null entries');
editor.movePositionBy(-1); check(list[0].type === 'nightLight' && list[3].type === 'network' && list[2] === null, 'reorder skips hidden/null controls');
editor.root.buttonIndex = 0;
editor.toggleEnabled(); check(!list.some(t => t && t.type === 'nightLight') && list[0].type === 'easyEffects', 'remove uses original Config index');
editor.root.buttonIndex = -1; editor.root.buttonData = {type:'gameMode'};
editor.toggleEnabled(); check(list[list.length - 1].type === 'gameMode', 'add unused control with null entries');
console.log('PASS: schedule/manual override/midnight and filtered toggle edit indices');
'@ | node -
Check ($LASTEXITCODE -eq 0) 'actual QML JavaScript functions pass console tests'

# qmlformat parses only; do NOT use --inplace. Supply bundled CRT DLLs and suppress loader
# dialogs, so an incomplete Qt SDK reports a console failure without creating a window.
Add-Type -Namespace IiSidebarCheck -Name Errors -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint mode);'
$oldMode = [IiSidebarCheck.Errors]::SetErrorMode(0x8003)
$oldPath = $env:Path
try {
    $env:Path = (Join-Path $repo 'dist\quickshell') + ';' + $oldPath
    $qtBin = if ($env:QTDIR) { Join-Path $env:QTDIR 'bin' } else { "$env:USERPROFILE\dev\Qt\6.12.0-msvc2022_64\bin" }
    $qmlFiles = @(Get-ChildItem (Join-Path $repo 'build\ii\modules\ii\sidebarRight') -Filter '*.qml' -Recurse)
    $qmlFiles += @(Get-ChildItem (Join-Path $repo 'build\ii\modules\common\models\quickToggles') -Filter '*.qml')
    foreach ($name in 'Hyprsunset','SystemInfo','Audio','Network') { $qmlFiles += Get-Item (Join-Path $repo "build\ii\services\$name.qml") }
    foreach ($qmlFile in $qmlFiles) {
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo.FileName = Join-Path $qtBin 'qmlformat.exe'
        $process.StartInfo.Arguments = '--ignore-settings "' + $qmlFile.FullName + '"'
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        [void]$process.Start()
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(10000)) { $process.Kill(); throw 'QML parser timeout' }
        [void]$outTask.Result
        $errors = $errTask.Result
        if ($errors) { Write-Output $errors }
        if ($process.ExitCode -ne 0) { throw "QML parser failed: $($qmlFile.FullName), exit=$($process.ExitCode)" }
        $process.Dispose()
    }
    Write-Output "PASS: QML parses ($($qmlFiles.Count) files), no GUI/runtime execution"
} finally {
    $env:Path = $oldPath
    [void][IiSidebarCheck.Errors]::SetErrorMode($oldMode)
}
Write-Output 'sidebar failures=0'
