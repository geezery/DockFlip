# Tests for .github/workflows/release.yml: every file a release publishes for installing gets a
# SHA-256 checksum next to it and a build-provenance attestation, as docs/IT.md and SECURITY.md
# promise. Plain PowerShell, no Pester, so Windows PowerShell 5.1 and pwsh 7 run them alike:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/release-workflow-tests.ps1
#   pwsh -NoProfile -File scripts/release-workflow-tests.ps1

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
$release = Get-Content -Raw (Join-Path $root '.github/workflows/release.yml')
$it = Get-Content -Raw (Join-Path $root 'docs/IT.md')

# The Publish step's file list, as written in the workflow (with $VERSION unexpanded).
function Get-PublishedFiles {
    if ($release -notmatch 'FILES="([^"]+)"') { throw 'release.yml has no FILES="..." list in Publish' }
    @($Matches[1] -split '\s+' | Where-Object { $_ })
}

# What a user or an MDM installs: everything published except the checksums and DockFlip.dmg,
# which is a copy of DockFlip-$VERSION.dmg under a fixed name (same bytes, same digest).
function Get-Installables {
    @(Get-PublishedFiles | Where-Object { $_ -notlike '*.sha256' -and $_ -ne 'DockFlip.dmg' })
}

Test 'the dmg, the pkg and the profile are all published' {
    $names = (Get-Installables) -join ' '
    foreach ($f in 'DockFlip-$VERSION.dmg', 'DockFlip-$VERSION.pkg', 'DockFlip-Accessibility.mobileconfig') {
        if ((Get-Installables) -notcontains $f) { throw "Publish does not upload $f (it uploads: $names)" }
    }
}

Test 'every installable file is published with its .sha256' {
    $published = Get-PublishedFiles
    foreach ($f in Get-Installables) {
        if ($published -notcontains "$f.sha256") { throw "Publish uploads $f but not $f.sha256" }
    }
}

Test 'the Checksums step writes a .sha256 for every installable file' {
    if ($release -notmatch 'for f in ([^;\r\n]+); do\s+shasum -a 256 "\$f" \| tee "\$f\.sha256"') {
        throw 'release.yml has no checksum loop: for f in ...; do shasum -a 256 "$f" | tee "$f.sha256"'
    }
    $looped = @($Matches[1] -split '\s+' | Where-Object { $_ } | ForEach-Object { $_.Trim('"') })
    foreach ($f in Get-Installables) {
        if ($looped -notcontains $f) { throw "the checksum loop skips $f" }
    }
}

Test 'every installable file is attested' {
    if ($release -notmatch '(?s)subject-path: \|\r?\n(.*?)(\r?\n\s*\r?\n|\r?\n\s*- )') {
        throw 'attest-build-provenance has no multi-line subject-path'
    }
    $subjects = @($Matches[1] -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($f in Get-Installables) {
        $subject = $f.Replace('$VERSION', '${{ env.VERSION }}')
        if ($subjects -notcontains $subject) { throw "subject-path does not attest $subject" }
    }
}

Test 'docs/IT.md tells IT how to verify the pkg and the profile' {
    foreach ($f in 'DockFlip-<version>.pkg', 'DockFlip-Accessibility.mobileconfig') {
        if (-not $it.Contains("gh attestation verify $f --repo geezery/DockFlip")) { throw "IT.md has no gh attestation verify for $f" }
        if (-not $it.Contains("shasum -a 256 -c $f.sha256")) { throw "IT.md has no shasum check for $f" }
    }
}

[Console]::Out.WriteLine("release workflow tests: $script:passed passed, $script:failed failed")
if ($script:failed -gt 0) { exit 1 }
