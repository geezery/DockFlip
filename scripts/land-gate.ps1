# DockFlip's landing gate on the Hogherd farm. The farm is Windows and has no Swift, so it cannot
# build a branch itself: this pushes the commit to land/<sha> on GitHub, waits for ci.yml (build,
# tests and bundle checks on macos-26), deletes the branch and exits 0 when the run passed, 1 when
# it failed (with the compiler errors and failed tests, each line starting `error:`), 2 when the
# gate itself could not tell (gh not logged in, GitHub out of reach, no run started, timed out).
# A commit that already has a passed push run is not built again ("found already built"): main's
# head after a landing is the commit its landing built.
#
# Needs git and gh, logged in with the repo and workflow scopes (`gh auth login`); the push uses
# gh's token. Register it in Hogherd, Settings > This project > Landing:
#   Landing checks (land_checks):
#     powershell -NoProfile -ExecutionPolicy Bypass -File scripts/land-gate-tests.ps1
#     powershell -NoProfile -ExecutionPolicy Bypass -File scripts/land-gate.ps1
#   Services the checks need (land_services), so a GitHub outage holds landing instead of
#   failing the branch:
#     github.com:443 GitHub
#     api.github.com:443 GitHub API
#
# By hand: powershell -File scripts/land-gate.ps1 [-Rev <commit>] from the repository root.
# PowerShell, not sh like the other scripts: the farm runs a check through cmd, where `bash` is
# WSL's, without git's or gh's login.

param(
    [string]$Rev = 'HEAD',
    [string]$Remote = 'origin',
    [string]$Workflow = 'ci.yml',
    # Under Hogherd's landing check timeout (30 min), so the gate says why and deletes its branch
    # before the farm stops it.
    [ValidateRange(1, 240)][int]$TimeoutMinutes = 25,
    [ValidateRange(5, 300)][int]$PollSeconds = 15
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'land-gate-lib.ps1')
# gh prints UTF-8; read and write it as such (a landing has no console, hence the try).
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
$env:GH_PROMPT_DISABLED = '1'
$env:GIT_TERMINAL_PROMPT = '0'

function Say([string]$Text) { [Console]::Out.WriteLine("land-gate: $Text") }
function Stop-Gate([int]$Code, [string]$Why) {
    [Console]::Out.WriteLine("error: land-gate: $Why")
    exit $Code
}

