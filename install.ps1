param (
    [string]$InstallDir = "$env:USERPROFILE\.zinstaller",
    [switch]$OnlyCheck,
    [switch]$ReinstallVenv
)

#$BaseDir = $PWD.Path
$BaseDirectory = Join-Path -Path $env:USERPROFILE -ChildPath ".zinstaller"
$SelectedOperatingSystem = "windows"

$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptDirectory = Split-Path -Parent $ScriptPath

function Show-Help {
    $helpText = @"
Usage: install.ps1 [options] [InstallDir]

Options:
  -h, --help, /?         Show this help message and exit.
  -OnlyCheck             Perform only a check for required software packages without installing.
  -InstallSdk            Additionally install the SDK after installing the packages.
  -ReinstallVenv         Remove .venv folder, create a new .venv, install requirements and west

Arguments:
  InstallDir             Optional. The directory where the Zephyr environment will be installed. Defaults to '$env:USERPROFILE\.zinstaller'.

Examples:
  install.ps1
  install.ps1 "C:\my\install\path"
  install.ps1 -OnlyCheck
  install.ps1 -ReinstallVenv
  install.ps1 "C:\my\install\path" -OnlyCheck
"@
    Write-Host $helpText
}

# Check for help flag
if ($args.Count -gt 0 -and ($args[0] -eq "-h" -or $args[0] -eq "--help" -or $args[0] -eq "/?")) {
    Show-Help
    exit
}

# Check if an install directory argument is provided
if ($args.Count -gt 0) {
    $InstallDirectory = Join-Path -Path $InstallDir -ChildPath ".zinstaller"
} else {
    $InstallDirectory = $BaseDirectory
}

$TemporaryDirectory = "$InstallDirectory\tmp"
$YamlFilePath = "$ScriptDirectory\tools.yml"
$ManifestFilePath = "$TemporaryDirectory\manifest.ps1"
$DownloadDirectory = "$TemporaryDirectory\downloads"
$WorkDirectory = "$TemporaryDirectory\workdir"
$ToolsDirectory = "$InstallDirectory\tools"

function Print-Title {
    param (
        [string[]]$Params
    )
    
    $Width = 40
    $Border = "-" * $Width

    foreach ($Param in $Params) {
        $TextLength = $Param.Length
        $LeftPadding = [math]::Floor(($Width - $TextLength) / 2)
        $FormattedText = (" " * $LeftPadding) + $Param
        Write-Output $Border
        Write-Output $FormattedText
        Write-Output $Border
    }
}

function Print-Error {
    param (
        [int]$Index,
        [string]$Message
    )

    Write-Output "ERROR: $Message"
    return $Index
}

function Print-Warning {
    param (
        [string]$Message
    )

    Write-Output "WARN: $Message"
}

function Install-PythonVenv {
    param (
        [string]$InstallDirectory,
        [string]$WorkDirectory,
        [string]$RequirementName
    )
	
    Print-Title "Requirements"
	$RequirementName = "requirements-3.6.0"
    $RequirementZipName =  $RequirementName + ".zip"
    Download-FileWithHashCheck $python_requirements_array[0] $python_requirements_array[1] $RequirementZipName
    Extract-ArchiveFile -ZipFilePath "$DownloadDirectory\$RequirementZipName" -DestinationDirectory "$WorkDirectory"

    python -m venv "$InstallDirectory\.venv"
    . "$InstallDirectory\.venv\Scripts\Activate.ps1"
    python -m pip install setuptools wheel west --quiet
    python -m pip install -r "$WorkDirectory\$RequirementName\requirements.txt" --quiet
}



