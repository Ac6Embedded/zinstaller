#!/bin/bash
BASE_DIR="$HOME/.zinstaller"
SELECTED_OS="linux"
TMP_DIR="$BASE_DIR/tmp"
MANIFEST_FILE="$TMP_DIR/manifest.sh"
DL_DIR="$TMP_DIR/downloads"
TOOLS_DIR="$BASE_DIR/tools"

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
YAML_FILE="$SCRIPT_DIR/tools.yml"

# Default values for the options
WITH_ROOT=false
WITHOUT_ROOT=false

# Function to display usage information
usage() {
  echo "Usage: $0 [--with-root] [--without-root]"
  exit 1
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --with-root)
      WITH_ROOT=true
      ;;
    --without-root)
      WITHOUT_ROOT=true
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
  shift
done

# Check for mutually exclusive arguments
if [ "$WITH_ROOT" = true ] && [ "$WITHOUT_ROOT" = true ]; then
  echo "Error: Cannot run --with-root and --without-root argument at the same time."
  usage
fi

pr_title() {
    local width=40
    local border=$(printf '%*s' "$width" | tr ' ' '-')
    for param in "$@"; do
        # Calculate left padding to center the text
        local text_length=${#param}
        local left_padding=$(((width - text_length) / 2))
        local formatted_text="$(printf '%*s%s' "$left_padding" '' "$param")"
        echo "$border"
        echo "$formatted_text"
        echo "$border"
    done
}

pr_error() {
    local index="$1"
    local message="$2"
    echo "ERROR: $message"
    return $index
}

pr_warn() {
    local message="$1"
    echo "WARN: $message"
}

# Function to download the file and check its SHA-256 hash
download_and_check_hash() {
    local source=$1
    local expected_hash=$2
    local filename=$3

    # Full path where the file will be saved
    local file_path="$DL_DIR/$filename"

    # Download the file using wget
    wget -q "$source" -O "$file_path"

    # Check if the download was successful
    if [ ! -f "$file_path" ]; then
        pr_error 1 "Error: Failed to download the file."
        exit 1
    fi

    # Compute the SHA-256 hash of the downloaded file
    local computed_hash=$(sha256sum "$file_path" | awk '{print $1}')

    # Compare the computed hash with the expected hash
    if [ "$computed_hash" == "$expected_hash" ]; then
        echo "DL: $filename downloaded successfully"
    else
        pr_error 2 "Error: Hash mismatch."
        pr_error 2 "Expected: $expected_hash"
        pr_error 2 "Computed: $computed_hash"
        exit 2
    fi
}

if [ "$WITHOUT_ROOT" = false ]; then

    pr_title "Install non portable tools"

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
        ubuntu)
            echo "This is Ubuntu."
            if [ $(lsb_release -rs | awk -F. '{print $1$2}') -ge 2004 ]; then
                echo "Ubuntu version is equal to or higher than 20.04"
            else
                pr_error 3 "Ubuntu version lower than 20.04 are not supported"
                exit 3
            fi
            sudo apt-get update
            sudo apt -y install --no-install-recommends git gperf ccache dfu-util wget xz-utils file make libsdl2-dev libmagic1
            ;;
        fedora)
            echo "This is Fedora."
            sudo dnf upgrade
            sudo dnf group install "Development Tools" "C Development Tools and Libraries"
            sudo dnf install gperf dfu-util wget which xz file SDL2-devel
            ;;
        clear-linux-os)
            echo "This is Clear Linux."
            sudo swupd update
            sudo swupd bundle-add c-basic dev-utils dfu-util dtc os-core-dev
            ;;
        arch)
            echo "This is Arch Linux."
            sudo pacman -Syu
            sudo pacman -S git cmake ninja gperf ccache dfu-util dtc wget xz file make
            ;;
        *)
            pr_error 3 "Distribution is not recognized."
            exit 3
            ;;
        esac
        else
        pr_error 3 "/etc/os-release file not found. Cannot determine distribution."
        exit 3
    fi
fi

