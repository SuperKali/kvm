#!/bin/bash
# tools/build_alsa_utils.sh
# Build ALSA utilities (aplay, arecord, amixer, etc.) for ARM RV1106
set -e

JETKVM_HOME="$HOME/.jetkvm"
AUDIO_LIBS_DIR="$JETKVM_HOME/audio-libs"
TOOLCHAIN_DIR="$JETKVM_HOME/rv1106-system"
CROSS_PREFIX="$TOOLCHAIN_DIR/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin/arm-rockchip830-linux-uclibcgnueabihf"
ALSA_UTILS_VERSION="1.2.14"

# Check if toolchain and alsa-lib are available
if [ ! -d "$TOOLCHAIN_DIR" ]; then
    echo "Error: Toolchain not found at $TOOLCHAIN_DIR"
    echo "Please run 'make setup_toolchain' first"
    exit 1
fi

if [ ! -d "$AUDIO_LIBS_DIR/alsa-lib-1.2.14" ]; then
    echo "Error: ALSA library not found at $AUDIO_LIBS_DIR/alsa-lib-1.2.14"
    echo "Please run 'make build_audio_deps' first"
    exit 1
fi

mkdir -p "$AUDIO_LIBS_DIR"
cd "$AUDIO_LIBS_DIR"

# Download alsa-utils source
echo "Downloading alsa-utils $ALSA_UTILS_VERSION..."
[ -f alsa-utils-${ALSA_UTILS_VERSION}.tar.bz2 ] || wget -N https://www.alsa-project.org/files/pub/utils/alsa-utils-${ALSA_UTILS_VERSION}.tar.bz2

# Extract
echo "Extracting alsa-utils..."
[ -d alsa-utils-${ALSA_UTILS_VERSION} ] || tar xf alsa-utils-${ALSA_UTILS_VERSION}.tar.bz2

# Set up cross-compilation environment
export CC="${CROSS_PREFIX}-gcc"
export CXX="${CROSS_PREFIX}-g++"
export AR="${CROSS_PREFIX}-ar"
export STRIP="${CROSS_PREFIX}-strip"
export PKG_CONFIG_PATH="$AUDIO_LIBS_DIR/install/usr/lib/pkgconfig:$PKG_CONFIG_PATH"
export CFLAGS="-I$AUDIO_LIBS_DIR/install/usr/include"
export LDFLAGS="-L$AUDIO_LIBS_DIR/alsa-lib-1.2.14/src/.libs -L$AUDIO_LIBS_DIR/alsa-lib-1.2.14/src/topology/.libs -static"
export CPPFLAGS="-I$AUDIO_LIBS_DIR/install/usr/include"

# Build alsa-utils
cd alsa-utils-${ALSA_UTILS_VERSION}
if [ ! -f .built ]; then
    echo "Configuring alsa-utils..."
    ./configure \
        --host=arm-rockchip830-linux-uclibcgnueabihf \
        --prefix=/usr \
        --disable-alsaconf \
        --disable-bat \
        --disable-xmlto \
        --disable-rst2man \
        --disable-alsamixer \
        --disable-alsaloop \
        --without-curses \
        --with-alsa-prefix="$AUDIO_LIBS_DIR/alsa-lib-1.2.14" \
        --with-alsa-inc-prefix="$AUDIO_LIBS_DIR/alsa-lib-1.2.14/include"
    
    echo "Building alsa-utils..."
    make -j$(nproc)
    
    # Create output directory for binaries
    mkdir -p "$AUDIO_LIBS_DIR/alsa-utils-bin"
    
    # Copy the important utilities
    echo "Copying utilities to $AUDIO_LIBS_DIR/alsa-utils-bin/"
    cp aplay/aplay "$AUDIO_LIBS_DIR/alsa-utils-bin/"
    # Create arecord as a symlink to aplay (standard ALSA practice)
    ln -sf aplay "$AUDIO_LIBS_DIR/alsa-utils-bin/arecord"
    cp amixer/amixer "$AUDIO_LIBS_DIR/alsa-utils-bin/"
    cp alsamixer/alsamixer "$AUDIO_LIBS_DIR/alsa-utils-bin/" 2>/dev/null || echo "Note: alsamixer not built (requires ncurses)"
    cp alsactl/alsactl "$AUDIO_LIBS_DIR/alsa-utils-bin/"
    cp speaker-test/speaker-test "$AUDIO_LIBS_DIR/alsa-utils-bin/"
    
    # Strip binaries to reduce size
    echo "Stripping binaries..."
    "${CROSS_PREFIX}-strip" "$AUDIO_LIBS_DIR/alsa-utils-bin/"*
    
    touch .built
fi

cd ..

echo ""
echo "✅ ALSA utilities built successfully!"
echo "📁 Binaries available in: $AUDIO_LIBS_DIR/alsa-utils-bin/"
echo "📋 Available utilities:"
ls -la "$AUDIO_LIBS_DIR/alsa-utils-bin/"
echo ""
echo "🚀 To deploy to JetKVM device:"
echo "   scp $AUDIO_LIBS_DIR/alsa-utils-bin/* root@<device-ip>:/userdata/jetkvm/alsa/"
echo ""
echo "💡 Usage examples on device:"
echo "   aplay -l                    # List playback devices"
echo "   arecord -l                  # List capture devices"
echo "   aplay -D hw:1,0 test.wav    # Play audio file"
echo "   arecord -D hw:1,0 -f cd test.wav  # Record audio"
echo "   amixer                      # Control audio mixer"
echo "   speaker-test -D hw:1,0      # Test speakers"