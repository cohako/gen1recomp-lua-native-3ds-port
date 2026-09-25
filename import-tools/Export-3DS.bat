@echo off
rem Windows double-click wrapper: runs Export-3DS.ps1 next to it.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Export-3DS.ps1"
