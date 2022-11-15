
@echo off
set PUB_HOSTED_URL=http://192.168.1.186:4001

@REM flutter packages pub publish --dry-run

echo y | flutter packages pub publish 

pause
