# update-rules.ps1
# Syncs shared Cursor rules and commands from the cursor-rules repo.
# Place this script in your project's .cursor/ directory and run it to update.
# The script self-updates on each run.

$ErrorActionPreference = "Stop"

# Configuration
$repoUrl = "git@github.com:UserGeneratedLLC/cursor-rules.git"
$forceDeleteDirs = @("luau", "roblox", "vide")
$selfUpdateFiles = @("update-rules.ps1", "update-rules.sh", "update-external.ps1", "update-external.sh")

# Resolve paths: script lives at <project>/.cursor/update-rules.ps1
$cursorDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rulesDir = Join-Path $cursorDir "rules"
$commandsDir = Join-Path $cursorDir "commands"

# Temp directory for clone
$tempDir = Join-Path $env:TEMP "update-rules-$(Get-Random)"

Write-Host "Updating Cursor rules..." -ForegroundColor Cyan
Write-Host "  Repo: $repoUrl"
Write-Host "  Target: $cursorDir"

try {
    # Clone repo (shallow)
    # Note: git writes progress to stderr; temporarily allow stderr so PowerShell
    # doesn't treat it as a terminating error under $ErrorActionPreference = "Stop"
    Write-Host ""
    Write-Host "Cloning repository..." -ForegroundColor Yellow
    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    git clone --depth 1 $repoUrl $tempDir
    $ErrorActionPreference = $prevPref
    if ($LASTEXITCODE -ne 0) { throw "git clone failed with exit code $LASTEXITCODE" }
    Write-Host "  Done!" -ForegroundColor Green

    $cloneRulesDir = Join-Path $tempDir "rules"
    $cloneCommandsDir = Join-Path $tempDir "commands"

    # --- Rules: Force-delete subdirectories then copy fresh ---
    Write-Host ""
    Write-Host "Syncing rules (subdirectories)..." -ForegroundColor Yellow

    if (-not (Test-Path $rulesDir)) {
        New-Item -ItemType Directory -Path $rulesDir -Force | Out-Null
    }

    foreach ($dir in $forceDeleteDirs) {
        $targetSubdir = Join-Path $rulesDir $dir
        $sourceSubdir = Join-Path $cloneRulesDir $dir

        if (Test-Path $targetSubdir) {
            Write-Host "  Removing $dir/..." -ForegroundColor Gray
            Remove-Item -Path $targetSubdir -Recurse -Force
        }

        if (Test-Path $sourceSubdir) {
            Write-Host "  Copying $dir/..." -ForegroundColor Gray
            Copy-Item -Path $sourceSubdir -Destination $targetSubdir -Recurse
        }
    }

    Write-Host "  Done!" -ForegroundColor Green

    # --- Rules: Copy root-level files individually (preserves user files) ---
    Write-Host ""
    Write-Host "Syncing rules (root files)..." -ForegroundColor Yellow

    Get-ChildItem -Path $cloneRulesDir -File | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination (Join-Path $rulesDir $_.Name) -Force
        Write-Host "  $($_.Name)" -ForegroundColor Gray
    }

    Write-Host "  Done!" -ForegroundColor Green

    # --- Commands: Copy files individually (no hard deletes, preserves user files) ---
    if (Test-Path $cloneCommandsDir) {
        Write-Host ""
        Write-Host "Syncing commands..." -ForegroundColor Yellow

        if (-not (Test-Path $commandsDir)) {
            New-Item -ItemType Directory -Path $commandsDir -Force | Out-Null
        }

        Get-ChildItem -Path $cloneCommandsDir -File | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $commandsDir $_.Name) -Force
            Write-Host "  $($_.Name)" -ForegroundColor Gray
        }

        Write-Host "  Done!" -ForegroundColor Green
    }

    # --- Self-update: Copy update-rules scripts from repo root ---
    Write-Host ""
    Write-Host "Self-updating scripts..." -ForegroundColor Yellow

    foreach ($fileName in $selfUpdateFiles) {
        $sourceFile = Join-Path $tempDir $fileName
        if (Test-Path $sourceFile) {
            Copy-Item -Path $sourceFile -Destination (Join-Path $cursorDir $fileName) -Force
            Write-Host "  $fileName" -ForegroundColor Gray
        }
    }

    Write-Host "  Done!" -ForegroundColor Green

} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    exit 1
} finally {
    # Clean up temp directory
    if (Test-Path $tempDir) {
        Write-Host ""
        Write-Host "Cleaning up..." -ForegroundColor Gray
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "Update completed successfully!" -ForegroundColor Green
exit 0
