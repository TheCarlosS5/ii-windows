& C:\ii\tools\sandbox\tests\test-persist.ps1 -Baseline 0
"=== baseline 1 (auto-hide on, like the real PC)"
& C:\ii\tools\sandbox\tests\test-persist.ps1 -Baseline 1
"=== back to the sandbox default"
& C:\ii\tools\sandbox\tests\test-persist.ps1 -Baseline 0 | Select-Object -Last 1
