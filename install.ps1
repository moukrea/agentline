# agentline installer for Windows (Claude Code and Codex).
#
#   irm https://raw.githubusercontent.com/moukrea/agentline/main/install.ps1 | iex
#
# agentline is a bash script, and Claude Code on Windows runs status lines
# through Git Bash: this finds Git Bash (installs Git with winget if needed),
# makes sure jq is there (winget), then runs install.sh in Git Bash, which
# downloads the latest release. Options for install.sh go in AGENTLINE_ARGS:
#
#   $env:AGENTLINE_ARGS = '--glyphs unicode'; irm …/install.ps1 | iex
#
# AGENTLINE_SOURCE (a clone or a .tar.gz) installs from there instead.
$ErrorActionPreference = 'Stop'

function Say($m) { Write-Host "agentline: $m" }
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
function Find-GitBash {
    $candidates = @($env:CLAUDE_CODE_GIT_BASH_PATH,
        "$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($git) { $candidates += Join-Path (Split-Path (Split-Path $git.Source)) 'bin\bash.exe' }
    foreach ($p in $candidates) { if ($p -and (Test-Path $p)) { return (Resolve-Path $p).Path } }
    return $null
}
function Winget-Install($id, $what) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw "$what is required and winget is not available: install $what, then run this again"
    }
    Say "installing $what (winget install $id)"
    winget install --id $id -e --source winget --accept-source-agreements --accept-package-agreements | Out-Host
    Refresh-Path
}

$bash = Find-GitBash
if (-not $bash) {
    Winget-Install 'Git.Git' 'Git for Windows (Git Bash)'
    $bash = Find-GitBash
    if (-not $bash) { throw 'Git Bash not found after installing Git: open a new terminal and run this again' }
}
& $bash -c 'command -v jq >/dev/null' | Out-Null
if ($LASTEXITCODE -ne 0) {
    Winget-Install 'jqlang.jq' 'jq'
    & $bash -c 'command -v jq >/dev/null' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'jq not found after installing it: open a new terminal and run this again' }
}

# No setup assistant here (it needs a Unix terminal): defaults, then
# `agentline configure` from Git Bash to change them.
$opts = if ($env:AGENTLINE_ARGS) { $env:AGENTLINE_ARGS } else { '' }
if ($env:AGENTLINE_SOURCE) {
    $src = ($env:AGENTLINE_SOURCE -replace '\\', '/')
    $cmd = "if [ -d '$src' ]; then exec bash '$src/install.sh' --yes $opts; else AGENTLINE_SOURCE='$src' exec bash -c 'curl -fsSL https://raw.githubusercontent.com/moukrea/agentline/main/install.sh | bash -s -- --yes $opts'; fi"
} else {
    $cmd = "curl -fsSL https://raw.githubusercontent.com/moukrea/agentline/main/install.sh | bash -s -- --yes $opts"
}
& $bash -c $cmd
if ($LASTEXITCODE -ne 0) { throw "install.sh failed (exit $LASTEXITCODE)" }  # not exit: under iex it would close the window
Say 'done. Restart Claude Code; to change the look, run "agentline configure" in Git Bash.'
