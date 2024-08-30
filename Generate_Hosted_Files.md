How hosted apps were created ?

python_requirements (all):
clone latest zephyr then:
$ mkdir requirements
$ cp zephyr/scripts/requi*.txt requirements
$ 7z a -tzip requirements-3.7.0.zip requirements

sevenz_portable (windows):
Download 7-Zip Portable from https://portableapps.com/apps/utilities/7-zip_portable
install, then create a self extracting archive: 
$ cp -r 7-ZipPortable/App/7-Zip64 7-Zip
$ 7z a -sfx 7-Zip-24.08.exe 7-Zip
