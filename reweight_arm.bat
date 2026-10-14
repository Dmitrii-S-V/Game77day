@echo off
chcp 65001 >nul
rem Пересчитать веса руки под текущие кости (assets\src\arm_rig.blend), сохранить и выгрузить в игру.
rem Перед запуском: в Blender Ctrl+S. После: в Blender Файл -> Вернуть (File -> Revert), чтобы увидеть новые веса.
"D:\ai3d\blender\blender.exe" -b "D:\77Days\assets\src\arm_rig.blend" -P "D:\77Days\scripts\ai3d\arm_reweight.py"
rem переимпорт в Godot (без него игра берёт старую модель из кэша .godot\imported)
"C:\Godot\godot.exe" --headless --path "D:\77Days" --import --quit
echo.
echo Готово: веса пересчитаны и рука выгружена в игру.
echo В Blender: Файл - Вернуть (File - Revert), чтобы увидеть результат.
pause
