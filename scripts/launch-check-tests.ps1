# Tests for scripts/launch-check.swift, the CI step that starts DockFlip.app and holds it to
# SCOPE.md's performance budgets: ci.yml runs it after the build, its budgets are SCOPE.md's,
# and ROADMAP M0 names only checks ci.yml has. On macOS (CI) the check is also compiled and
# run against programs that must fail it.
# Plain PowerShell, no Pester, so Windows PowerShell 5.1 and pwsh 7 run them alike:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/launch-check-tests.ps1
#   pwsh -NoProfile -File scripts/launch-check-tests.ps1

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

function Read-Text([string]$Path) {
    [IO.File]::ReadAllText((Join-Path $root $Path), [Text.Encoding]::UTF8)
}

# The number a `let name = 12.0` line in launch-check.swift sets.
function Get-SwiftNumber([string]$Name) {
    $m = [regex]::Match((Read-Text 'scripts/launch-check.swift'), "(?m)^let $Name = ([0-9_.]+)")
    if (-not $m.Success) { throw "no 'let $Name = ...' in launch-check.swift" }
    [double]($m.Groups[1].Value -replace '_', '')
}

# A row of SCOPE.md's performance budget table: '| Memory (footprint) | < 50 MB |'.
function Get-ScopeBudget([string]$Metric, [string]$Unit) {
    $m = [regex]::Match((Read-Text 'SCOPE.md'), "(?m)^\| $([regex]::Escape($Metric)) \| < ([0-9.]+) $Unit \|")
    if (-not $m.Success) { throw "no '| $Metric | < N $Unit |' row in SCOPE.md" }
    [double]$m.Groups[1].Value
}

# The names of ci.yml's steps, in order.
function Get-StepNames {
    @([regex]::Matches((Read-Text '.github/workflows/ci.yml'), '(?m)^\s+- name: (.+?)\s*$') |
        ForEach-Object { $_.Groups[1].Value })
}

function Get-M0 {
    $m = [regex]::Match((Read-Text 'ROADMAP.md'), '(?ms)^## M0 [^\r\n]*\r?\n(.*?)(?=^## |\z)')
    if (-not $m.Success) { throw 'no M0 section in ROADMAP.md' }
    $m.Groups[1].Value
}

Test 'ci.yml compiles the launch check and runs it on the built app' {
    $ci = Read-Text '.github/workflows/ci.yml'
    $m = [regex]::Match($ci, '(?ms)^\s+- name: Launch check\r?\n(.*?)(?=^\s+- name: |\z)')
    if (-not $m.Success) { throw "no 'Launch check' step in ci.yml" }
    $step = $m.Groups[1].Value
    if ($step -notmatch 'swiftc -O scripts/launch-check\.swift -o build/launch-check') {
        throw "the Launch check step does not compile scripts/launch-check.swift to build/launch-check"
    }
    if ($step -notmatch 'build/launch-check build/DockFlip\.app') {
        throw 'the Launch check step does not run build/launch-check on build/DockFlip.app'
    }
}

Test 'the launch check runs after the app is built' {
    $names = Get-StepNames
    $build = [array]::IndexOf($names, 'Build app bundle (ad-hoc signed)')
    $check = [array]::IndexOf($names, 'Launch check')
    if ($build -lt 0) { throw "no 'Build app bundle (ad-hoc signed)' step in ci.yml" }
    if ($check -lt $build) { throw "'Launch check' comes before the app is built" }
}

Test 'ci.yml runs these tests' {
    if ((Read-Text '.github/workflows/ci.yml') -notmatch 'pwsh -NoProfile -File scripts/launch-check-tests\.ps1') {
        throw 'ci.yml does not run scripts/launch-check-tests.ps1'
    }
}

Test 'the memory budget is SCOPE.md''s' {
    $scope = Get-ScopeBudget 'Memory (footprint)' 'MB'
    $check = Get-SwiftNumber 'memoryBudgetMB'
    if ($check -ne $scope) { throw "launch-check.swift allows $check MB, SCOPE.md says < $scope MB" }
}