if [ "$WITH_ROOT" = false ]; then

    mkdir -p "$TMP_DIR"
    mkdir -p "$DL_DIR"
    mkdir -p "$TOOLS_DIR"

    pr_title "YQ"
    YQ="yq"
    YQ_SOURCE=$(grep -A 10 'tool: yq' $YAML_FILE | grep -A 2 "$SELECTED_OS:" | grep 'source' | awk -F": " '{print $2}')
    YQ_SHA256=$(grep -A 10 'tool: yq' $YAML_FILE | grep -A 2 "$SELECTED_OS:" | grep 'sha256' | awk -F": " '{print $2}')
    download_and_check_hash "$YQ_SOURCE" "$YQ_SHA256" "$YQ"
    YQ="$DL_DIR/$YQ"
    chmod +x $YQ

    # Start generating the manifest file
    echo "#!/bin/bash" > $MANIFEST_FILE

    # Function to generate array entries if the tool supports the specified OS
    function generate_manifest_entries {
        local tool=$1
        local SELECTED_OS=$2

        # Using yq to parse the source and sha256 for the specific OS and tool
        source=$($YQ eval ".*_content[] | select(.tool == \"$tool\") | .os.$SELECTED_OS.source" $YAML_FILE)
        sha256=$($YQ eval ".*_content[] | select(.tool == \"$tool\") | .os.$SELECTED_OS.sha256" $YAML_FILE)

        # Check if the source and sha256 are not null (meaning the tool supports the OS)
        if [ "$source" != "null" ] && [ "$sha256" != "null" ]; then
            echo "declare -A ${tool}=()" >> $MANIFEST_FILE
            echo "${tool}[source]=\"$source\"" >> $MANIFEST_FILE
            echo "${tool}[sha256]=\"$sha256\"" >> $MANIFEST_FILE
        fi
    }

    pr_title "Parse YAML and generate manifest"

    # List all tools from the YAML file
    tools=$($YQ eval '.*_content[].tool' $YAML_FILE)

    # Loop through each tool and generate the entries
    for tool in $tools; do
        generate_manifest_entries $tool $SELECTED_OS
    done

    source $MANIFEST_FILE

    pr_title "OpenSSL"
    OPENSSL_FOLDER_NAME="openssl-1.1.1t"
    OPENSSL_ARCHIVE_NAME="openssl-1.1.1t.tar.bz2"
    download_and_check_hash ${openssl[source]} ${openssl[sha256]} "$OPENSSL_ARCHIVE_NAME"
    tar xf "$DL_DIR/$OPENSSL_ARCHIVE_NAME" -C "$TOOLS_DIR"

    pr_title "Python"
    PYTHON_FOLDER_NAME="3.10.14"
    PYTHON_ARCHIVE_NAME="cpython-3.10.14-linux-x86_64.tar.gz"
    download_and_check_hash ${python[source]} ${python[sha256]} "$PYTHON_ARCHIVE_NAME"
    tar xf "$DL_DIR/$PYTHON_ARCHIVE_NAME" -C "$TOOLS_DIR"

    pr_title "Ninja"
    NINJA_ARCHIVE_NAME="ninja-linux.zip"
    download_and_check_hash ${ninja[source]} ${ninja[sha256]} "$NINJA_ARCHIVE_NAME"
    mkdir -p "$TOOLS_DIR/ninja"
    unzip "$DL_DIR/$NINJA_ARCHIVE_NAME" -d "$TOOLS_DIR/ninja"

    pr_title "CMake"
    CMAKE_FOLDER_NAME="cmake-3.29.2-linux-x86_64"
    CMAKE_ARCHIVE_NAME="cmake-3.29.2-linux-x86_64.tar.gz"
    download_and_check_hash ${cmake[source]} ${cmake[sha256]} "$CMAKE_ARCHIVE_NAME"
    tar xf "$DL_DIR/$CMAKE_ARCHIVE_NAME" -C "$TOOLS_DIR"

    pr_title "Zephyr SDK"
    ZEPHYR_SDK_FOLDER_NAME="zephyr-sdk-0.16.5"
    ZEPHYR_SDK_ARCHIVE_NAME="zephyr-sdk-0.16.5_linux-x86_64.tar.xz"
    download_and_check_hash ${zephyr_sdk[source]} ${zephyr_sdk[sha256]} "$ZEPHYR_SDK_ARCHIVE_NAME"
    tar xf "$DL_DIR/$ZEPHYR_SDK_ARCHIVE_NAME" -C "$BASE_DIR"

    pr_title "Install Zephyr SDK"
    yes | bash "$TOOLS_DIR/$ZEPHYR_SDK_FOLDER_NAME/setup.sh"

    pr_title "Python Requirements"
    REQUIREMENTS_NAME="requirements-3.6.0"
    REQUIREMENTS_ZIP_NAME="$REQUIREMENTS_NAME".zip
    download_and_check_hash ${python_requirements[source]} ${python_requirements[sha256]} "$REQUIREMENTS_ZIP_NAME"
    unzip "$DL_DIR/$REQUIREMENTS_ZIP_NAME" -d "$TMP_DIR/"

    cmake_path="$BASE_DIR/tools/$CMAKE_FOLDER_NAME/bin"
    python_path="$BASE_DIR/tools/$PYTHON_FOLDER_NAME/bin"
    ninja_path="$BASE_DIR/tools/ninja"
    openssl_path="$BASE_DIR/tools/$OPENSSL_FOLDER_NAME"

    export PATH="$python_path:$ninja_path:$cmake_path:$openssl_path/usr/local/bin:$PATH"
    export LD_LIBRARY_PATH="$openssl_path/usr/local/lib:$LD_LIBRARY_PATH"

    pr_title "Python VENV"
    python3 -m venv $BASE_DIR/.venv
    source $BASE_DIR/.venv/bin/activate
    python3 -m pip install setuptools west py
    python3 -m pip install -r "$TMP_DIR/$REQUIREMENTS_NAME/requirements.txt" --quiet

    if ! command -v west &> /dev/null; then
    echo "West is not available. Something is wrong !!"
    else
    echo "West is available."
    fi

    env_script() {
    cat << EOF
#!/bin/bash

base_dir="\$(dirname "\$(realpath "\${BASH_SOURCE[0]}")")"
cmake_path="\$base_dir/tools/$CMAKE_FOLDER_NAME/bin"
python_path="\$base_dir/tools/$PYTHON_FOLDER_NAME/bin"
ninja_path="\$base_dir/tools/ninja"
openssl_path="\$base_dir/tools/$OPENSSL_FOLDER_NAME"

export PATH="\$python_path:\$ninja_path:\$cmake_path:\$openssl_path/usr/local/bin:\$PATH"
export LD_LIBRARY_PATH="\$openssl_path/usr/local/lib:\$LD_LIBRARY_PATH"

source \$base_dir/.venv/bin/activate

if ! command -v west &> /dev/null; then
   echo "West is not available. Something is wrong !!"
else
   echo "West is available."
fi

EOF
    }

    env_script > $BASE_DIR/env.sh

    echo "Source me: . $BASE_DIR/env.sh"
fi

#pr_title "Clean up"
#rm -rf $TMP_DIR