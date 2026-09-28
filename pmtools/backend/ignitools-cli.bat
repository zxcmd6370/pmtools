@echo off
rem Ignitools standalone CLI wrapper — no Millennium needed.
rem Usage:  ignitools-cli.bat add 440 [source] | remove 440 | list | status 440 | sources
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ignitools-cli.ps1" %*
exit /b %ERRORLEVEL%
