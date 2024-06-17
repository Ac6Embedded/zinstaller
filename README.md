# zinstaller
This tool installs the host dependencies

# Getting started on windows
## Install packages
Using powershell (not administrator)
```
$ powershell -ExecutionPolicy Bypass -File .\install.ps1
```
The script will automatically create environnement scripts in $env:USERPROFILE\.zinstaller\ that should be sources to have access to west and the other tools

## Activate west environnement using Powershell
```
$ Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
$ & "$env:USERPROFILE\.zinstaller\env.ps1"
```
## Activate west environnement using Powershell
```
$ %USERPROFILE%\.zinstaller\env.bat
```
## Use west
```
$ west init ~/zephyrproject
$ cd ~/zephyrproject
$ west update
```
# Getting started on Linux
(Only ubuntu >= 20.04 for now)
## Install packages
```
$ bash install.sh
```
## Activate west environnement
```
$ source ~/.zinstaller/env.sh
```
