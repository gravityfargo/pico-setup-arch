#!/bin/bash

# Exit on error
set -e

# Number of cores when running make
JNUM=14

# Where will the output go?
OUTDIR="$(pwd)/pico"

# Install dependencies
GIT_DEPS="git"
SDK_DEPS="cmake gcc arm-none-eabi-gcc"
OPENOCD_DEPS=" automake autoconf base-devel texinfo libtool libftdi libusb"
VSCODE_DEPS="code"
UART_DEPS="minicom"

# Build full list of dependencies
DEPS="$GIT_DEPS $SDK_DEPS"

if [[ "$SKIP_OPENOCD" == 1 ]]; then
    echo "Skipping OpenOCD (debug support)"
else
    DEPS="$DEPS $OPENOCD_DEPS"
fi

echo "Installing Dependencies"
sudo pacman -Syu
sudo pacman -S --noconfirm $DEPS
git clone https://aur.archlinux.org/gdb-multiarch.git
echo "May need to install the GPG key with 'gpg --recv-key 92EDB04BFF325CF3'"
cd gdb-multiarch
makepkg -sri
cd ..



echo "Creating $OUTDIR"
# Create pico directory to put everything in
mkdir -p $OUTDIR
cd $OUTDIR

# Clone sw repos
GITHUB_PREFIX="https://github.com/raspberrypi/"
GITHUB_SUFFIX=".git"
SDK_BRANCH="master"

for REPO in sdk examples extras playground
do
    DEST="$OUTDIR/pico-$REPO"

    if [ -d $DEST ]; then
        echo "$DEST already exists so skipping"
    else
        REPO_URL="${GITHUB_PREFIX}pico-${REPO}${GITHUB_SUFFIX}"
        echo "Cloning $REPO_URL"
        git clone -b $SDK_BRANCH $REPO_URL

        # Any submodules
        cd $DEST
        git submodule update --init
        cd $OUTDIR

        # Define PICO_SDK_PATH in ~/.zshrc
        VARNAME="PICO_${REPO^^}_PATH"
        echo "Adding $VARNAME to ~/.zshrc"
        echo "export $VARNAME=$DEST" >> ~/.zshrc
        export ${VARNAME}=$DEST
    fi
done

cd $OUTDIR

# Pick up new variables we just defined
source ~/.bashrc

# Build a couple of examples
cd "$OUTDIR/pico-examples"
mkdir build
cd build
cmake ../ -DCMAKE_BUILD_TYPE=Debug

for e in blink hello_world
do
    echo "Building $e"
    cd $e
    make -j$JNUM
    cd ..
done

cd $OUTDIR

# Picoprobe and picotool
for REPO in picoprobe picotool
do
    DEST="$OUTDIR/$REPO"
    REPO_URL="${GITHUB_PREFIX}${REPO}${GITHUB_SUFFIX}"
    git clone $REPO_URL

    # Build both
    cd $DEST
    git submodule update --init
    mkdir build
    cd build
    cmake ../
    make -j$JNUM

    if [[ "$REPO" == "picotool" ]]; then
        echo "Installing picotool to /usr/local/bin/picotool"
        sudo cp picotool /usr/local/bin/
    fi

    cd $OUTDIR
done

if [ -d openocd ]; then
    echo "openocd already exists so skipping"
    SKIP_OPENOCD=1
fi

if [[ "$SKIP_OPENOCD" == 1 ]]; then
    echo "Won't build OpenOCD"
else
    # Build OpenOCD
    echo "Building OpenOCD"
    cd $OUTDIR
    # Should we include picoprobe support (which is a Pico acting as a debugger for another Pico)
    INCLUDE_PICOPROBE=1
    OPENOCD_BRANCH="rp2040"
    OPENOCD_CONFIGURE_ARGS="--enable-ftdi --enable-sysfsgpio --enable-bcm2835gpio"
    if [[ "$INCLUDE_PICOPROBE" == 1 ]]; then
        OPENOCD_CONFIGURE_ARGS="$OPENOCD_CONFIGURE_ARGS --enable-picoprobe"
    fi

    git clone "${GITHUB_PREFIX}openocd${GITHUB_SUFFIX}" -b $OPENOCD_BRANCH --depth=1
    cd openocd
    ./bootstrap
    ./configure $OPENOCD_CONFIGURE_ARGS
    make -j$JNUM
    sudo make install
fi

cd $OUTDIR

if [[ "$SKIP_VSCODE" == 1 ]]; then
    echo "Skipping VSCODE"
else
    echo "Installing VSCODE"
    sudo pacman -S --noconfirm $VSCODE_DEPS

    # Get extensions
    code --install-extension marus25.cortex-debug
    code --install-extension ms-vscode.cmake-tools
    code --install-extension ms-vscode.cpptools
fi

# Enable UART
if [[ "$SKIP_UART" == 1 ]]; then
    echo "Skipping uart configuration"
else
    sudo pacman -S --noconfirm $UART_DEPS
    echo "Disabling Linux serial console (UART) so we can use it for pico"
    echo "You must run sudo reboot to finish UART setup"
fi
