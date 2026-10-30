# Tests for scripts/build-commit.sh, which names the commit make app writes into Info.plist
# (DockFlipCommit) and marks it -dirty when the checkout holds code that commit doesn't. Each
# test builds a small git repository in the temp folder with the script in it.
# Needs git and sh, so it runs on macOS or Linux (CI runs it on macOS). Plain PowerShell, no
# Pester, in the same shape as the other scripts/*-tests.ps1:
#   pwsh -NoProfile -File scripts/build-commit-tests.ps1

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
$source = Join-Path $PSScriptRoot 'build-commit.sh'
$script:temps = @()

function Write-File([string]$Dir, [string]$Path, [string]$Text) {
    $full = Join-Path $Dir $Path
    New-Item -ItemType Directory -Force (Split-Path $full) | Out-Null
    [IO.File]::WriteAllText($full, $Text)
}

function Invoke-Git([string]$Dir) {
    & git -C $Dir -c user.name=test -c user.email=test@example.com -c init.defaultBranch=main @args | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git $args failed in $Dir" }
}

# A folder laid out like DockFlip's checkout, with the script copied in; committed unless -NoGit.
function New-Checkout([switch]$NoGit) {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('build-commit-' + [guid]::NewGuid().ToString('N'))
    $script:temps += $dir
    Write-File $dir 'scripts/build-commit.sh' ([IO.File]::ReadAllText($source))
    Write-File $dir '.gitignore' ".DS_Store`n.build/`nbuild/`n"
    Write-File $dir 'Sources/DockFlip/main.swift' "print(1)`n"
    Write-File $dir 'Resources/en.lproj/Localizable.strings' "`"A`" = `"A`";`n"
    if (-not $NoGit) {
        Invoke-Git $dir init -q
        Invoke-Git $dir add -A
        Invoke-Git $dir commit -q -m init
    }
    $dir
}

function Get-Commit([string]$Dir) {
    $out = & sh (Join-Path $Dir 'scripts/build-commit.sh')
    if ($LASTEXITCODE -ne 0) { throw "build-commit.sh exited with $LASTEXITCODE" }
    "$out".Trim()
}

function Assert-Clean([string]$Commit) {
    if ($Commit -notmatch '^[0-9a-f]{7}$') { throw "expected a bare 7-character commit, got '$Commit'" }
}

function Assert-Dirty([string]$Commit) {
    if ($Commit -notmatch '^[0-9a-f]{7}-dirty$') { throw "expected '<commit>-dirty', got '$Commit'" }
}

try {
    Test 'a clean checkout gives the bare short commit' {
        $dir = New-Checkout
        $commit = Get-Commit $dir
        Assert-Clean $commit
        $head = (& git -C $dir rev-parse --short=7 HEAD).Trim()
        if ($commit -ne $head) { throw "expected HEAD $head, got $commit" }
    }

    Test 'an edited tracked file marks the build dirty' {
        $dir = New-Checkout
        Write-File $dir 'Sources/DockFlip/main.swift' "print(2)`n"
        Assert-Dirty (Get-Commit $dir)
    }

    Test 'a staged edit marks the build dirty' {
        $dir = New-Checkout
        Write-File $dir 'Sources/DockFlip/main.swift' "print(2)`n"
        Invoke-Git $dir add -A
        Assert-Dirty (Get-Commit $dir)
    }

    Test 'a deleted tracked file marks the build dirty' {
        $dir = New-Checkout
        Remove-Item (Join-Path $dir 'Resources/en.lproj/Localizable.strings')
        Assert-Dirty (Get-Commit $dir)
    }

    Test 'a new source file the build compiles marks it dirty' {
        $dir = New-Checkout
        Write-File $dir 'Sources/DockFlip/Extra.swift' "let x = 1`n"
        Assert-Dirty (Get-Commit $dir)
    }

    Test 'a new file in Resources marks the build dirty' {
        $dir = New-Checkout
        Write-File $dir 'Resources/fi.lproj/Localizable.strings' "`"A`" = `"B`";`n"
        Assert-Dirty (Get-Commit $dir)
    }

    Test 'build output, ignored files and stray notes leave it clean' {
        $dir = New-Checkout
        Write-File $dir 'build/DockFlip.app/Contents/Info.plist' 'x'
        Write-File $dir '.build/release/DockFlip' 'x'
        Write-File $dir 'Sources/.DS_Store' 'x'
        Write-File $dir 'build.log' 'x'
        Assert-Clean (Get-Commit $dir)
    }

    Test 'it answers the same when run from another folder' {
        $dir = New-Checkout
        Write-File $dir 'Sources/DockFlip/main.swift' "print(2)`n"
        Push-Location ([IO.Path]::GetTempPath())
        try { Assert-Dirty (Get-Commit $dir) } finally { Pop-Location }
    }

    Test 'outside a git checkout it says unknown' {
        $dir = New-Checkout -NoGit
        $commit = Get-Commit $dir
        if ($commit -ne 'unknown') { throw "expected 'unknown', got '$commit'" }
    }

    Test 'the Makefile takes COMMIT from build-commit.sh' {
        $makefile = [IO.File]::ReadAllText((Join-Path $root 'Makefile'))
        if ($makefile -notmatch '(?m)^COMMIT\s*\?=.*scripts/build-commit\.sh') {
            throw 'the Makefile does not set COMMIT from scripts/build-commit.sh'
        }
    }
} finally {
    foreach ($dir in $script:temps) { Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue }
}

[Console]::Out.WriteLine("build commit tests: $script:passed passed, $script:failed failed")
if ($script:failed -gt 0) { exit 1 }
