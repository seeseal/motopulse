@echo off
cd /d C:\Users\cecil\motopulse
call C:\flutter\bin\flutter.bat pub get > build_v140_log.txt 2>&1
call C:\flutter\bin\flutter.bat build apk --release --target-platform android-arm64 >> build_v140_log.txt 2>&1
echo BUILD_EXIT_CODE=%ERRORLEVEL% >> build_v140_log.txt
