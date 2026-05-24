$ErrorActionPreference = "Stop"

function Convert-ToGitBashPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full -match '^([A-Za-z]):\\(.*)$') {
        return "/" + $matches[1].ToLowerInvariant() + "/" + ($matches[2] -replace '\\', '/')
    }
    return ($full -replace '\\', '/')
}

function Resolve-FirstPath {
    param([string[]]$Candidates)

    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$bash = Resolve-FirstPath @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files\Git\usr\bin\bash.exe"
)
if (-not $bash) {
    throw "Git Bash was not found. Install Git for Windows or run verify.sh from a shell with bash."
}

$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
$python = if ($pythonCommand) { $pythonCommand.Source } else { $null }
if (-not $python) {
    $python = Resolve-FirstPath @(
        "$env:USERPROFILE\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
    )
}
if (-not $python) {
    throw "Python was not found. Install Python or run inside Codex with the bundled runtime available."
}

$repoBash = Convert-ToGitBashPath $repoRoot
$pythonBash = Convert-ToGitBashPath $python

& $bash -lc "cd '$repoBash' && PYTHON='$pythonBash' ./verify.sh"
exit $LASTEXITCODE