Test 'the launch budget is SCOPE.md''s' {
    $scope = Get-ScopeBudget 'Launch to usable' 's'
    $check = Get-SwiftNumber 'scopeLaunchBudgetMs'
    if ($check -ne $scope * 1000) { throw "launch-check.swift has $check ms, SCOPE.md says < $scope s" }
}

Test 'ROADMAP M0 names the launch check and its CI allowance' {
    $m0 = Get-M0
    if (-not $m0.Contains('scripts/launch-check.swift')) { throw 'ROADMAP M0 does not name scripts/launch-check.swift' }
    $m = [regex]::Match($m0, 'launch gets (\d+)')
    if (-not $m.Success) { throw "ROADMAP M0 does not say how much longer launch may take on CI ('launch gets N')" }
    $allowance = Get-SwiftNumber 'ciLaunchAllowance'
    if ([double]$m.Groups[1].Value -ne $allowance) {
        throw "ROADMAP M0 says launch gets $($m.Groups[1].Value)x on CI, launch-check.swift allows ${allowance}x"
    }
}

Test 'every check ROADMAP M0 promises is a ci.yml step' {
    $m = [regex]::Match((Get-M0), '(?m)^- GitHub Actions on `macos-26`: ([^(]+)')
    if (-not $m.Success) { throw "no '- GitHub Actions on ``macos-26``: ...' line in ROADMAP M0" }
    $promised = @($m.Groups[1].Value -split ',| and ' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne 'a' })
    $steps = @{ 'build' = 'Build app bundle (ad-hoc signed)'; 'unit tests' = 'Unit tests';
                'bundle check' = 'Check bundle'; 'a launch check' = 'Launch check' }
    $names = Get-StepNames
    foreach ($check in $promised) {
        if (-not $steps.ContainsKey($check)) { throw "ROADMAP M0 promises '$check', which this test does not know a ci.yml step for" }
        if ($names -notcontains $steps[$check]) { throw "ROADMAP M0 promises '$check', but ci.yml has no '$($steps[$check])' step" }
    }
}

# The check itself, only where there is a Swift compiler (CI's macOS runner). CI's Launch check
# step has built it already; compiling it again would add about ten seconds, so it is reused.
if ($IsMacOS -and (Get-Command swiftc -ErrorAction SilentlyContinue)) {
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('launch-check-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $temp | Out-Null
    $bin = Join-Path $root 'build/launch-check'
    try {
        $source = Join-Path $PSScriptRoot 'launch-check.swift'
        if ((Test-Path $bin) -and (Get-Item $bin).LastWriteTimeUtc -ge (Get-Item $source).LastWriteTimeUtc) {
            $compiled = $true
        } else {
            $bin = Join-Path $temp 'launch-check'
            & swiftc -O $source -o $bin
            $compiled = $LASTEXITCODE -eq 0
        }

        Test 'the launch check compiles' {
            if (-not $compiled) { throw 'swiftc could not compile scripts/launch-check.swift' }
        }

        if ($compiled) {
            Test 'a program that quits at once fails the check' {
                $out = & $bin '/usr/bin/true' | Out-String
                if ($LASTEXITCODE -ne 1) { throw "expected exit 1, got $LASTEXITCODE" }
                if ($out -notmatch '::error::Launch check: the app quit on its own') { throw "unexpected output: $out" }
            }

            Test 'a program that is not there fails the check' {
                $out = & $bin (Join-Path $temp 'missing') | Out-String
                if ($LASTEXITCODE -ne 1) { throw "expected exit 1, got $LASTEXITCODE" }
                if ($out -notmatch '::error::Launch check: could not start') { throw "unexpected output: $out" }
            }

            Test 'no target is a usage error' {
                $out = & $bin | Out-String
                if ($LASTEXITCODE -ne 2) { throw "expected exit 2, got $LASTEXITCODE" }
                if ($out -notmatch 'usage: launch-check') { throw "unexpected output: $out" }
            }
        }
    } finally {
        Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
    }
}

[Console]::Out.WriteLine("$($script:passed) passed, $($script:failed) failed")
if ($script:failed -gt 0) { exit 1 }
