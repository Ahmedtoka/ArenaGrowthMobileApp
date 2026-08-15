@echo off
REM ============================================================
REM  SUPERSEDED — do not use.
REM
REM  This script hardcoded its own broker settings, which is how
REM  builds ended up on a different broker than the one the server
REM  signs /broadcasting/auth with. The result is silent: auth
REM  returns 200, the subscribe is rejected as an invalid
REM  signature, and no message or typing event ever arrives.
REM
REM  Broker choice now lives in live.json ONLY. Use:
REM      scripts\build-prod.bat
REM ============================================================

echo.
echo  This script is superseded. Broker settings live in live.json.
echo  Run:  scripts\build-prod.bat
echo.
exit /b 1
