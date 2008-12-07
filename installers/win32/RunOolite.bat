@echo off
set BASE=%~dp0
set GNUSTEP_PATH_HANDLING=windows
set GNUSTEP_SYSTEM_ROOT=%BASE%\oolite.app
set GNUSTEP_LOCAL_ROOT=%BASE%\oolite.app
set GNUSTEP_NETWORK_ROOT=%BASE%\oolite.app
set GNUSTEP_USERS_ROOT=%BASE%\oolite.app
set HOMEPATH=%BASE%\oolite.app
"%BASE%\oolite.app\oolite.exe" %1 %2 %3 %4