if (! $OnlyCheck -or $ReinstallVenv) {

    # Create directories if they do not exist, and suppress output
    New-Item -Path $InstallDirectory -ItemType Directory -Force > $null 2>&1
    New-Item -Path $TemporaryDirectory -ItemType Directory -Force > $null 2>&1
    New-Item -Path $DownloadDirectory -ItemType Directory -Force > $null 2>&1
    New-Item -Path $WorkDirectory -ItemType Directory -Force > $null 2>&1
    New-Item -Path $ToolsDirectory -ItemType Directory -Force > $null 2>&1
    
    $UseWget = $false
    
    function Download-FileWithHashCheck {
        param (
            [string]$SourceUrl,
            [string]$ExpectedHash,
            [string]$Filename
        )
    
        # Full path where the file will be saved
        $FilePath = Join-Path -Path $DownloadDirectory -ChildPath $Filename
    
        Write-Output "Downloading: $Filename ..."
    
        if ($UseWget) {
            # Using wget for downloading
            & $Wget -q $SourceUrl -O $FilePath
        } else {
            # Using Invoke-WebRequest for downloading
            Invoke-WebRequest -Uri $SourceUrl -OutFile $FilePath -ErrorAction Stop
        }   
        # Check if the download was successful
        if (-Not (Test-Path -Path $FilePath)) {
            Print-Error 1 "Error: Failed to download the file."
            exit 1
        }
    
        # Compute the SHA-256 hash of the downloaded file
        $ComputedHash = Get-FileHash -Path $FilePath -Algorithm SHA256 | Select-Object -ExpandProperty Hash
    
        # Compare the computed hash with the expected hash
        if ($ComputedHash -eq $ExpectedHash) {
            Write-Output "DL: $Filename downloaded successfully"
        } else {
            Print-Error 2 "Error: Hash mismatch."
            Print-Error 2 "Expected: $ExpectedHash"
            Print-Error 2 "Computed: $ComputedHash"
            exit 2
        }
    }
    
    function Test-FileExistence {
        param (
            [string]$FilePath  # Path to the file to check
        )
        
        if (-Not (Test-Path -Path $FilePath)) {
            Print-Error 3 "File does not exist: $FilePath"
            exit 3
        }
        else {
            Write-Output "File exists: $FilePath"
        }
    }
    
    # Function to generate manifest entries
    function New-ManifestEntry {
        Param(
            [string]$Tool,
            [string]$OperatingSystem
        )
        # Using yq to parse the source and sha256 for the specific OS and tool
        $Source = & $Yq eval ".*_content[] | select(.tool == `"`"`"$Tool`"`"`") | .os.$OperatingSystem.source" $YamlFilePath
        $Sha256 = & $Yq eval ".*_content[] | select(.tool == `"`"`"$Tool`"`"`") | .os.$OperatingSystem.sha256" $YamlFilePath
    
        # Check if the source and sha256 are not null (meaning the tool supports the OS)
        if ($Source -ne 'null' -and $Sha256 -ne 'null') {
            $ManifestEntry = @"
`$${Tool}_array =  @('$Source','$Sha256')

"@
            Add-Content $ManifestFilePath $ManifestEntry
        }
    }
    
    function Extract-ArchiveFile {
        param (
            [string]$ZipFilePath,    
            [string]$DestinationDirectory
        )
        
        # Ensure the destination directory exists
        New-Item -Path $DestinationDirectory -ItemType Directory -Force > $null
    
        # Extract the file silently
        & $SevenZ x "$ZipFilePath" -o"$DestinationDirectory" -y -bso0 -bsp0
    
        if ($LastExitCode -eq 0) {
            Write-Output "Extraction successful: $ZipFilePath"
        } else {
            Print-Error $LastExitCode "Failed to extract $ZipFilePath"
        }
    }
    
    # Download and verify yq
    Print-Title "YQ"
    $YqExecutable = "yq.exe"
    
    # Read the content of the YAML file
    $YamlContent = Get-Content -Path $YamlFilePath
    
    # Initialize variables to store the source and sha256 values
    $YqSource = ""
    $YqSha256 = ""
    
    # Flag variables to track the position in the file
    $FoundTool = $false
    $FoundOS = $false
    
    # Iterate through each line of the YAML content
    foreach ($Line in $YamlContent) {
        if ($Line -match "^\s*- tool: yq") {
            $FoundTool = $true
        } elseif ($FoundTool -and $Line -match "^\s*${SelectedOperatingSystem}:") {
            $FoundOS = $true
        } elseif ($FoundOS -and $Line -match "^\s*source:") {
            $YqSource = $Line -split "source:\s*" | Select-Object -Last 1
        } elseif ($FoundOS -and $Line -match "^\s*sha256:") {
            $YqSha256 = $Line -split "sha256:\s*" | Select-Object -Last 1
            break
        }
    }
    
    Download-FileWithHashCheck $YqSource $YqSha256 $YqExecutable
    $Yq = Join-Path -Path $DownloadDirectory -ChildPath $YqExecutable
    Test-FileExistence -FilePath $Yq
    
    Print-Title "Parse YAML and generate manifest"
    "# Automatically generated by Zinstaller on Powershell" | Out-File -FilePath $ManifestFilePath
    
    # List all tools from the YAML file
    $ToolsList = & $Yq eval '.*_content[].tool' $YamlFilePath
    
    # Loop through each tool and generate the entries
    foreach ($Tool in $ToolsList) {
        New-ManifestEntry $Tool $SelectedOperatingSystem
    }
    
    # Source manifest to get the array of elements
    . $ManifestFilePath
    
    Print-Title "Wget"
    $WgetExecutableName = "wget.exe"
    Download-FileWithHashCheck $wget_array[0] $wget_array[1] $WgetExecutableName
    Test-FileExistence -FilePath "$DownloadDirectory\$WgetExecutableName"
    
    New-Item -Path "$ToolsDirectory\wget" -ItemType Directory -Force > $null 2>&1
    Copy-Item -Path "$DownloadDirectory\$WgetExecutableName" -Destination "$ToolsDirectory\wget\$WgetExecutableName"
    
    $Wget = "$ToolsDirectory\wget\$WgetExecutableName"
    
    $UseWget = $true
    
    Print-Title "7-Zip"
    
    $SevenZInstalled = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.DisplayName -like "*7-Zip*" }
    
    if ($SevenZInstalled) {
        Write-Host "7-Zip is already installed."
    } else {
        Write-Host "7-Zip is not installed. Installing now..."
        $SevenZInstallerName = "7z.exe"
        Download-FileWithHashCheck $SevenZ_array[0] $SevenZ_array[1] $SevenZInstallerName
    
        $SevenZInstallerPath = Join-Path -Path $DownloadDirectory -ChildPath $SevenZInstallerName
    
        Start-Process -FilePath $SevenZInstallerPath -ArgumentList "/S" -Wait
        Write-Host "7-Zip installation completed."
        $SevenZInstalled = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.DisplayName -like "*7-Zip*" }
        if ($SevenZInstalled) {
            Write-Host "7-Zip was installed successfully"
        } else {
            Print-Error 4 "7-Zip was not installed ! Stop here !!"
            exit 4
        }
    }
    $SevenZ = "C:\Program Files\7-Zip\7z.exe"
    Test-FileExistence -FilePath $SevenZ
    
	if ($ReinstallVenv) {
		Print-Title "Reinstalling Python VENV"
		if (Test-Path -Path "$InstallDirectory\.venv") {
			Remove-Item -Path "$InstallDirectory\.venv" -Recurse -Force
		}

		. "$BaseDirectory\env.ps1" *>$null

		Install-PythonVenv -InstallDirectory $InstallDirectory -WorkDirectory $WorkDirectory -RequirementName $RequirementName
	    Remove-Item -Path $TemporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
		exit
	}
	
    Print-Title "Gperf"
    $GperfZipName = "gperf-3.0.1-bin.zip"
    $GperfInstallDirectory = "$ToolsDirectory\gperf"
    Download-FileWithHashCheck $gperf_array[0] $gperf_array[1] $GperfZipName
    
    New-Item -Path $GperfInstallDirectory -ItemType Directory -Force > $null 2>&1
    Extract-ArchiveFile -ZipFilePath "$DownloadDirectory\$GperfZipName" -DestinationDirectory $GperfInstallDirectory
    
    Print-Title "CMake"
    $CmakeZipName = "cmake-3.28.1-windows-x86_64.zip"
    $CmakeFolderName = "cmake-3.28.1-windows-x86_64"
    Download-FileWithHashCheck $cmake_array[0] $cmake_array[1] $CmakeZipName
    Extract-ArchiveFile -ZipFilePath "$DownloadDirectory\$CmakeZipName" -DestinationDirectory $ToolsDirectory
	if (Test-Path -Path $ToolsDirectory\cmake) {
       Remove-Item -Path $ToolsDirectory\cmake -Recurse -Force
    }
    Rename-Item -Path "$ToolsDirectory\$CmakeFolderName" -NewName "cmake"
    
    Print-Title "Ninja"
    $NinjaZipName = "ninja-win.zip"
    Download-FileWithHashCheck $ninja_array[0] $ninja_array[1] $NinjaZipName
    
    $NinjaFolderPath = "$ToolsDirectory\ninja"
    New-Item -Path $NinjaFolderPath -ItemType Directory -Force > $null 2>&1
    
    Extract-ArchiveFile -ZipFilePath "$DownloadDirectory\$NinjaZipName" -DestinationDirectory $NinjaFolderPath
    
    Print-Title "Zstd"
    $ZstdZipName = "zstd-v1.5.6-win64.zip"
    Download-FileWithHashCheck $zstd_array[0] $zstd_array[1] $ZstdZipName
    Extract-ArchiveFile -ZipFilePath "$DownloadDirectory\$ZstdZipName" -DestinationDirectory $DownloadDirectory
    
    $ZstdFolderName = "zstd-v1.5.6-win64"
    $ZstdExecutable = "$DownloadDirectory\$ZstdFolderName\zstd.exe"
    
    Print-Title "DTC"
    $DtcZstName = "dtc-1.7.0-1-x86_64.pkg.tar.zst"
    $DtcZstTarName = "dtc-1.7.0-1-x86_64.pkg.tar"
    Download-FileWithHashCheck $dtc_array[0] $dtc_array[1] $DtcZstName
    
    & $ZstdExecutable --quiet -d "$DownloadDirectory\$DtcZstName" -o "$DownloadDirectory\$DtcZstTarName"
    
    $DtcFolderPath = "$ToolsDirectory\dtc"
    New-Item -Path $DtcFolderPath -ItemType Directory -Force > $null 2>&1
    Extract-ArchiveFile -ZipFilePath "$DownloadDirectory\$DtcZstTarName" -DestinationDirectory $DtcFolderPath
    
    Print-Title "msys2"
    $Msys2ZstName = "msys2-runtime-3.5.3-4-x86_64.pkg.tar.zst"
    $Msys2ZstTarName = "msys2-runtime-3.5.3-4-x86_64.pkg.tar"
    Download-FileWithHashCheck $msys2_runtime_array[0] $msys2_runtime_array[1] $Msys2ZstName
    
    & $ZstdExecutable --quiet -d "$DownloadDirectory\$Msys2ZstName" -o "$DownloadDirectory\$Msys2ZstTarName"
    
    $Msys2FolderPath = "$DownloadDirectory\msys2"
    New-Item -Path $Msys2FolderPath -ItemType Directory -Force > $null 2>&1
    Extract-ArchiveFile -ZipFilePath "$DownloadDirectory\$Msys2ZstTarName" -DestinationDirectory $Msys2FolderPath
    
    Copy-Item -Path "$Msys2FolderPath\usr\bin\msys-2.0.dll" -Destination "$DtcFolderPath\usr\bin\msys-2.0.dll"
    
    Print-Title "libyaml"
    $LibyamlName = "libyaml-0.2.5-2-x86_64"
    $LibyamlZstName = "$LibyamlName.pkg.tar.zst"
    $LibyamlZstTarName = "$LibyamlName.pkg.tar"
    Download-FileWithHashCheck $libyaml_array[0] $libyaml_array[1] $LibyamlZstName
    
    & $ZstdExecutable --quiet -d "$DownloadDirectory\$LibyamlZstName" -o "$DownloadDirectory\$LibyamlZstTarName"
    
    $LibyamlFolderPath = "$DownloadDirectory\libyaml"
    New-Item -Path $LibyamlFolderPath -ItemType Directory -Force > $null 2>&1
    Extract-ArchiveFile -ZipFilePath "$DownloadDirectory\$LibyamlZstTarName" -DestinationDirectory $LibyamlFolderPath
    
    Copy-Item -Path "$LibyamlFolderPath\usr\bin\msys-yaml-0-2.dll" -Destination "$DtcFolderPath\usr\bin\msys-yaml-0-2.dll"
    
    Print-Title "Check DTC"
    
    $DtcExecutable = "$DtcFolderPath\usr\bin\dtc.exe"
    & $DtcExecutable --version
    
    if ($LastExitCode -eq 0) {
        Write-Output "Device tree compiler was successfully installed"
    } else {
        Print-Error $LastExitCode "Failed to install device tree compiler"
    }
    
    Print-Title "Git"
    $GitSetupFilename = "PortableGit-2.45.2-64-bit.7z.exe"
    Download-FileWithHashCheck $git_array[0] $git_array[1] $GitSetupFilename
    
    $GitInstallDirectory = "$ToolsDirectory\git"
    
    # Extract and wait
    Start-Process -FilePath "$DownloadDirectory\$GitSetupFilename" -ArgumentList "-o`"$ToolsDirectory\git`" -y" -Wait
    
    Print-Title "Default Zephyr SDK"
    $SdkName = "zephyr-sdk-0.16.8"
    $SdkZipName = $SdkName + "_windows-x86_64.7z"
    Download-FileWithHashCheck $zephyr_sdk_array[0] $zephyr_sdk_array[1] $SdkZipName
    Extract-ArchiveFile -ZipFilePath "$DownloadDirectory\$SdkZipName" -DestinationDirectory "$InstallDirectory"
    
    Print-Title "Python"
    $PythonSetupFilename = "Winpython64-3.10.11.1.exe"
    Download-FileWithHashCheck $python_array[0] $python_array[1] $PythonSetupFilename
    
    $PythonFolderName = "WPy64-310111"
    $PythonInstallDirectory = "$ToolsDirectory\python"
    
    # Extract and wait
    Start-Process -FilePath "$DownloadDirectory\$PythonSetupFilename" -ArgumentList "-o`"$ToolsDirectory`" -y" -Wait
	if (Test-Path -Path $ToolsDirectory\python) {
       Remove-Item -Path $ToolsDirectory\python -Recurse -Force
    }
    Rename-Item -Path "$ToolsDirectory\$PythonFolderName" -NewName "python"
    Copy-Item -Path "$ToolsDirectory\python\python-3.10.11.amd64\python.exe" -Destination "$ToolsDirectory\python\python-3.10.11.amd64\python3.exe"

    # Update path
    $CmakePath = "$ToolsDirectory\cmake\bin"
    $DtcPath = "$ToolsDirectory\dtc\usr\bin"
    $GperfPath = "$ToolsDirectory\gperf\bin"
    $NinjaPath = "$ToolsDirectory\ninja"
    $GitPath = "$ToolsDirectory\git"
    $SevenZPath = "C:\Program Files\7-Zip"
    
    $PythonPath = "$ToolsDirectory\python\python-3.10.11.amd64;$ToolsDirectory\python\python-3.10.11.amd64\Scripts"
    $WgetPath = "$ToolsDirectory\wget"
    
    $env:PATH = "$CmakePath;$DtcPath;$GperfPath;$NinjaPath;$PythonPath;$WgetPath;$GitPath;$SevenZPath;" + $env:PATH
    
	if ($InstallSdk) {
        Print-Title "Install Default Zephyr SDK"
        & "$InstallDirectory\$SdkName\setup.cmd" /c
    }
    Print-Title "Python VENV"
    Install-PythonVenv -InstallDirectory $InstallDirectory -WorkDirectory $WorkDirectory -RequirementName $RequirementName
    
@"
@echo off
set "BASE_DIR=%~dp0"
set "TOOLS_DIR=%BASE_DIR%tools"
set "PYTHON_VENV=%BASE_DIR%.venv"

set "cmake_path=%TOOLS_DIR%\cmake\bin"
set "dtc_path=%TOOLS_DIR%\dtc\usr\bin"
set "gperf_path=%TOOLS_DIR%\gperf\bin"
set "ninja_path=%TOOLS_DIR%\ninja"
set "wget_path=%TOOLS_DIR%\wget"
set "git_path=%TOOLS_DIR%\git\bin"
set "python_path=%TOOLS_DIR%\python\python-3.10.11.amd64;%TOOLS_DIR%\python\python-3.10.11.amd64\Scripts;"
set "SevenZ_path=C:\Program Files\7-Zip"

set "PATH=%python_path%;%cmake_path%;%dtc_path%;%gperf_path%;%ninja_path%;%wget_path%;%git_path%;%SevenZ_path%;%PATH%"

call "%PYTHON_VENV%\Scripts\activate.bat"
"@ | Out-File -FilePath "$InstallDirectory\env.bat" -Encoding ASCII

@"
`$BaseDir = `"$`PSScriptRoot`"
`$ToolsDir = `"$`BaseDir\tools`"

`$cmake_path = `"$`ToolsDir\cmake\bin`"
`$dtc_path = `"$`ToolsDir\dtc\usr\bin`"
`$gperf_path = `"$`ToolsDir\gperf\bin`"
`$ninja_path = `"$`ToolsDir\ninja`"
`$git_path = `"$`ToolsDir\git\bin`"
`$SevenZ_path = `"C:\Program Files\7-Zip`"
`$python_path = `"$`ToolsDir\python\python-3.10.11.amd64;$`ToolsDir\python\python-3.10.11.amd64\Scripts`"
`$wget_path = `"$`ToolsDir\wget`"

`$env:PATH = `"`$cmake_path;`$dtc_path;`$gperf_path;`$ninja_path;`$python_path;`$wget_path;`$git_path;`$SevenZ_path;`" + `$env:PATH

. `"`$BaseDir\.venv\Scripts\Activate.ps1`"

"@ | Out-File -FilePath "$InstallDirectory\env.ps1" -Encoding ASCII

    Write-Output "using cmd: $InstallDirectory\env.bat"
    Write-Output "using powershell: $InstallDirectory\env.ps1"

    Print-Title "Clean up"
    Remove-Item -Path $TemporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue

}

# Define the list of default packages in a single location
$defaultPackages = @('python', 'cmake', 'ninja', 'git', 'gperf', 'dtc', 'wget')

function Check-Package {
    param (
        [string]$package
    )

    $versionCommand = $null

    switch ($package) {
        'python'   { $versionCommand = 'python --version' }
        'cmake'    { $versionCommand = 'cmake --version' }
        'ninja'    { $versionCommand = 'ninja --version' }
        'git'      { $versionCommand = 'git --version' }
        'gperf'    { $versionCommand = 'gperf --version' }
        'dtc'      { $versionCommand = 'dtc --version' }
        'wget'     { $versionCommand = 'wget.exe --version' }
        Default    { Write-Host "$package [NOT INSTALLED]"; return $false }
    }

    try {
        $version = Invoke-Expression $versionCommand 2>&1 | Select-Object -First 1
        switch ($package) {
            'python'   { if ($version -match 'Python (\S+)') { $version = $matches[1] } }
            'cmake'    { if ($version -match 'version (\S+)') { $version = $matches[1] } }
            'ninja'    { if ($version -match '(\S+)') { $version = $matches[0] } }
            'git'      { if ($version -match 'git version (\S+)') { $version = $matches[1] } }
            'gperf'    { if ($version -match 'GNU gperf (\S+)') { $version = $matches[1] } }
            'dtc'      { if ($version -match 'Version: DTC (\S+)') { $version = $matches[1] } }
            'wget'     { if ($version -match 'GNU Wget (\S+) built on') { $version = $matches[1] } }
        }
    } catch {
        Write-Host "$package [NOT INSTALLED]"
        return $false
    }

    Write-Host "$package [$version]"
    return $true
}

function Check-Packages {
    param (
        [string[]]$packages = $defaultPackages
    )

    $missingCount = 0

    foreach ($pkg in $packages) {
        if (-not (Check-Package -package $pkg)) {
            $missingCount++
        }
    }

    if ($missingCount -gt 0) {
        Write-Host "$missingCount package(s) are not installed."
        return -$missingCount
    } else {
        Write-Host "All specified packages are installed."
        return 0
    }
}

Print-Title "Check Installed Packages"

#it should always true, for now...
$checkInstalled = $true

if ($checkInstalled) {
    $returnCode = Check-Packages
    exit $returnCode
}


#should remove tmp dir
