# Дополнительные фото-материалы ambientCG (CC0, 2K-JPG): варианты коры деревьев и породы для валунов.
# Запуск: powershell -ExecutionPolicy Bypass -File tools\fetch_bark_rock.ps1
$ErrorActionPreference = "Continue"
$root = "D:\77Days"
$dl = "$root\_dl"
New-Item -ItemType Directory -Force -Path $dl | Out-Null
$godot = "C:\Godot\godot.exe"

# имя текстуры в игре -> ассет ambientCG
$map = @(
 @("bark_1","Bark007"), @("bark_2","Bark014"), @("bark_3","Bark004"),
 @("rock_a","Rock030"), @("rock_b","Rock035"), @("rock_c","Rock051")
)

foreach ($m in $map) {
  $a = $m[1]
  $dir = "$dl\$a"
  if (-not (Test-Path "$dir\done")) {
    $zip = "$dl\${a}_2K-JPG.zip"
    if (-not (Test-Path $zip)) {
      curl.exe -L -sS --ssl-no-revoke -o $zip "https://ambientcg.com/get?file=${a}_2K-JPG.zip"
    }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    tar -xf $zip -C $dir 2>$null
    if ((Get-ChildItem $dir -Filter *.jpg).Count -gt 0) {
      New-Item -ItemType File -Force -Path "$dir\done" | Out-Null
      [System.IO.File]::Delete($zip)
    } else {
      Write-Output "FAILED $a"
      continue
    }
  }
  $o = & $godot --headless --path $root --script res://tools/import_pbr.gd -- "$dir".Replace("\","/") $m[0] dir=terrain 2>&1 | Select-String "Импорт|Не найд|SCRIPT"
  Write-Output "$($m[0]) <- $a : $o"
}
Write-Output "ALL DONE"
