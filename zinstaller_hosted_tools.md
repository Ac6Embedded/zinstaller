# Hosted Tools Creation Guide

This is a step-by-step explanation of how we created the tools that we host and that are used by `zinstaller`. You can also compile these tools manually and use the version you want.

## Python Requirements

Clone the latest Zephyr repository:
```bash
git clone https://github.com/zephyrproject-rtos/zephyr.git
cd zephyr
```

Create a requirements directory:
```bash
mkdir requirements
```

Copy the requirements files:
```bash
cp zephyr/scripts/requirements*.txt requirements/
```

Package the requirements:
```bash
7z a -tzip requirements-3.7.0.zip requirements
```

## 7-Zip Portable (Windows)

Download and install 7-Zip Portable from [PortableApps.com](https://portableapps.com/apps/utilities/7-zip_portable).

Create a self-extracting archive:
```bash
cp -r 7-ZipPortable/App/7-Zip64 7-Zip
7z a -sfx 7-Zip-24.08.exe 7-Zip
```

## OpenSSL (libssl-1) (Linux)

Download the OpenSSL source:
```bash
wget https://www.openssl.org/source/openssl-1.1.1t.tar.gz
```

Extract the source:
```bash
tar xf openssl-1.1.1t.tar.gz
```

Rename and package the source:
```bash
mv out/ openssl-1.1.1t
tar cjf openssl-1.1.1t.tar.bz2 openssl-1.1.1t
```

## Portable Python (Linux)

This setup is based on the [portable-python](https://github.com/codrsquad/portable-python) project.

Install the required dependencies:
```bash
sudo apt-get install python3-pip python3-setuptools python3-tk libffi-dev \\
libgdbm-compat-dev libbz2-dev libreadline-dev libncurses-dev libssl-dev \\
libsqlite3-dev libdb-dev libgdbm-dev tk-dev tcl-dev
```

Create a virtual environment:
```bash
/usr/bin/python3 -m venv /tmp/pp
```

Install portable-python:
```bash
/tmp/pp/bin/python -m pip install portable-python
```

Inspect the Python installation:
```bash
/tmp/pp/bin/portable-python inspect /usr/bin/python3
```
Ensure that all necessary modules, including `_ssl` and `_tkinter`, are installed.

Build portable Python:
```bash
/tmp/pp/bin/portable-python build 3.11.9
```