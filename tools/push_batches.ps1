param([int]$BatchMB = 250, [string]$Log = "$env:TEMP\push_progress.log")
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = New-Object Text.UTF8Encoding($false)
$g = 'E:\Git\cmd\git.exe'
Set-Location (Split-Path -Parent $PSScriptRoot)
Set-Content $Log '' -Encoding utf8

$files = & $g ls-files -o --exclude-standard
$groups = $files | Group-Object { ($_ -split '/')[0..([math]::Min(1, ($_ -split '/').Count - 2))] -join '/' }
$batches = @(); $cur = @(); $size = 0
foreach ($grp in $groups) {
  $s = ($grp.Group | ForEach-Object { (Get-Item -LiteralPath $_).Length } | Measure-Object -Sum).Sum
  if ($cur.Count -gt 0 -and ($size + $s) / 1MB -gt $BatchMB) { $batches += , $cur; $cur = @(); $size = 0 }
  $cur += $grp.Group; $size += $s
}
if ($cur.Count) { $batches += , $cur }

$i = 0
foreach ($b in $batches) {
  $i++
  "BATCH $i/$($batches.Count): $($b.Count) files" | Add-Content $Log -Encoding utf8
  $b | & $g add --pathspec-from-file=- 2>&1 | Out-Null
  & $g commit -q -m "Add project files ($i/$($batches.Count))" 2>&1 | Out-Null
  & $g push --progress -u origin main 2>&1 | ForEach-Object { "$_" } | Add-Content $Log -Encoding utf8
  if ($LASTEXITCODE -ne 0) { "PUSH FAILED at batch $i" | Add-Content $Log -Encoding utf8; exit 1 }
}
"ALL DONE" | Add-Content $Log -Encoding utf8

