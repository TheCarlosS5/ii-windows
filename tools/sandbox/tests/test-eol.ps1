# The files .gitattributes keeps byte for byte (CRLF in the repository) did not lose their CRLF line endings
# (tools/dev/check-eol.py). Read-only.
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$out = & python -I "$repo\tools\dev\check-eol.py" 2>&1
Assert-Equal $LASTEXITCODE 0 "every CRLF file kept its line endings ($($out -join '; '))"
Complete-IiTest
