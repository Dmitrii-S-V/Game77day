@echo off
chcp 65001 >nul
rem Экспорт руки из assets\src\arm_rig.blend в игру (assets\ready\arm_fp.glb). Сначала сохраните файл в Blender (Ctrl+S).
"D:\ai3d\blender\blender.exe" -b "D:\77Days\assets\src\arm_rig.blend" -P "D:\77Days\scripts\ai3d\arm_export.py"
rem переимпорт в Godot (без него игра берёт старую модель из кэша .godot\imported)
"C:\Godot\godot.exe" --headless --path "D:\77Days" --import --quit
echo.
echo Готово. Перезапустите игру, чтобы увидеть изменения.
pause
