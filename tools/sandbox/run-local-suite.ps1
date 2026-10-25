# The tests that run on one ordinary Windows PC, with nothing but this repository's build output:
# no Windows Sandbox, no second user, no reboot, and nothing that touches the ii that is running.
# (The older ii-*.ps1 / test-banners / test-host ... scripts in tests\ need a disposable machine and are
# not part of this list.)
#   run-local-suite.ps1 [-Only <name-substring>] [-TimeoutSec 600]
# Build first: cmake --build host\build --target ii-host ii-fake-shell ii-launcher ii-keyrouter-test ii-lockstate-test ii-vdesk-test ii-config-test
#              cmake --build host\build-clang --target ii-shim   (clang-cl)
# A test whose prerequisite is missing is reported as SKIPPED, never as passed.
param([string]$Only = '', [int]$TimeoutSec = 600)
$tests = 'test-ownership', 'test-changes', 'test-autostart', 'test-runtime', 'test-install-flow', 'test-staging', 'test-qml-lint',
         'test-actions', 'test-vdesk', 'test-config', 'test-language', 'test-linux-routes', 'test-shim-files', 'test-report-redaction', 'test-airequest',
         'test-fastfetch', 'test-host-launch', 'test-host-heartbeat', 'test-host-health', 'test-rescue-ps', 'test-bench', 'test-qs-smoke', 'test-input-region'
if ($Only) { $tests = @($tests | Where-Object { $_ -like "*$Only*" }) }
$paths = $tests | ForEach-Object { Join-Path $PSScriptRoot "tests\$_.ps1" }
& (Join-Path $PSScriptRoot 'run-tests.ps1') -Path ($paths -join ',') -RequireAssertions -TimeoutSec $TimeoutSec
exit $LASTEXITCODE
