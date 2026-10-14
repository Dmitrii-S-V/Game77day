@echo off
cd /d "%~dp0"
echo Generating textures...
"C:\Godot\godot.exe" --headless --path . --script res://tools/gen_textures.gd | more
echo Generating models...
"C:\Godot\godot.exe" --headless --path . --script res://tools/gen_models.gd | more
echo Done.
pause
