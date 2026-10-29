@echo off
rem Gera os arquivos de download em dist\:
rem   VoiceLog-Setup-<versao>.exe   instalador para Windows
rem   VoiceLog-<versao>.apk         app para Android (celulares de 64 bits)
rem   *.sha256                      para conferir a integridade
rem Requer: Flutter, Visual Studio Build Tools (C++), Android SDK e Inno Setup 6.
setlocal
cd /d "%~dp0"

for /f "tokens=2 delims=: " %%v in ('findstr /b "version:" pubspec.yaml') do set FULLVER=%%v
for /f "tokens=1 delims=+" %%v in ("%FULLVER%") do set VERSION=%%v

set ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe
if not exist "%ISCC%" set ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe
if not exist "%ISCC%" (echo Inno Setup 6 nao encontrado. & goto :erro)

set VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe
for /f "delims=" %%d in ('call "%VSWHERE%" -latest -products * -find "VC\Redist\MSVC\*\x64\Microsoft.VC14*.CRT"') do set VCREDIST=%%d
if not defined VCREDIST (echo Runtime do Visual C++ nao encontrado. & goto :erro)

call flutter test || goto :erro
call flutter build windows --release || goto :erro
call flutter build apk --release --split-per-abi || goto :erro

if not exist dist mkdir dist
"%ISCC%" /Q /DAppVersion=%VERSION% "/DVCRedistDir=%VCREDIST%" installer\voicelog.iss || goto :erro
copy /y build\app\outputs\flutter-apk\app-arm64-v8a-release.apk dist\VoiceLog-%VERSION%.apk >nul || goto :erro

pushd dist
for %%f in (VoiceLog-Setup-%VERSION%.exe VoiceLog-%VERSION%.apk) do (
  for /f "tokens=*" %%h in ('certutil -hashfile %%f SHA256 ^| findstr /v ":"') do echo %%h  %%f> %%f.sha256
)
popd

echo.
echo Pronto: %~dp0dist
dir /b dist
exit /b 0

:erro
echo.
echo Falhou. Veja as mensagens acima.
exit /b 1
