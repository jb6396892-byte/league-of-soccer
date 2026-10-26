@echo off
cd /d "%~dp0"
if not exist "%~dp0tools\godot\Godot_v4.5.1-stable_win64.exe" (
  echo Godot 4.5.1 is not bundled with the source repository.
  echo Import project.godot in Godot, or place the Windows executable in tools\godot.
  pause
  exit /b 1
)
start "" "%~dp0tools\godot\Godot_v4.5.1-stable_win64.exe" --editor --path "%~dp0."
