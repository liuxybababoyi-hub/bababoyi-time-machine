# Bababoyi Time Machine - One-Click Deploy
# Right-click -> Run with PowerShell
# Scans photos, generates thumbnails, commits & pushes to GitHub

param(
    [string]$Message = "Update photos"
)

$scriptDir = $PSScriptRoot
Push-Location $scriptDir

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Time Machine - Deploy" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- Step 1: Scan photos ---
Write-Host "[1/3] Scanning photos..." -ForegroundColor Yellow
$scanScript = Join-Path $scriptDir "scan-photos.ps1"
if (Test-Path $scanScript) {
    & $scanScript
} else {
    Write-Host "[FAIL] scan-photos.ps1 not found" -ForegroundColor Red
    Pop-Location; Read-Host "Press Enter to exit"; exit 1
}
Write-Host ""

# --- Step 2: Commit ---
Write-Host "[2/3] Committing changes..." -ForegroundColor Yellow
git add -A 2>&1 | Out-Null

$status = git status --porcelain
if (-not $status) {
    Write-Host "  No changes to commit" -ForegroundColor Gray
    Write-Host ""
    Write-Host "[OK] Everything up to date!" -ForegroundColor Green
    Pop-Location; Read-Host "Press Enter to exit"; exit 0
}

Write-Host "  Changed files:" -ForegroundColor Gray
git status --short
Write-Host ""

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
$commitMsg = "$Message - $timestamp"
git commit -m "$commitMsg" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Commit failed" -ForegroundColor Red
    Pop-Location; Read-Host "Press Enter to exit"; exit 1
}
Write-Host ""

# --- Step 3: Push ---
Write-Host "[3/3] Pushing to GitHub..." -ForegroundColor Yellow
Write-Host "  (if a login window appears, sign in to GitHub)" -ForegroundColor Gray
git push 
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "[FAIL] Push failed. Check network or run: git push" -ForegroundColor Red
    Pop-Location; Read-Host "Press Enter to exit"; exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Deploy complete!" -ForegroundColor Green
Write-Host "  Wait 1-2 min, then visit:" -ForegroundColor Green
Write-Host "  https://liuxybababoyi-hub.github.io/bababoyi-time-machine/" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Green

Pop-Location
Read-Host "Press Enter to exit"
