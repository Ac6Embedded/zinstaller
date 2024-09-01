# zinstaller for Zephyr Project
This tool installs Zephyr's host dependencies automatically.
It is designed to be as standalone and portable as possible to avoid polluting the host's environment and prevent conflicts. It works on Windows and Linux (coming soon on MacOS)

## Getting started on windows
### Install packages
Using powershell (not administrator)
```
$ powershell -ExecutionPolicy Bypass -File .\install.ps1
```
The script will automatically create environnement scripts in $env:USERPROFILE\.zinstaller\ that should be sources to have access to west and the other tools

### Activate west environnement
Using PowerShell:
```
$ Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
$ & "$env:USERPROFILE\.zinstaller\env.ps1"
```
Alternatively, using Command Prompt (cmd):
```
$ %USERPROFILE%\.zinstaller\env.bat
```
### Use west
```
$ west init ~/zephyrproject
$ cd ~/zephyrproject
$ west update
```

## Getting started on Linux
Currently supported on Ubuntu 20.04 or newer.
### Install packages
```
$ bash install.sh
```
### Activate west environnement
```
$ source ~/.zinstaller/env.sh
```

## Testing

Initialize and build Hello World:
```
$ bash
west init zephyrtest && cd zephyrtest && west update
$ bash
ZEPHYR_SDK_INSTALL_DIR=~/.zinstaller/zephyr-sdk-0.16.8 west build -b stm32f4_disco zephyr/samples/hello_world
```