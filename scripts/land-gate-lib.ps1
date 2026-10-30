# The landing gate's decisions, kept apart from its git and gh calls so land-gate-tests.ps1 can
# check them. Runs on Windows PowerShell 5.1 (the Hogherd farm) and pwsh 7 (CI): plain ASCII,
# no ?? or ?: operators.

# The temporary branch a commit is pushed to; ci.yml runs on a push to land/**.
function Get-LandBranch([string]$Sha) {
    "land/$Sha"
}

# The items of a JSON array as gh prints it. Windows PowerShell 5.1 hands a parsed array on as
# one object, so the items are taken out one by one; empty output is no items.
function ConvertFrom-JsonList([string]$Text) {
    if (-not $Text -or -not $Text.Trim()) { return }
    $parsed = ConvertFrom-Json -InputObject $Text
    foreach ($item in $parsed) {
        if ($null -ne $item) { $item }
    }
}

# What to do about a commit, from ci.yml's runs on it (gh run list --json
# databaseId,status,conclusion,event,url):
#   green - a push run passed on this very commit: it is built already.
#   watch - a push run on it is still going: wait for that one.
#   push  - nothing to reuse: push the commit to its land/ branch. A red run is not reused, so a
#           landing that goes again after a runner hiccup builds afresh.
# Only push runs count: a pull_request run builds the merge with its base, not this commit.
function Get-GateStart([object[]]$Runs) {
    $push = @($Runs | Where-Object { $null -ne $_ -and $_.event -eq 'push' })
    $green = @($push | Where-Object { $_.status -eq 'completed' -and $_.conclusion -eq 'success' })
    if ($green.Count -gt 0) {
        return [pscustomobject]@{ Action = 'green'; Run = $green[0] }
    }
    $going = @($push | Where-Object { $_.status -ne 'completed' })
    if ($going.Count -gt 0) {
        return [pscustomobject]@{ Action = 'watch'; Run = $going[0] }
    }
    [pscustomobject]@{ Action = 'push'; Run = $null }
}

# A run as the gate reads it: running, green, or red (failure, cancelled, timed out, skipped...).
function Get-RunOutcome([object]$Run) {
    if ($Run.status -ne 'completed') { return 'running' }
    if ($Run.conclusion -eq 'success') { return 'green' }
    'red'
}

# The land/ branches in `git ls-remote --heads` output: what earlier gates left on the remote
# when they were stopped before they could delete theirs.
function Get-LandBranches([string[]]$LsRemote) {
    foreach ($line in $LsRemote) {
        if ($line -match '\trefs/heads/(land/\S+)$') { $Matches[1] }
    }
}

# The lines of `gh run view --log-failed` that say why a run failed, each starting `error:` so
# Hogherd's landing puts it in the red excerpt it sends the pig: Swift compiler errors with the
# runner's checkout folder cut off their paths (so they name the repository's files) and Swift
# Testing's failed expectations. With neither, the end of the log. At most $Max lines.
function ConvertTo-RedLines([string[]]$Log, [int]$Max = 40) {
    $found = New-Object System.Collections.Generic.List[string]
    $tail = New-Object System.Collections.Generic.List[string]
    foreach ($raw in $Log) {
        # "<job>\t<step>\t<timestamp> <text>"; a step's first line has a BOM before its timestamp.
        $parts = $raw -split "`t", 3
        $text = $parts[$parts.Count - 1].TrimStart([char]0xFEFF) -replace '^\d{4}-\d\d-\d\dT[\d:.]+Z ?', ''
        if (-not $text.Trim()) { continue }
        $tail.Add($text)
        $line = $null
        if ($text -match '^(?<file>\S+?):(?<at>\d+:\d+): error: (?<msg>.+)$') {
            $file = $Matches['file'] -replace '^.*?/work/[^/]+/[^/]+/', ''
            $line = "error: ${file}:$($Matches['at']): $($Matches['msg'])"
        } elseif ($text -match '(?<what>Test .+ recorded an issue at .+)$') {
            $line = "error: $($Matches['what'])"
        }
        if ($line -and -not $found.Contains($line)) { $found.Add($line) }
    }
    if ($found.Count -gt 0) {
        return @($found | Select-Object -First $Max)
    }
    $last = @($tail | Select-Object -Last $Max)
    if ($last.Count -eq 0) { return }
    "error: $($last[0])"
    $last | Select-Object -Skip 1
}
