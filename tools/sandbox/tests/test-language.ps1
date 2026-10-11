# C12: which UI language is loaded, resolved from the translation files that exist. Runs the very
# JavaScript file the shell imports (overlay\ii\modules\common\functions\LanguageResolve.js) under
# Node with its pragma line stripped. Also checks the real upstream folder against it.
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { Skip-Test 'node not found' }
$js = Join-Path $repo 'overlay\ii\modules\common\functions\LanguageResolve.js'
$translations = Join-Path $repo 'upstream\dots\.config\quickshell\ii\translations'

$harness = Join-Path $env:TEMP ('ii-language-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.js')
$source = (Get-Content $js -Raw) -replace '(?m)^\.pragma library', ''
$jsLiteral = ($source | ConvertTo-Json)
$files = if (Test-Path $translations) { (Get-ChildItem $translations | ForEach-Object { $_.Name } | ConvertTo-Json -Compress) } else { '[]' }
Set-Content $harness @"
const vm = require('vm');
const ctx = {}; vm.createContext(ctx); vm.runInContext($jsLiteral, ctx);
const L = ctx;
const out = [];
const eq = (a, b, what) => out.push((JSON.stringify(a) === JSON.stringify(b) ? 'ok  ' : 'FAIL') + ' ' + what + (JSON.stringify(a) === JSON.stringify(b) ? '' : ' got ' + JSON.stringify(a) + ' wanted ' + JSON.stringify(b)));

eq(L.folderUrl('C:\\Users\\a b\\x'), 'file:///C:/Users/a b/x', 'a Windows path becomes a file URL');
eq(L.folderUrl('/C:/Users/x'), 'file:///C:/Users/x', 'the /C:/ form that trimFileProtocol leaves works too');
eq(L.folderUrl('file:///C:/x'), 'file:///C:/x', 'a URL is left alone');

eq(L.parseLanguages(['en_US.json', 'es_MX.json', 'tools', 'README.md', 'zh_CN.json', 'bad name.json', 'es_MX.json']), ['en_US', 'es_MX', 'zh_CN'], 'only locale-named .json files are languages, once each, sorted');
eq(L.parseLanguages([]), [], 'an empty folder has none');

eq(L.normalize('es-CO'), 'es_CO', 'es-CO -> es_CO');
eq(L.normalize('es_CO.UTF-8'), 'es_CO', 'a POSIX-style locale is cleaned');
eq(L.normalize('ES_co@euro'), 'es_CO', 'case is fixed');
eq(L.normalize('zh-Hans'), 'zh_Hans', 'script subtags keep their shape');
eq(L.normalize('en'), 'en', 'a bare language stays bare');
eq(L.normalize('nonsense!!'), '', 'garbage is not a locale');
eq(L.normalize(''), '', 'empty is empty');

const have = ['de_DE', 'en_US', 'es_MX', 'pt_BR', 'zh_CN'];
eq(L.resolve('es_MX', have), 'es_MX', 'an exact match wins');
eq(L.resolve('es-CO', have), 'es_MX', 'es_CO falls back to the Spanish that exists (es_MX)');
eq(L.resolve('es_ES', have), 'es_MX', 'so does es_ES');
eq(L.resolve('pt_PT', have), 'pt_BR', 'pt_PT -> pt_BR');
eq(L.resolve('es_CO', ['en_US', 'es_AR', 'es_MX']), 'es_AR', 'with several variants the first sorted is used (stable)');
eq(L.resolve('fr_FR', have), 'en_US', 'a language with no file falls back to English');
eq(L.resolve('ja_JP', ['zh_CN']), 'zh_CN', 'and to the first one if there is not even English');
eq(L.resolve('es_CO', []), 'es_CO', 'before the folder is scanned nothing is guessed');
eq(L.resolve('', have), 'en_US', 'no language at all: English');
eq(L.resolve('weird!!', have), 'en_US', 'an unparsable code: English');
eq(L.resolve('zh_CN', have), 'zh_CN', 'zh_CN exact');

const real = L.parseLanguages($files);
out.push((real.length > 5 ? 'ok  ' : 'FAIL') + ' the real upstream folder yields ' + real.length + ' languages');
out.push((!real.includes('tools') ? 'ok  ' : 'FAIL') + ' and its tools folder is not one of them');
eq(L.resolve('es_CO', real), real.includes('es_CO') ? 'es_CO' : 'es_MX', 'es_CO against the real files');
console.log(out.join('\n'));
process.exit(out.some(l => l.startsWith('FAIL')) ? 1 : 0);
"@
try {
    $text = & $node $harness 2>&1 | Out-String
    $code = $LASTEXITCODE
    $text.TrimEnd() -split "`r?`n" | ForEach-Object { Write-Output $_ }
    Assert-Equal $code 0 'every language check passed'
    Assert-True (([regex]::Matches($text, '(?m)^ok ')).Count -ge 24) 'and there were at least 24 of them'
}
finally { Remove-Item $harness -ErrorAction SilentlyContinue }
Complete-IiTest
