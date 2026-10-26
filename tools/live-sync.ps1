# live-sync v1.0
# Keeps Studio in sync with the scripts Claude pushes: starts `rojo serve` and pulls the branch
# from GitHub every few seconds. Leave it running; connect Studio with Plugins -> Rojo -> Connect.
#
#   powershell -ExecutionPolicy Bypass -File tools\live-sync.ps1
#
# Needs git and rojo (rojo.exe next to this repo's default.project.json, or on PATH).
# Changes made to the scripts by hand in Studio get overwritten by the next sync.

param(
	[string]$Branch = "claude/beautiful-allen-i99pdk",
	[int]$Every = 15   # seconds between checks
)

$repo = Split-Path $PSScriptRoot
Set-Location $repo

$rojo = if (Test-Path (Join-Path $repo "rojo.exe")) { Join-Path $repo "rojo.exe" } else { (Get-Command rojo -ErrorAction SilentlyContinue).Source }
if (-not $rojo) { throw "rojo not found: put rojo.exe in $repo (from github.com/rojo-rbx/rojo/releases)" }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git not found: winget install Git.Git, then open a new PowerShell window" }

git fetch origin $Branch
git checkout $Branch
git pull --ff-only origin $Branch

$server = Start-Process $rojo -ArgumentList "serve" -NoNewWindow -PassThru
Write-Host "`nRojo is running. In Studio: Plugins -> Rojo -> Connect. Checking GitHub every $Every s (Ctrl+C to stop).`n"
try {
	while ($true) {
		Start-Sleep -Seconds $Every
		$before = git rev-parse HEAD
		git pull --ff-only --quiet origin $Branch 2>$null
		if ($LASTEXITCODE -ne 0) {
			Write-Warning "Couldn't pull (offline, or files changed here by hand?). Trying again in $Every s."
			continue
		}
		$after = git rev-parse HEAD
		if ($before -ne $after) {
			Write-Host ("{0}  updated: {1}" -f (Get-Date -Format "HH:mm:ss"), (git log -1 --format=%s))
		}
	}
} finally {
	Stop-Process -Id $server.Id -ErrorAction SilentlyContinue
}
