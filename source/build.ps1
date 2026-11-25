# Builds both versions of the game from impostor.src.html + words.csv:
#   impostor.html  -> the claude.ai artifact
#   site\          -> the GitHub Pages app (index.html, peer-to-peer play, icons, offline)
param([string]$Out = '')
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$enc = New-Object Text.UTF8Encoding $false
$read = { param($p) [IO.File]::ReadAllText((Join-Path $root $p), [Text.Encoding]::UTF8) }

$rows = Get-Content -Encoding UTF8 (Join-Path $root 'words.csv') | Select-Object -Skip 1 | Where-Object { $_.Trim() } |
  ForEach-Object { ,@($_.Split(',') | ForEach-Object { $_.Trim() }) }
$json = (ConvertTo-Json -InputObject @($rows) -Compress -Depth 3).Replace('<', '<')
$page = (& $read 'impostor.src.html').Replace('/*WORDS*/', $json)
[IO.File]::WriteAllText((Join-Path $root 'impostor.html'), $page, $enc)

$site = if ($Out) { $Out } else { Join-Path $root 'site' }
New-Item -ItemType Directory -Force $site | Out-Null
$head = (& $read 'web\head.html').Replace('/*PEERDB*/', (& $read 'web\peerdb.js'))
$webPage = $page.Replace('<meta name="claude:viewport-fit-sides" content="cover">', '')
[IO.File]::WriteAllText((Join-Path $site 'index.html'), $head + $webPage + (& $read 'web\foot.html'), $enc)
Copy-Item (Join-Path $root 'web\manifest.webmanifest'), (Join-Path $root 'web\sw.js') $site -Force

# App icons: the pink carnival mask on sun yellow
Add-Type -AssemblyName System.Drawing
function New-Icon([int]$size, [string]$path) {
  $bmp = New-Object Drawing.Bitmap $size, $size
  $g = [Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.Clear([Drawing.Color]::FromArgb(255, 255, 212, 0))
  $s = $size / 64.0
  $ink = [Drawing.Color]::FromArgb(255, 27, 11, 58)
  $pink = [Drawing.Color]::FromArgb(255, 230, 0, 126)
  $yellow = [Drawing.Color]::FromArgb(255, 255, 212, 0)
  $mask = {
    param([float]$dx, [float]$dy)
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $o = 9; $yo = 16
    $pts = @(
      @(3,7, 12,2, 22,3, 32,10), @(32,10, 42,3, 52,2, 61,7),
      @(61,7, 63,18, 59,28, 49,30), @(49,30, 41,31, 36,27, 32,22),
      @(32,22, 28,27, 23,31, 15,30), @(15,30, 5,28, 1,18, 3,7))
    foreach ($b in $pts) {
      $p.AddBezier((($b[0] * 0.8 + $o) * $s + $dx), (($b[1] * 0.8 + $yo) * $s + $dy), (($b[2] * 0.8 + $o) * $s + $dx), (($b[3] * 0.8 + $yo) * $s + $dy),
                   (($b[4] * 0.8 + $o) * $s + $dx), (($b[5] * 0.8 + $yo) * $s + $dy), (($b[6] * 0.8 + $o) * $s + $dx), (($b[7] * 0.8 + $yo) * $s + $dy))
    }
    $p.CloseFigure(); return $p
  }
  $sh = & $mask (3 * $s) (3 * $s)
  $g.FillPath((New-Object Drawing.SolidBrush $ink), $sh)
  $m = & $mask 0 0
  $g.FillPath((New-Object Drawing.SolidBrush $pink), $m)
  $yb = New-Object Drawing.SolidBrush $yellow
  $g.FillEllipse($yb, [float]((19 * 0.8 + 9 - 5.2) * $s), [float]((16 * 0.8 + 16 - 3.4) * $s), [float](10.4 * $s), [float](6.8 * $s))
  $g.FillEllipse($yb, [float]((45 * 0.8 + 9 - 5.2) * $s), [float]((16 * 0.8 + 16 - 3.4) * $s), [float](10.4 * $s), [float](6.8 * $s))
  $bmp.Save($path, [Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
}
New-Icon 192 (Join-Path $site 'icon-192.png')
New-Icon 512 (Join-Path $site 'icon-512.png')
New-Icon 180 (Join-Path $site 'apple-touch-icon.png')
"built: impostor.html, site\ ($((Get-ChildItem $site).Name -join ', '))"
