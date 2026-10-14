# Скачивает фотореалистичные PBR-материалы ambientCG (CC0, 2K-JPG), импортирует их под имена слоёв игры.
# Запуск: powershell -ExecutionPolicy Bypass -File tools\fetch_photo_textures.ps1
# Архивы распаковываются в D:\77Days\_dl (после успешного импорта папку можно убрать).
$ErrorActionPreference = "Continue"
$root = "D:\77Days"
$dl = "$root\_dl"
New-Item -ItemType Directory -Force -Path $dl | Out-Null
$godot = "C:\Godot\godot.exe"

# цель (имя слоя), режим (blocks|terrain), ассет ambientCG
$map = @(
 @("frame","blocks","Wood082B"),
 @("planks_fresh_0","blocks","Planks037A"), @("planks_fresh_1","blocks","Planks037B"), @("planks_fresh_2","blocks","WoodFloor061"),
 @("planks_worn_0","blocks","WoodFloor065B"), @("planks_worn_1","blocks","Wood082B"), @("planks_worn_2","blocks","Wood035"),
 @("planks_rotten_0","blocks","Planks039"), @("planks_rotten_1","blocks","Wood036"), @("planks_rotten_2","blocks","PaintedWood005"),
 @("planks_dying_0","blocks","Planks038"), @("planks_dying_1","blocks","Wood040"), @("planks_dying_2","blocks","Planks038"),
 @("concrete_smooth_0","blocks","Concrete034"), @("concrete_smooth_1","blocks","Concrete046"),
 @("concrete_cracked_0","blocks","Concrete044D"), @("concrete_cracked_1","blocks","Concrete047A"),
 @("concrete_reinforced_0","blocks","Concrete042C"), @("concrete_reinforced_1","blocks","Concrete031"),
 @("concrete_dirty_0","blocks","Concrete048"), @("concrete_dirty_1","blocks","Concrete030"),
 @("door_wood_0","blocks","Wood082B"), @("door_wood_1","blocks","PaintedWood005"),
 @("door_boarded_0","blocks","Planks039"), @("door_boarded_1","blocks","Wood036"),
 @("window_frame_0","blocks","PaintedWood009C"), @("window_frame_1","blocks","Wood040"),
 @("window_boarded_0","blocks","Planks038"), @("window_boarded_1","blocks","Wood035"),
 @("boards","blocks","Planks039"), @("brass","blocks","Metal048A"),
 @("carpet_0","blocks","Carpet015"), @("carpet_1","blocks","Carpet012"), @("carpet_2","blocks","Fabric028"),
 @("grass_a","terrain","Grass003"), @("grass_b","terrain","Ground013"), @("grass_c","terrain","Ground003"),
 @("dirt_a","terrain","Ground103"), @("terrain_stone","terrain","Rock058"), @("terrain_sand","terrain","Ground080"),
 @("terrain_gravel","terrain","Gravel043"), @("road_asphalt","terrain","Asphalt033"), @("road_asphalt_rough","terrain","Road012A"),
 @("road_dirt","terrain","Ground110"), @("bark","terrain","Bark012"), @("metal_clean","terrain","Metal049A"),
 @("metal_rust","terrain","Metal063"), @("road_concrete","terrain","Concrete047A"), @("sidewalk_slab","terrain","Concrete048"),
 @("wood_planks","terrain","Planks037A")
)

$assets = $map | ForEach-Object { $_[2] } | Select-Object -Unique
foreach ($a in $assets) {
  $dir = "$dl\$a"
  if (Test-Path "$dir\done") { continue }
  $zip = "$dl\${a}_2K-JPG.zip"
  if (-not (Test-Path $zip)) {
    Write-Output "download $a"
    curl.exe -L -sS --ssl-no-revoke -o $zip "https://ambientcg.com/get?file=${a}_2K-JPG.zip"
  }
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  tar -xf $zip -C $dir
  if ((Get-ChildItem $dir -Filter *.jpg).Count -gt 0) {
    New-Item -ItemType File -Force -Path "$dir\done" | Out-Null
    [System.IO.File]::Delete($zip)
  } else {
    Write-Output "FAILED extract $a"
  }
}

foreach ($m in $map) {
  $name = $m[0]; $mode = $m[1]; $a = $m[2]
  $args2 = @("--headless","--path",$root,"--script","res://tools/import_pbr.gd","--","$dl\$a".Replace("\","/"),$name)
  if ($mode -eq "terrain") { $args2 += "dir=terrain" } else { $args2 += "size=1024" }
  $o = & $godot @args2 2>&1 | Select-String "Импорт|Не найд|SCRIPT"
  Write-Output "$name <- $a : $o"
}
Write-Output "ALL DONE"
