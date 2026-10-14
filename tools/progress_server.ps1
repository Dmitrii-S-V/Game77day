param([int]$Port = 8777, [int]$TotalFiles = 2817, [string]$PushLog = "$env:TEMP\push_progress.log")
$repo = Split-Path -Parent $PSScriptRoot
$html = Get-Content (Join-Path $PSScriptRoot 'progress.html') -Raw -Encoding UTF8
$l = New-Object System.Net.HttpListener
$l.Prefixes.Add("http://localhost:$Port/")
$l.Start()
while ($l.IsListening) {
  $c = $l.GetContext()
  $path = $c.Request.Url.AbsolutePath
  if ($path -eq '/status') {
    $git = Get-Process git -ErrorAction SilentlyContinue | Sort-Object CPU -Descending | Select-Object -First 1
    $start = if ($git) { $git.StartTime } else { (Get-Date).AddHours(-1) }
    $objs = Get-ChildItem (Join-Path $repo '.git\objects') -Recurse -File -ErrorAction SilentlyContinue
    $new = $objs | Where-Object { $_.LastWriteTime -ge $start }
    $push = ''
    if (Test-Path $PushLog) { $push = (Get-Content $PushLog -Raw -ErrorAction SilentlyContinue) -replace "`r", "`n" }
    $pct = $null
    if ($push -match '(?s).*Writing objects:\s+(\d+)%') { $pct = [int]$Matches[1] }
    $obj = [pscustomobject]@{
      gitRunning = [bool]$git
      cpu        = if ($git) { [math]::Round($git.CPU, 1) } else { 0 }
      lock       = Test-Path (Join-Path $repo '.git\index.lock')
      newObjects = ($new | Measure-Object).Count
      newMB      = [math]::Round((($new | Measure-Object Length -Sum).Sum) / 1MB)
      totalFiles = $TotalFiles
      pushPct    = $pct
      pushTail   = ($push -split "`n" | Where-Object { $_ } | Select-Object -Last 2) -join ' '
      time       = (Get-Date).ToString('HH:mm:ss')
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress))
    $c.Response.ContentType = 'application/json'
  } else {
    $bytes = [Text.Encoding]::UTF8.GetBytes($html)
    $c.Response.ContentType = 'text/html; charset=utf-8'
  }
  $c.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $c.Response.Close()
}
