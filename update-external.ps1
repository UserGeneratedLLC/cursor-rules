# update-external.ps1
# Syncs external documentation from GitHub repos into the rules directory

$ErrorActionPreference = "Stop"

# Configuration: Owner, Repo, Branch, Subdir, Target
$repos = @(
    @{
        Owner = "luau-lang"
        Repo = "rfcs"
        Branch = "master"
        Subdir = "docs"
        Target = "rules/luau"
    },
    @{
        Owner = "Roblox"
        Repo = "creator-docs"
        Branch = "main"
        Subdir = "content"
        Target = "rules/roblox"
    },
    @{
        Owner = "centau"
        Repo = "vide"
        Branch = "main"
        Subdir = "docs"
        Target = "rules/vide"
    }
)

# Get script directory (workspace root)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Starting sync process..." -ForegroundColor Cyan

foreach ($repo in $repos) {
    $zipUrl = "https://github.com/$($repo.Owner)/$($repo.Repo)/archive/refs/heads/$($repo.Branch).zip"
    $tempZip = Join-Path $env:TEMP "sync-docs-$($repo.Repo)-$(Get-Random).zip"
    $tempExtract = Join-Path $env:TEMP "sync-docs-$($repo.Repo)-$(Get-Random)"
    $targetPath = Join-Path $scriptDir $repo.Target
    
    # After extraction, the folder will be named like "repo-branch"
    $extractedFolder = Join-Path $tempExtract "$($repo.Repo)-$($repo.Branch)"
    $sourceSubdir = Join-Path $extractedFolder $repo.Subdir

    Write-Host ""
    Write-Host "Processing: $($repo.Repo)" -ForegroundColor Yellow
    Write-Host "  Source: $($repo.Owner)/$($repo.Repo) -> $($repo.Subdir)/"
    Write-Host "  Target: $($repo.Target)/"

    try {
        # Download zip archive
        Write-Host "  Downloading archive..." -ForegroundColor Gray
        curl.exe -sL $zipUrl -o $tempZip

        # Extract zip (using tar for speed, built into Windows 10+)
        Write-Host "  Extracting..." -ForegroundColor Gray
        New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null
        tar -xf $tempZip -C $tempExtract

        # Verify source directory exists
        if (-not (Test-Path $sourceSubdir)) {
            throw "Source subdirectory '$($repo.Subdir)' not found in archive"
        }

        # Remove old target directory contents
        if (Test-Path $targetPath) {
            Write-Host "  Removing old files..." -ForegroundColor Gray
            Remove-Item -Path $targetPath -Recurse -Force
        }

        # Create target directory
        New-Item -ItemType Directory -Path $targetPath -Force | Out-Null

        # Copy new files
        Write-Host "  Copying new files..." -ForegroundColor Gray
        Copy-Item -Path "$sourceSubdir\*" -Destination $targetPath -Recurse -Force

        Write-Host "  Done!" -ForegroundColor Green

    } catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
        exit 1
    } finally {
        # Clean up temp files
        Write-Host "  Cleaning up temp files..." -ForegroundColor Gray
        if (Test-Path $tempZip) { Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tempExtract) { Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host ""
Write-Host "Sync completed successfully!" -ForegroundColor Green
