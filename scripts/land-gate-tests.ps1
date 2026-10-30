# Tests for land-gate-lib.ps1, the landing gate's decisions. Plain PowerShell, no Pester, so
# Windows PowerShell 5.1 on the Hogherd farm and pwsh 7 in CI run them alike:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/land-gate-tests.ps1
#   pwsh -NoProfile -File scripts/land-gate-tests.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'land-gate-lib.ps1')

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

function Expect($Actual, $Expected, [string]$What) {
    if ("$Actual" -cne "$Expected") { throw "${What}: expected <$Expected>, got <$Actual>" }
}

function Run($Status, $Conclusion, $Event = 'push', $Id = 1) {
    [pscustomobject]@{ databaseId = $Id; status = $Status; conclusion = $Conclusion; event = $Event; url = "https://example/runs/$Id" }
}

# A line of `gh run view --log-failed`.
function LogLine([string]$Text, [string]$Step = 'Build app bundle (ad-hoc signed)') {
    "build`t$Step`t2026-10-30T21:40:12.1234567Z $Text"
}

Test 'a passed push run on the commit is found already built' {
    $s = Get-GateStart @((Run 'completed' 'failure' 'push' 1), (Run 'completed' 'success' 'push' 2))
    Expect $s.Action 'green' 'action'
    Expect $s.Run.databaseId 2 'run'
}

Test 'a passed pull_request run does not count: it built the merge with its base' {
    $s = Get-GateStart @((Run 'completed' 'success' 'pull_request' 3))
    Expect $s.Action 'push' 'action'
}

Test 'a push run still going is waited for' {
    $s = Get-GateStart @((Run 'completed' 'failure' 'push' 1), (Run 'in_progress' '' 'push' 4))
    Expect $s.Action 'watch' 'action'
    Expect $s.Run.databaseId 4 'run'
}

Test 'a red run is built again, not reused' {
    $s = Get-GateStart @((Run 'completed' 'failure' 'push' 1), (Run 'completed' 'cancelled' 'push' 2))
    Expect $s.Action 'push' 'action'
}

Test 'a commit with no runs is pushed' {
    Expect (Get-GateStart @()).Action 'push' 'empty list'
    Expect (Get-GateStart $null).Action 'push' 'no list'
}

Test 'gh output parses to its items on 5.1 and 7 alike' {
    Expect (@(ConvertFrom-JsonList '[{"status":"queued"},{"status":"completed"}]').Count) 2 'two runs'
    Expect (@(ConvertFrom-JsonList '[{"status":"queued"}]')[0].status) 'queued' 'one run'
    Expect (@(ConvertFrom-JsonList '[]').Count) 0 'no runs'
    Expect (@(ConvertFrom-JsonList '').Count) 0 'no output'
    Expect (@(ConvertFrom-JsonList '{"status":"completed"}').Count) 1 'one object'
}

Test 'a run is running until it completes, then green only on success' {
    Expect (Get-RunOutcome (Run 'queued' '')) 'running' 'queued'
    Expect (Get-RunOutcome (Run 'in_progress' '')) 'running' 'in progress'
    Expect (Get-RunOutcome (Run 'completed' 'success')) 'green' 'success'
    Expect (Get-RunOutcome (Run 'completed' 'failure')) 'red' 'failure'
    Expect (Get-RunOutcome (Run 'completed' 'cancelled')) 'red' 'cancelled'
    Expect (Get-RunOutcome (Run 'completed' 'skipped')) 'red' 'skipped'
}

Test 'a compile error is an error: line naming the repository file' {
    $log = @(
        (LogLine 'Building for production...'),
        (LogLine "/Users/runner/work/DockFlip/DockFlip/Sources/DockFlip/main.swift:4:1: error: cannot find 'landGateTrial' in scope"),
        (LogLine "/Users/runner/work/DockFlip/DockFlip/Sources/DockFlip/main.swift:4:1: error: cannot find 'landGateTrial' in scope"),
        (LogLine '/Users/runner/work/DockFlip/DockFlip/Sources/DockFlipKit/App/Settings.swift:9:5: warning: var never mutated'),
        (LogLine '##[error]Process completed with exit code 1.')
    )
    $red = @(ConvertTo-RedLines $log)
    Expect $red.Count 1 'one line, duplicates and warnings dropped'
    Expect $red[0] "error: Sources/DockFlip/main.swift:4:1: cannot find 'landGateTrial' in scope" 'line'
}

Test 'a failed Swift Testing expectation is an error: line' {
    $mark = [char]0x2718
    $log = @(
        (LogLine "$mark Test `"Wraps around`" recorded an issue at SwitcherSelectionTests.swift:20:9: Expectation failed: 1 == 2" 'Unit tests'),
        (LogLine "$mark Test `"Wraps around`" failed after 0.002 seconds with 1 issue." 'Unit tests')
    )
    $red = @(ConvertTo-RedLines $log)
    Expect $red.Count 1 'lines'
    Expect $red[0] 'error: Test "Wraps around" recorded an issue at SwitcherSelectionTests.swift:20:9: Expectation failed: 1 == 2' 'line'
}

Test 'a failure with no compiler or test line shows the end of the log' {
    $log = @((LogLine 'codesign: invalid signature' 'Check bundle'), (LogLine '##[error]Process completed with exit code 1.' 'Check bundle'))
    $red = @(ConvertTo-RedLines $log)
    Expect $red.Count 2 'lines'
    Expect $red[0] 'error: codesign: invalid signature' 'first line says error:'
    Expect $red[1] '##[error]Process completed with exit code 1.' 'second line'
    Expect (@(ConvertTo-RedLines @()).Count) 0 'empty log'
}

Test 'red lines stop at the maximum' {
    $log = 1..50 | ForEach-Object { LogLine "/Users/runner/work/DockFlip/DockFlip/Sources/A.swift:${_}:1: error: e$_" }
    Expect (@(ConvertTo-RedLines $log -Max 40).Count) 40 'lines'
}

Test 'the land branches left on the remote are found in ls-remote output' {
    $ls = @(
        "1111111111111111111111111111111111111111`trefs/heads/land/1111111111111111111111111111111111111111",
        "2222222222222222222222222222222222222222`trefs/heads/main",
        "3333333333333333333333333333333333333333`trefs/heads/hogherd/land/x"
    )
    Expect (@(Get-LandBranches $ls) -join ',') 'land/1111111111111111111111111111111111111111' 'branches'
    Expect (@(Get-LandBranches @()).Count) 0 'none'
}

Test 'a commit goes to land/<sha>, which ci.yml runs on' {
    Expect (Get-LandBranch 'abc123') 'land/abc123' 'branch'
    $ci = Get-Content -Raw (Join-Path $PSScriptRoot '../.github/workflows/ci.yml')
    if ($ci -notmatch "branches: \[main, 'land/\*\*'\]") { throw "ci.yml does not run on a push to land/**" }
}

[Console]::Out.WriteLine("land-gate tests: $script:passed passed, $script:failed failed")
if ($script:failed -gt 0) { exit 1 }
