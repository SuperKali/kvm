#!/usr/bin/env bash
# tools/deploy_alsa_utils.sh
# Deploy ALSA utilities to JetKVM device
set -e

C_RST="$(tput sgr0)"
C_ERR="$(tput setaf 1)"
C_OK="$(tput setaf 2)"
C_WARN="$(tput setaf 3)"
C_INFO="$(tput setaf 5)"

msg() { printf '%s%s%s\n' $2 "$1" $C_RST; }

msg_info() { msg "$1" $C_INFO; }
msg_ok() { msg "$1" $C_OK; }
msg_err() { msg "$1" $C_ERR; }
msg_warn() { msg "$1" $C_WARN; }

JETKVM_HOME="$HOME/.jetkvm"
AUDIO_LIBS_DIR="$JETKVM_HOME/audio-libs"
ALSA_UTILS_BIN_DIR="$AUDIO_LIBS_DIR/alsa-utils-bin"

# Function to show usage
show_usage() {
    echo "Usage: $0 [options] -r <remote_ip>"
    echo ""
    echo "Deploy ALSA utilities to JetKVM device"
    echo ""
    echo "Required:"
    echo "  -r, --remote <remote_ip>   Remote host IP address"
    echo ""
    echo "Optional:"
    echo "  -u, --user <remote_user>   Remote username (default: root)"
    echo "  -p, --path <remote_path>   Target path on device (default: /userdata/jetkvm/alsa)"
    echo "  -t, --test                 Test utilities after deployment"
    echo "      --help                 Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -r 192.168.1.100"
    echo "  $0 -r 192.168.1.100 --test"
    echo "  $0 -r 192.168.1.100 --user admin --path /tmp"
}

# Default values
REMOTE_USER="root"
REMOTE_PATH="/userdata/jetkvm/alsa"
RUN_TESTS=false
REMOTE_HOST=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--remote)
            REMOTE_HOST="$2"
            shift 2
            ;;
        -u|--user)
            REMOTE_USER="$2"
            shift 2
            ;;
        -p|--path)
            REMOTE_PATH="$2"
            shift 2
            ;;
        -t|--test)
            RUN_TESTS=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Verify required parameters
if [ -z "$REMOTE_HOST" ]; then
    msg_err "Error: Remote IP is a required parameter"
    show_usage
    exit 1
fi

# Check if binaries exist
if [ ! -d "$ALSA_UTILS_BIN_DIR" ]; then
    msg_err "Error: ALSA utilities not found at $ALSA_UTILS_BIN_DIR"
    msg_err "Please run 'make build_alsa_utils' first"
    exit 1
fi

msg_info "▶ Deploying ALSA utilities to $REMOTE_HOST"
msg_info "📁 Source: $ALSA_UTILS_BIN_DIR"
msg_info "📁 Target: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"

# Test SSH connection
msg_info "▶ Testing SSH connection"
if ! ssh -o ConnectTimeout=5 "${REMOTE_USER}@${REMOTE_HOST}" "echo 'SSH connection successful'" >/dev/null 2>&1; then
    msg_err "❌ Failed to connect to ${REMOTE_USER}@${REMOTE_HOST}"
    msg_err "Please check:"
    msg_err "  - Device IP address is correct"
    msg_err "  - Device is powered on and connected to network"
    msg_err "  - SSH is enabled on the device"
    exit 1
fi

# Create target directory if it doesn't exist
msg_info "▶ Creating target directory"
ssh "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p ${REMOTE_PATH}"

# Copy binaries using cat method (no scp dependency)
msg_info "▶ Copying ALSA utilities"
for binary in "$ALSA_UTILS_BIN_DIR"/*; do
    if [ -f "$binary" ]; then
        binary_name=$(basename "$binary")
        msg_info "  📄 Copying $binary_name"
        ssh "${REMOTE_USER}@${REMOTE_HOST}" "cat > ${REMOTE_PATH}/$binary_name" < "$binary"
        ssh "${REMOTE_USER}@${REMOTE_HOST}" "chmod +x ${REMOTE_PATH}/$binary_name"
    fi
done

msg_ok "✅ Deployment completed successfully!"

# List deployed utilities
msg_info "📋 Deployed utilities:"
ssh "${REMOTE_USER}@${REMOTE_HOST}" "ls -la ${REMOTE_PATH}/a* ${REMOTE_PATH}/speaker-test 2>/dev/null || true"

# Run tests if requested
if [ "$RUN_TESTS" = true ]; then
    msg_info "▶ Running ALSA utilities tests"
    
    msg_info "📋 Testing aplay -l (list playback devices):"
    ssh "${REMOTE_USER}@${REMOTE_HOST}" "${REMOTE_PATH}/aplay -l || echo 'No playback devices found'"
    
    msg_info "📋 Testing arecord -l (list capture devices):"
    ssh "${REMOTE_USER}@${REMOTE_HOST}" "${REMOTE_PATH}/arecord -l || echo 'No capture devices found'"
    
    msg_info "📋 Testing amixer (show mixer controls):"
    ssh "${REMOTE_USER}@${REMOTE_HOST}" "${REMOTE_PATH}/amixer || echo 'No mixer controls found'"
fi

msg_info "💡 Usage examples on device:"
echo "  ${REMOTE_PATH}/aplay -l                    # List playback devices"
echo "  ${REMOTE_PATH}/arecord -l                  # List capture devices"
echo "  ${REMOTE_PATH}/aplay -D hw:1,0 test.wav    # Play audio file"
echo "  ${REMOTE_PATH}/arecord -D hw:1,0 -f cd test.wav  # Record audio"
echo "  ${REMOTE_PATH}/amixer                      # Control audio mixer"
echo "  ${REMOTE_PATH}/speaker-test -D hw:1,0      # Test speakers"
echo ""
msg_info "🔧 To add to PATH permanently, add to device's ~/.profile:"
echo "  export PATH=\$PATH:${REMOTE_PATH}"

echo "Deployment complete."