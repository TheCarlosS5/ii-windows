. "$PSScriptRoot\..\..\lib\ii-test.ps1"
Assert-True $true 'first check passes'
Assert-Equal 'a' 'b' 'second check must fail'
Complete-IiTest
