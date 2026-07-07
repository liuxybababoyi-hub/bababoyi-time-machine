# Scan photos/ folder, extract EXIF dates, generate photos.js
# Usage: Right-click -> Run with PowerShell, or .\scan-photos.ps1

$scriptDir = $PSScriptRoot
$photosDir = Join-Path $scriptDir "photos"
$outputFile = Join-Path $scriptDir "photos.js"

$extensions = @(".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".tiff", ".tif", ".heic", ".heif", ".avif")

if (-not (Test-Path $photosDir)) {
    Write-Host "[!] photos folder not found: $photosDir" -ForegroundColor Red
    Write-Host "    Please create a 'photos' folder and put your images in it."
    Read-Host "Press Enter to exit"
    exit 1
}

try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
} catch {
    Write-Host "[!] Cannot load System.Drawing (required for EXIF reading)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

$files = Get-ChildItem $photosDir -File | Where-Object { $_.Extension.ToLower() -in $extensions }

if ($files.Count -eq 0) {
    Write-Host "[!] No images found in photos folder" -ForegroundColor Yellow
    Write-Host "    Supported formats: $($extensions -join ', ')"
    Read-Host "Press Enter to exit"
    exit 0
}

$results = @()
$exifOk = 0
$fallback = 0

foreach ($f in $files) {
    $date = $null
    $source = "mtime"

    # Try EXIF via System.Drawing
    try {
        $img = [System.Drawing.Image]::FromFile($f.FullName)
        foreach ($pi in $img.PropertyItems) {
            if ($pi.Id -eq 36867) {  # DateTimeOriginal
                $date = [System.Text.Encoding]::ASCII.GetString($pi.Value).Trim([char]0)
                $source = "EXIF"
                break
            }
        }
        if (-not $date) {
            foreach ($pi in $img.PropertyItems) {
                if ($pi.Id -eq 306) {  # DateTime
                    $date = [System.Text.Encoding]::ASCII.GetString($pi.Value).Trim([char]0)
                    $source = "EXIF"
                    break
                }
            }
        }
        $img.Dispose()
    } catch {}

    # Fallback: file modification time
    if (-not $date) {
        $date = $f.LastWriteTime.ToString("yyyy:MM:dd HH:mm:ss")
        $fallback++
    } else {
        $exifOk++
    }

    # Build relative path with forward slashes
    $relPath = ($f.FullName.Substring($scriptDir.Length + 1)).Replace("\", "/")
    $displayDate = $date.Substring(0, 10).Replace(":", "-")  # "YYYY-MM-DD"

    $results += @{
        src     = $relPath
        alt     = $f.BaseName
        date    = $displayDate
        rawDate = $date
    }

    Write-Host "  [$source] $displayDate  $($f.Name)"
}

# Sort by date descending (newest first)
$results = $results | Sort-Object { $_.rawDate } -Descending

# Build entries
$entries = @()
foreach ($r in $results) {
    $src = $r.src -replace '\\', '/'
    $alt = $r.alt
    $date = $r.date
    $entries += "  { `"src`": `"$src`", `"alt`": `"$alt`", `"date`": `"$date`" }"
}

$content = @"
// Photo list for bababoyi-time-machine
// $($results.Count) photos | sorted by date (newest first) | auto-generated, re-run after adding photos
var PHOTOS = [
$($entries -join ",`n")
];
"@

# Write with UTF-8 (no BOM, same as before)
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($outputFile, $content, $utf8)

Write-Host ""
Write-Host "[OK] photos.js generated - $($results.Count) photos (EXIF: $exifOk, fallback: $fallback)" -ForegroundColor Green
