# Scan photos/ folder, extract EXIF dates, generate thumbnails & photos.js
# Usage: Right-click -> Run with PowerShell, or .\scan-photos.ps1
# One-click: scans photos, makes thumbs, writes photos.js — ready to deploy

$scriptDir = $PSScriptRoot
$photosDir = Join-Path $scriptDir "photos"
$thumbDir = Join-Path $photosDir "thumbs"
$previewDir = Join-Path $photosDir "previews"
$outputFile = Join-Path $scriptDir "photos.js"
$maxThumbWidth = 800
$maxPreviewWidth = 2560
$jpegQuality = 80

$extensions = @(".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".tiff", ".tif", ".heic", ".heif", ".avif")

# --- Checks ---
if (-not (Test-Path $photosDir)) {
    Write-Host "[!] photos folder not found: $photosDir" -ForegroundColor Red
    Write-Host "    Please create a 'photos' folder and put your images in it."
    Read-Host "Press Enter to exit"
    exit 1
}

try { Add-Type -AssemblyName System.Drawing -ErrorAction Stop }
catch {
    Write-Host "[!] Cannot load System.Drawing (required)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Create thumb dir if needed
if (-not (Test-Path $thumbDir)) { New-Item -ItemType Directory -Path $thumbDir -Force | Out-Null }
if (-not (Test-Path $previewDir)) { New-Item -ItemType Directory -Path $previewDir -Force | Out-Null }

$files = Get-ChildItem $photosDir -File | Where-Object { $_.Extension.ToLower() -in $extensions }

if ($files.Count -eq 0) {
    Write-Host "[!] No images found in photos folder" -ForegroundColor Yellow
    Write-Host "    Supported formats: $($extensions -join ', ')"
    Read-Host "Press Enter to exit"
    exit 0
}

# --- Thumbnail helper ---
function New-Thumbnail($srcPath, $dstPath, $maxW, $quality) {
    try {
        $img = [System.Drawing.Image]::FromFile($srcPath)
        $w = $img.Width; $h = $img.Height
        if ($w -le $maxW) {
            # Still save as JPEG (source might be PNG)
            if ($img.RawFormat.Guid -ne [System.Drawing.Imaging.ImageFormat]::Jpeg.Guid) {
                $bmp = New-Object System.Drawing.Bitmap($w, $h)
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                $g.DrawImage($img, 0, 0, $w, $h)
                $g.Dispose(); $img.Dispose()
                $encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
                    Where-Object { $_.MimeType -eq 'image/jpeg' }
                $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
                $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
                    [System.Drawing.Imaging.Encoder]::Quality, $quality)
                $bmp.Save($dstPath, $encoder, $ep)
                $bmp.Dispose()
            } else {
                $img.Dispose()
                Copy-Item $srcPath $dstPath
            }
            return "COPY ($($w)x$h)"
        }
        $ratio = $maxW / $w
        $newH = [int]($h * $ratio)
        $bmp = New-Object System.Drawing.Bitmap($maxW, $newH)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.DrawImage($img, 0, 0, $maxW, $newH)
        $g.Dispose(); $img.Dispose()

        $encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
            Where-Object { $_.MimeType -eq 'image/jpeg' }
        $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
        $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
            [System.Drawing.Imaging.Encoder]::Quality, $quality)
        $bmp.Save($dstPath, $encoder, $ep)
        $bmp.Dispose()
        return "OK ($($w)x$h -> $($maxW)x$newH)"
    } catch {
        return "FAIL: $($_.Exception.Message)"
    }
}

# --- Main loop ---
$results = @()
$exifOk = 0; $fallback = 0
$thumbNew = 0; $thumbSkip = 0

foreach ($f in $files) {
    # --- Extract date ---
    $date = $null; $source = "mtime"
    try {
        $img = [System.Drawing.Image]::FromFile($f.FullName)
        foreach ($pi in $img.PropertyItems) {
            if ($pi.Id -eq 36867) {
                $date = [System.Text.Encoding]::ASCII.GetString($pi.Value).Trim([char]0)
                $source = "EXIF"; break
            }
        }
        if (-not $date) {
            foreach ($pi in $img.PropertyItems) {
                if ($pi.Id -eq 306) {
                    $date = [System.Text.Encoding]::ASCII.GetString($pi.Value).Trim([char]0)
                    $source = "EXIF"; break
                }
            }
        }
        $img.Dispose()
    } catch {}
    if (-not $date) { $date = $f.LastWriteTime.ToString("yyyy:MM:dd HH:mm:ss"); $fallback++ }
    else { $exifOk++ }

    # --- Thumbnail ---
    $thumbName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name) + ".jpg"
    $thumbPath = Join-Path $thumbDir $thumbName
    $thumbRel = "photos/thumbs/$thumbName"

    if (Test-Path $thumbPath) {
        $thumbSkip++
    } else {
        $thumbResult = New-Thumbnail $f.FullName $thumbPath $maxThumbWidth $jpegQuality
        Write-Host "  [thumb] $thumbResult  $thumbName"
        $thumbNew++
    }

    # --- Preview (2560px) ---
    $previewName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name) + ".jpg"
    $previewPath = Join-Path $previewDir $previewName
    $previewRel = "photos/previews/$previewName"

    if (Test-Path $previewPath) {
        Write-Host "  [preview] SKIP (exists)  $previewName"
    } else {
        $previewResult = New-Thumbnail $f.FullName $previewPath $maxPreviewWidth $jpegQuality
        Write-Host "  [preview] $previewResult  $previewName"
    }

    # --- Build result ---
    $relPath = ($f.FullName.Substring($scriptDir.Length + 1)).Replace("\", "/")
    $displayDate = $date.Substring(0, 10).Replace(":", "-")

    $results += @{
        src     = $relPath
        thumb   = $thumbRel
        preview = $previewRel
        alt     = $f.BaseName
        date    = $displayDate
        rawDate = $date
    }

    Write-Host "  [$source] $displayDate  $($f.Name)"
}

# --- Sort & write photos.js ---
$results = $results | Sort-Object { $_.rawDate } -Descending

$entries = @()
foreach ($r in $results) {
    $src = $r.src -replace '\\', '/'
    $thumb = $r.thumb -replace '\\', '/'
    $preview = $r.preview -replace '\\', '/'
    $alt = $r.alt
    $date = $r.date
    $entries += "  { `"src`": `"$src`", `"thumb`": `"$thumb`", `"preview`": `"$preview`", `"alt`": `"$alt`", `"date`": `"$date`" }"
}

$content = @"
// Photo list for bababoyi-time-machine
// $($results.Count) photos | sorted by date (newest first) | auto-generated, re-run after adding photos
var PHOTOS = [
$($entries -join ",`n")
];
"@

$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($outputFile, $content, $utf8)

Write-Host ""
Write-Host "[OK] photos.js - $($results.Count) photos (EXIF: $exifOk, mtime: $fallback)" -ForegroundColor Green
Write-Host "[OK] Thumbnails - $thumbNew new, $thumbSkip skipped" -ForegroundColor Green
