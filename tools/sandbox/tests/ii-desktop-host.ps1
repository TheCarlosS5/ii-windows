# Sandbox driver entry point: desktop interactions plus real host / Win+D.
if ($env:USERNAME -ne 'WDAGUtilityAccount') { throw 'Sandbox only' }
& C:\ii\tools\sandbox\tests\ii-desktop.ps1 -WithHost
exit $LASTEXITCODE
