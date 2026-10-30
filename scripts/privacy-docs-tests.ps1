# Tests that SECURITY.md and docs/wiki/Privacy-and-Permissions.md name every input stream the
# code watches system-wide: each event type in a CGEvent tap mask or a global NSEvent monitor
# must have its line in both pages, so a new tap or monitor can't slip past the privacy page.
# Local monitors are left out: they only see DockFlip's own windows.
# Plain PowerShell, no Pester, so Windows PowerShell 5.1 and pwsh 7 run them alike:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/privacy-docs-tests.ps1
#   pwsh -NoProfile -File scripts/privacy-docs-tests.ps1

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

$pages = @{
    'SECURITY.md' = (Read-Text 'SECURITY.md').ToLowerInvariant()
    'docs/wiki/Privacy-and-Permissions.md' = (Read-Text 'docs/wiki/Privacy-and-Permissions.md').ToLowerInvariant()
}

# Each watched event type and the words both pages use for it.
$streams = @{
    'leftMouseDown' = 'left mouse clicks and drags'
    'leftMouseUp' = 'left mouse clicks and drags'
    'leftMouseDragged' = 'left mouse clicks and drags'
    'mouseMoved' = 'pointer movement'
    'flagsChanged' = 'modifier keys'
    'keyDown' = 'other keys'
    'keyUp' = 'other keys'
}

# Event type name -> the source files that watch it.
function Get-WatchedEvents {
    $watched = @{}
    $sources = Join-Path $root 'Sources'
    foreach ($file in Get-ChildItem -Path $sources -Recurse -Filter '*.swift') {
        $text = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
        $names = @()
        foreach ($m in [regex]::Matches($text, 'CGEventType\.(\w+)\.rawValue')) { $names += $m.Groups[1].Value }
        foreach ($m in [regex]::Matches($text, 'addGlobalMonitorForEvents\(matching:\s*(\[[^\]]*\]|\.\w+)')) {
            foreach ($n in [regex]::Matches($m.Groups[1].Value, '\.(\w+)')) { $names += $n.Groups[1].Value }
        }
        foreach ($name in $names) {
            if (-not $watched.ContainsKey($name)) { $watched[$name] = @() }
            if ($watched[$name] -notcontains $file.Name) { $watched[$name] += $file.Name }
        }
    }
    $watched
}

$watched = Get-WatchedEvents

Test 'the scan finds the Dock click tap and the snap drag monitors' {
    foreach ($f in 'DockController.swift', 'SnapController.swift') {
        if (-not $watched.ContainsKey('leftMouseDown') -or $watched['leftMouseDown'] -notcontains $f) {
            throw "no leftMouseDown found in $($f): the scan's patterns no longer match the code"
        }
    }
}

Test 'every watched event type has words in the privacy pages' {
    foreach ($name in $watched.Keys) {
        if (-not $streams.ContainsKey($name)) {
            throw "$($watched[$name] -join ', ') watches $name, which neither page describes: add it to SECURITY.md and docs/wiki/Privacy-and-Permissions.md, then to `$streams here"
        }
    }
}

foreach ($page in $pages.Keys) {
    Test "$page names every watched input stream" {
        foreach ($name in $watched.Keys) {
            if (-not $streams.ContainsKey($name)) { continue }
            if (-not $pages[$page].Contains($streams[$name])) {
                throw "$page does not mention '$($streams[$name])' ($name, watched in $($watched[$name] -join ', '))"
            }
        }
    }
}

[Console]::Out.WriteLine("privacy docs tests: $script:passed passed, $script:failed failed")
if ($script:failed -gt 0) { exit 1 }
