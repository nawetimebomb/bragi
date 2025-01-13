@echo off

set ExecutableName="bragi.exe"
set DestinationFolder=".\dist"
set Command="%1"

if %Command% == "clean" (
   DEL /S /Q %DestinationFolder%
)

IF NOT EXIST %DestinationFolder% (
   MKDIR %DestinationFolder%
)

PUSHD %DestinationFolder%

odin build ../src -show-timings -use-separate-modules -out:%ExecutableName% -strict-style -vet-using-stmt -vet-using-param -vet-style -vet-semicolon -debug
rem -subsystem:windows

IF %ERRORLEVEL% NEQ 0 (
   POPD
   EXIT /b 1
)

IF %Command% == "run" (
   CALL %ExecutableName%
)

POPD
