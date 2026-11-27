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

# The logo (logo.jpg) is used only for the app icons below
Add-Type -AssemblyName System.Drawing
$logo = [Drawing.Image]::FromFile((Join-Path $root 'logo.jpg'))
function Get-Jpeg([Drawing.Image]$img, [int]$w, [int]$h, [int]$sx, [int]$sy, [int]$sw, [int]$sh, [int]$canvas = 0, [Drawing.Color]$bg = [Drawing.Color]::Black) {
  $cw = if ($canvas) { $canvas } else { $w }; $ch = if ($canvas) { $canvas } else { $h }
  $bmp = New-Object Drawing.Bitmap $cw, $ch
  $g = [Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = 'HighQualityBicubic'; $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'
  $g.Clear($bg)
  $g.DrawImage($img, (New-Object Drawing.Rectangle ([int](($cw - $w) / 2)), ([int](($ch - $h) / 2)), $w, $h), $sx, $sy, $sw, $sh, [Drawing.GraphicsUnit]::Pixel)
  $g.Dispose(); return $bmp
}
[IO.File]::WriteAllText((Join-Path $root 'impostor.html'), $page, $enc)

$site = if ($Out) { $Out } else { Join-Path $root 'site' }
New-Item -ItemType Directory -Force $site | Out-Null
$head = (& $read 'web\head.html').Replace('/*PEERDB*/', (& $read 'web\peerdb.js'))
$webPage = $page.Replace('<meta name="claude:viewport-fit-sides" content="cover">', '')
[IO.File]::WriteAllText((Join-Path $site 'index.html'), $head + $webPage + (& $read 'web\foot.html'), $enc)

# A design being tried out: preview\index.html = the same game with preview-theme.css on top (the real game is untouched)
$themeFile = Join-Path $root 'preview-theme.css'
if (Test-Path $themeFile) {
  $theme = [IO.File]::ReadAllText($themeFile, [Text.Encoding]::UTF8)
  $i = $webPage.IndexOf('</style>')
  $pv = $webPage.Substring(0, $i) + "`n" + $theme + $webPage.Substring($i)
  # the detective from the logo, cropped round, instead of the mask on the home screen
  $em = Get-Jpeg $logo 300 300 235 80 1220 1220
  $codec = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
  $ep = New-Object Drawing.Imaging.EncoderParameters 1
  $ep.Param[0] = New-Object Drawing.Imaging.EncoderParameter ([Drawing.Imaging.Encoder]::Quality), 85L
  $ms = New-Object IO.MemoryStream
  $em.Save($ms, $codec, $ep); $em.Dispose()
  $heroOld = '<div class="hero">${MASK}<h1>'
  if ($pv.IndexOf($heroOld) -lt 0) { throw 'home hero not found' }
  $pv = $pv.Replace($heroOld, '<div class="hero"><img class="emblem" alt="" src="data:image/jpeg;base64,' + [Convert]::ToBase64String($ms.ToArray()) + '"><h1>')
  # player sticker colors: cyan instead of yellow
  $pv = $pv.Replace("['#FFD400','#1B0B3A']", "['#22D3EE','#1B0B3A']")
  $pdir = Join-Path $site 'preview'
  New-Item -ItemType Directory -Force $pdir | Out-Null
  $pfoot = (& $read 'web\foot.html').Replace("navigator.serviceWorker.register('sw.js')", "navigator.serviceWorker.register('../sw.js')")
  $phead = $head.Replace('content="#FFD400"', 'content="#07152F"').Replace('href="manifest.webmanifest"', 'href="../manifest.webmanifest"').Replace('href="icon-192.png', 'href="../icon-192.png').Replace('href="apple-touch-icon.png', 'href="../apple-touch-icon.png')
  [IO.File]::WriteAllText((Join-Path $pdir 'index.html'), $phead + $pv + $pfoot, $enc)
}
Copy-Item (Join-Path $root 'web\manifest.webmanifest'), (Join-Path $root 'web\sw.js') $site -Force

# App icons: the logo, cropped square (and with room around it for round/maskable icons)
$navy = [Drawing.Color]::FromArgb(255, 7, 21, 47)
$sq = [Math]::Min($logo.Width, $logo.Height)
$top = [int](($logo.Height - $sq) / 2)
function Save-Icon([int]$size, [string]$path, [double]$fill = 1.0) {
  $d = [int]($size * $fill)
  $bmp = Get-Jpeg $logo $d $d 0 $top $sq $sq $size $navy
  $bmp.Save($path, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}
Save-Icon 192 (Join-Path $site 'icon-192.png')
Save-Icon 512 (Join-Path $site 'icon-512.png')
Save-Icon 512 (Join-Path $site 'icon-maskable.png') 0.8
Save-Icon 180 (Join-Path $site 'apple-touch-icon.png')
$logo.Dispose()
"built: impostor.html, site\ ($((Get-ChildItem $site).Name -join ', '))"
