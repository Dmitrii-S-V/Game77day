@echo off
cd /d "%~dp0"
if not exist "C:\Godot\godot.exe" (
  echo Godot not found: C:\Godot\godot.exe
  pause
  exit /b 1
)
echo Starting 77Days... (close the game window to exit)
"C:\Godot\godot.exe" --path . 2>&1 | more
echo.
echo Game exited.
pause