# A native command's stdout lines and exit code. Its stderr goes straight to the log: redirecting
# it makes Windows PowerShell 5.1 turn each line into an error.
function Invoke-Tool([string]$Exe, [string[]]$Argv) {
    if (-not (Get-Command $Exe -CommandType Application -ErrorAction SilentlyContinue)) {
        Stop-Gate 2 "$Exe is not installed or not on PATH"
    }
    $out = @(& $Exe @Argv)
    [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}

# git with gh's token, which has the workflow scope a push changing .github/workflows needs.
function Invoke-Git([string[]]$Argv) {
    Invoke-Tool 'git' (@('-c', 'credential.helper=', '-c', 'credential.helper=!gh auth git-credential') + $Argv)
}

function Get-Runs([string]$Sha) {
    $r = Invoke-Tool 'gh' @('run', 'list', '--workflow', $Workflow, '--commit', $Sha, '--limit', '20',
        '--json', 'databaseId,status,conclusion,event,headBranch,url')
    if ($r.Code -ne 0) { Stop-Gate 2 "gh run list failed (exit $($r.Code)); is GitHub reachable?" }
    @(ConvertFrom-JsonList ($r.Out -join "`n"))
}

function Get-Run([string]$Id) {
    $r = Invoke-Tool 'gh' @('run', 'view', $Id, '--json', 'databaseId,status,conclusion,event,url')
    if ($r.Code -ne 0) { return $null }
    ConvertFrom-JsonList ($r.Out -join "`n")
}

# Delete land/ branches an earlier gate left when it was stopped, unless a run on one still goes.
# This commit's own is among them when a stopped gate pushed it: pushing it again unchanged would
# start no run.
function Remove-Leftovers {
    $ls = Invoke-Git @('ls-remote', '--heads', $Remote, 'land/*')
    if ($ls.Code -ne 0) { return }
    $gone = @()
    foreach ($branch in @(Get-LandBranches $ls.Out)) {
        $r = Invoke-Tool 'gh' @('run', 'list', '--workflow', $Workflow, '--branch', $branch, '--json', 'status')
        $going = @(ConvertFrom-JsonList ($r.Out -join "`n") | Where-Object { $_.status -ne 'completed' })
        if ($r.Code -eq 0 -and $going.Count -eq 0) { $gone += $branch }
    }
    if ($gone.Count -gt 0) {
        Say "deleting branches earlier gates left: $($gone -join ', ')"
        $null = Invoke-Git (@('push', '--quiet', $Remote, '--delete') + $gone)
    }
}

$resolved = Invoke-Tool 'git' @('rev-parse', '--verify', "$Rev^{commit}")
if ($resolved.Code -ne 0) { Stop-Gate 2 "no commit $Rev here" }
$sha = $resolved.Out[0].Trim()
$branch = Get-LandBranch $sha

if ((Invoke-Tool 'gh' @('auth', 'status')).Code -ne 0) {
    Stop-Gate 2 'gh is not logged in to GitHub: run gh auth login (repo and workflow scopes)'
}
$dirty = Invoke-Tool 'git' @('status', '--porcelain', '--untracked-files=no')
if ($dirty.Out.Count -gt 0) { Say "uncommitted changes here are not checked: the gate builds commit $sha" }

$start = Get-GateStart (Get-Runs $sha)
if ($start.Action -eq 'green') {
    Say "found already built: $Workflow passed on $sha ($($start.Run.url))"
    exit 0
}

$pushed = $false
try {
    $run = $start.Run
    if ($start.Action -eq 'watch') {
        Say "$Workflow already runs on $sha; waiting for it ($($run.url))"
    } else {
        Remove-Leftovers
        $push = Invoke-Git @('push', '--quiet', $Remote, "${sha}:refs/heads/$branch")
        if ($push.Code -ne 0) { Stop-Gate 2 "could not push $sha to $Remote $branch (exit $($push.Code))" }
        $pushed = $true
        Say "pushed $sha to $branch; waiting for $Workflow to start"
        # A push run shows up in a few seconds.
        $until = (Get-Date).AddMinutes(3)
        while (-not $run) {
            if ((Get-Date) -gt $until) {
                Stop-Gate 2 "no $Workflow run started for $branch in 3 min: does $Workflow at $sha run on a push to land/**?"
            }
            Start-Sleep -Seconds 5
            $run = @(Get-Runs $sha | Where-Object { $_.event -eq 'push' -and $_.headBranch -eq $branch })[0]
        }
        Say "$Workflow runs: $($run.url)"
    }

    $began = Get-Date
    $deadline = $began.AddMinutes($TimeoutMinutes)
    $status = $run.status
    while ((Get-RunOutcome $run) -eq 'running') {
        if ((Get-Date) -gt $deadline) {
            Stop-Gate 2 "$Workflow run $($run.url) is still $($run.status) after $TimeoutMinutes min"
        }
        Start-Sleep -Seconds $PollSeconds
        $now = Get-Run $run.databaseId
        if ($now) { $run = $now }
        if ($run.status -ne $status) {
            $status = $run.status
            Say "$Workflow is $status"
        }
    }

    $took = [int]((Get-Date) - $began).TotalSeconds
    if ((Get-RunOutcome $run) -eq 'green') {
        Say "$Workflow passed on $sha in $took s ($($run.url))"
        exit 0
    }
    $log = Invoke-Tool 'gh' @('run', 'view', $run.databaseId, '--log-failed')
    foreach ($line in @(ConvertTo-RedLines $log.Out)) { [Console]::Out.WriteLine($line) }
    Stop-Gate 1 "$Workflow $($run.conclusion) on $sha ($($run.url))"
} finally {
    if ($pushed) {
        $del = Invoke-Git @('push', '--quiet', $Remote, '--delete', $branch)
        if ($del.Code -ne 0) { Say "could not delete $branch on $Remote; the next gate deletes it" }
    }
}
