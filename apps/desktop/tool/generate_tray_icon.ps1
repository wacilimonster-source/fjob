# Generates the multi-size tray icon assets/tray_icon.ico from
# assets/tray_icon.png. Windows loads tray icons through Win32
# LoadImage(IMAGE_ICON, LR_LOADFROMFILE), which accepts .ico/.bmp only; a PNG
# returns NULL and leaves the notification area blank. Re-run after changing
# the source image:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tool/generate_tray_icon.ps1
# Keep this file ASCII-only: Windows PowerShell 5 reads BOM-less scripts as ANSI.
param(
  [string]$Source = (Join-Path $PSScriptRoot '..\assets\tray_icon.png'),
  [string]$Output = (Join-Path $PSScriptRoot '..\assets\tray_icon.ico')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# 16/20/24/32 cover the system small icon at 100%-200% scaling; 40/48/64 feed
# menus and higher-DPI surfaces.
$sizes = @(16, 20, 24, 32, 40, 48, 64)

$sourcePath = (Resolve-Path -LiteralPath $Source).Path
$sourceImage = [System.Drawing.Image]::FromFile($sourcePath)
$entries = @()
try {
  foreach ($size in $sizes) {
    $bitmap = New-Object System.Drawing.Bitmap(
      $size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
      $graphics.InterpolationMode =
        [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
      $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
      $graphics.DrawImage($sourceImage, 0, 0, $size, $size)
    } finally {
      $graphics.Dispose()
    }
    $stream = New-Object System.IO.MemoryStream
    try {
      $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
      $entries += [pscustomobject]@{ Size = $size; Bytes = $stream.ToArray() }
    } finally {
      $stream.Dispose()
      $bitmap.Dispose()
    }
  }
} finally {
  $sourceImage.Dispose()
}

$outputPath = [System.IO.Path]::GetFullPath($Output)
$outputStream = [System.IO.File]::Create($outputPath)
$writer = New-Object System.IO.BinaryWriter($outputStream)
try {
  $writer.Write([uint16]0)                # reserved
  $writer.Write([uint16]1)                # type: icon
  $writer.Write([uint16]$entries.Count)   # image count
  $offset = 6 + 16 * $entries.Count
  foreach ($entry in $entries) {
    $dimension = if ($entry.Size -ge 256) { 0 } else { $entry.Size }
    $writer.Write([byte]$dimension)       # width
    $writer.Write([byte]$dimension)       # height
    $writer.Write([byte]0)                # palette colors
    $writer.Write([byte]0)                # reserved
    $writer.Write([uint16]1)              # color planes
    $writer.Write([uint16]32)             # bits per pixel
    $writer.Write([uint32]$entry.Bytes.Length)
    $writer.Write([uint32]$offset)
    $offset += $entry.Bytes.Length
  }
  foreach ($entry in $entries) {
    $writer.Write($entry.Bytes)
  }
} finally {
  $writer.Dispose()
  $outputStream.Dispose()
}

Write-Output ("wrote {0} ({1} entries, {2} bytes)" -f $outputPath, $entries.Count,
  (Get-Item -LiteralPath $outputPath).Length)
