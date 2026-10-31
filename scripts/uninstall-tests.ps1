# Tests that uninstalling leaves macOS's own edge tiling as macOS ships it: `make uninstall`
# runs scripts/restore-edge-tiling.sh, the script deletes the same keys NativeEdgeTiling.turnOff
# writes, and the wiki tells drag-to-Trash users where to switch it back on. On macOS (CI) the
# script also runs for real, against a plist in a temporary folder instead of WindowManager's.
# Plain PowerShell, no Pester, so Windows PowerShell 5.1 and pwsh 7 run them alike:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/uninstall-tests.ps1
#   pwsh -NoProfile -File scripts/uninstall-tests.ps1

$ErrorActionPreference = 'Stop'

$script:passed = 0
$script:failed = 0

function Test([string]$Name, [scriptblock]$Body) {
    try {
        & $Body
        $script:passed++
    } catch {
        $script:failed++
        [Console]::Out.WriteLine("FAIL $Name")
        [Console]::Out.WriteLine("  $($_.Exception.Message)")
    }
}

$root = Join-Path $PSScriptRoot '..'
$restore = Join-Path $root 'scripts/restore-edge-tiling.sh'

function Read-Text([string]$Path) {
    [IO.File]::ReadAllText((Join-Path $root $Path), [Text.Encoding]::UTF8)
}

function Get-SwiftKeys {
    $text = Read-Text 'Sources/DockFlipKit/WindowLayout/NativeEdgeTiling.swift'
    $m = [regex]::Match($text, 'static let keys = \[([^\]]*)\]')
    if (-not $m.Success) { throw 'no `static let keys = [...]` in NativeEdgeTiling.swift' }
    @([regex]::Matches($m.Groups[1].Value, '"(\w+)"') | ForEach-Object { $_.Groups[1].Value }) | Sort-Object
}

Test 'make uninstall runs restore-edge-tiling.sh' {
    $makefile = Read-Text 'Makefile'
    $m = [regex]::Match($makefile, '(?ms)^uninstall:\r?\n((?:\t[^\r\n]*\r?\n)+)')
    if (-not $m.Success) { throw 'no uninstall target in the Makefile' }
    if (-not $m.Groups[1].Value.Contains('scripts/restore-edge-tiling.sh')) {
        throw 'the uninstall recipe does not run scripts/restore-edge-tiling.sh'
    }
}

Test 'the script restores every key NativeEdgeTiling turns off' {
    $m = [regex]::Match((Read-Text 'scripts/restore-edge-tiling.sh'), '(?m)^for key in ([^;]+);')
    if (-not $m.Success) { throw 'no `for key in ...;` loop in restore-edge-tiling.sh' }
    $scriptKeys = @($m.Groups[1].Value.Trim() -split '\s+') | Sort-Object
    $swiftKeys = Get-SwiftKeys
    if (($scriptKeys -join ' ') -ne ($swiftKeys -join ' ')) {
        throw "restore-edge-tiling.sh has [$($scriptKeys -join ', ')], NativeEdgeTiling.keys has [$($swiftKeys -join ', ')]"
    }
}

Test 'the wiki tells drag-to-Trash users where to switch edge tiling back on' {
    $m = [regex]::Match((Read-Text 'docs/wiki/Installation.md'), '(?ms)^## Uninstalling\r?\n(.*?)(?=^## |\z)')
    if (-not $m.Success) { throw 'no Uninstalling section in docs/wiki/Installation.md' }
    foreach ($words in 'Desktop & Dock', 'Drag windows to screen edges to tile', 'make uninstall') {
        if (-not $m.Groups[1].Value.Contains($words)) { throw "the Uninstalling section does not say '$words'" }
    }
}

if ($IsMacOS) {
    # `defaults` takes a plist path without its .plist as the domain, which keeps the real
    # com.apple.WindowManager untouched and makes the script skip the WindowManager restart.
    $dir = Join-Path ([IO.Path]::GetTempPath()) "dockflip-uninstall-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $dir | Out-Null
    $domain = Join-Path $dir 'WindowManager'

    # 'Continue' in these two: a missing key or domain is an answer here, not an error.
    function Read-Key([string]$Key) {
        $ErrorActionPreference = 'Continue'
        $value = & defaults read $domain $Key 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        "$value".Trim()
    }

    function Invoke-Restore {
        $out = & $restore $domain
        if ($LASTEXITCODE -ne 0) { throw "restore-edge-tiling.sh exited with $LASTEXITCODE" }
        "$out"
    }

    # Through `defaults`, not by deleting the file: cfprefsd would keep serving its cached copy.
    function Reset-Domain {
        $ErrorActionPreference = 'Continue'
        & defaults delete $domain 2>$null | Out-Null
    }

    try {
        Test 'the script is executable, as make runs it' {
            # /bin/test by path: PowerShell names are case-blind, so a bare `test` is this file's Test.
            & /bin/test -x $restore
            if ($LASTEXITCODE -ne 0) { throw 'scripts/restore-edge-tiling.sh is not executable (git update-index --chmod=+x)' }
        }

        Test 'keys DockFlip turned off are deleted, so macOS default (on) is back' {
            Reset-Domain
            foreach ($key in Get-SwiftKeys) { & defaults write $domain $key -bool false }
            if ((Read-Key 'EnableTilingByEdgeDrag') -ne '0') { throw 'setup failed: the key does not read 0' }
            $out = Invoke-Restore
            foreach ($key in Get-SwiftKeys) {
                $value = Read-Key $key
                if ($null -ne $value) { throw "$key still reads '$value'" }
            }
            if (-not $out.Contains('back on')) { throw "no message that tiling is back on: '$out'" }
        }

        Test 'a key the user left on stays as it is' {
            Reset-Domain
            & defaults write $domain EnableTilingByEdgeDrag -bool false
            & defaults write $domain EnableTopTilingByEdgeDrag -bool true
            Invoke-Restore | Out-Null
            if ($null -ne (Read-Key 'EnableTilingByEdgeDrag')) { throw 'EnableTilingByEdgeDrag was not deleted' }
            if ((Read-Key 'EnableTopTilingByEdgeDrag') -ne '1') { throw 'EnableTopTilingByEdgeDrag changed' }
        }

        Test 'nothing to restore says nothing' {
            Reset-Domain
            $out = Invoke-Restore
            if ($out.Trim()) { throw "printed '$out' with no key switched off" }
        }
    } finally {
        Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

[Console]::Out.WriteLine("uninstall tests: $script:passed passed, $script:failed failed")
if ($script:failed -gt 0) { exit 1 }
