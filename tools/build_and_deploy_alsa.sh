#!/bin/bash
# tools/build_and_deploy_alsa.sh
# Complete ALSA utilities build and deployment script for JetKVM
# This script combines all steps: toolchain setup, audio deps, ALSA utils build, and deployment
set -e

# Color output functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
JETKVM_HOME="$HOME/.jetkvm"
AUDIO_LIBS_DIR="$JETKVM_HOME/audio-libs"
TOOLCHAIN_DIR="$JETKVM_HOME/rv1106-system"

# Default values
DEPLOY=false
DEVICE_IP=""
RUN_TESTS=false
FORCE_REBUILD=false
VERBOSE=false

# Usage function
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Complete ALSA utilities build and deployment script for JetKVM

OPTIONS:
    -d, --deploy IP         Deploy to JetKVM device at specified IP
    -t, --test             Run tests after deployment (requires -d)
    -f, --force            Force rebuild even if already built
    -v, --verbose          Enable verbose output
    -h, --help             Show this help message

EXAMPLES:
    $0                                    # Build only
    $0 -d 192.168.1.100                  # Build and deploy
    $0 -d 192.168.1.100 -t               # Build, deploy, and test
    $0 -f -d 192.168.1.100 -t            # Force rebuild, deploy, and test

NOTE:
    This script will automatically:
    1. Setup RV1106 toolchain (if needed)
    2. Build ALSA and Opus libraries (if needed)
    3. Build ALSA utilities (aplay, arecord, amixer, etc.)
    4. Optionally deploy to JetKVM device
    5. Optionally run tests on the device

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--deploy)
            DEPLOY=true
            DEVICE_IP="$2"
            shift 2
            ;;
        -t|--test)
            RUN_TESTS=true
            shift
            ;;
        -f|--force)
            FORCE_REBUILD=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate arguments
if [[ "$RUN_TESTS" == "true" && "$DEPLOY" == "false" ]]; then
    log_error "Test option (-t) requires deploy option (-d)"
    exit 1
fi

if [[ "$DEPLOY" == "true" && -z "$DEVICE_IP" ]]; then
    log_error "Deploy option requires device IP address"
    show_usage
    exit 1
fi

# Enable verbose output if requested
if [[ "$VERBOSE" == "true" ]]; then
    set -x
fi

log_info "Starting ALSA utilities build process..."
log_info "Project root: $PROJECT_ROOT"
log_info "JetKVM home: $JETKVM_HOME"

# Step 1: Setup toolchain
log_info "Step 1/4: Setting up RV1106 toolchain"
if [[ ! -d "$TOOLCHAIN_DIR" || "$FORCE_REBUILD" == "true" ]]; then
    if [[ "$FORCE_REBUILD" == "true" && -d "$TOOLCHAIN_DIR" ]]; then
        log_warning "Force rebuild: removing existing toolchain"
        rm -rf "$TOOLCHAIN_DIR"
    fi
    log_info "Running toolchain setup..."
    bash "$SCRIPT_DIR/setup_rv1106_toolchain.sh"
    log_success "Toolchain setup completed"
else
    log_success "Toolchain already present at $TOOLCHAIN_DIR"
fi

# Step 2: Build audio dependencies
log_info "Step 2/4: Building audio dependencies (ALSA lib + Opus)"
if [[ ! -d "$AUDIO_LIBS_DIR/alsa-lib-1.2.14" || ! -d "$AUDIO_LIBS_DIR/opus-1.5.2" || "$FORCE_REBUILD" == "true" ]]; then
    if [[ "$FORCE_REBUILD" == "true" ]]; then
        log_warning "Force rebuild: cleaning audio dependencies"
        rm -rf "$AUDIO_LIBS_DIR"
    fi
    log_info "Building ALSA library and Opus..."
    bash "$SCRIPT_DIR/build_audio_deps.sh"
    log_success "Audio dependencies built successfully"
else
    log_success "Audio dependencies already built"
fi

# Step 3: Build ALSA utilities
log_info "Step 3/4: Building ALSA utilities"
if [[ ! -d "$AUDIO_LIBS_DIR/alsa-utils-bin" || "$FORCE_REBUILD" == "true" ]]; then
    if [[ "$FORCE_REBUILD" == "true" && -d "$AUDIO_LIBS_DIR/alsa-utils-bin" ]]; then
        log_warning "Force rebuild: removing existing ALSA utilities"
        rm -rf "$AUDIO_LIBS_DIR/alsa-utils-bin"
        rm -rf "$AUDIO_LIBS_DIR/alsa-utils-1.2.14"
    fi
    log_info "Building ALSA utilities (aplay, arecord, amixer, etc.)..."
    bash "$SCRIPT_DIR/build_alsa_utils.sh"
    log_success "ALSA utilities built successfully"
else
    log_success "ALSA utilities already built"
fi

# Show build results
log_info "Build completed! Available utilities:"
if [[ -d "$AUDIO_LIBS_DIR/alsa-utils-bin" ]]; then
    ls -la "$AUDIO_LIBS_DIR/alsa-utils-bin/"
else
    log_error "ALSA utilities directory not found!"
    exit 1
fi

# Step 4: Deploy (optional)
if [[ "$DEPLOY" == "true" ]]; then
    log_info "Step 4/4: Deploying to JetKVM device at $DEVICE_IP"
    
    # Build deploy command
    DEPLOY_CMD="bash $SCRIPT_DIR/deploy_alsa_utils.sh -r $DEVICE_IP"
    if [[ "$RUN_TESTS" == "true" ]]; then
        DEPLOY_CMD="$DEPLOY_CMD --test"
    fi
    
    log_info "Running deployment: $DEPLOY_CMD"
    eval "$DEPLOY_CMD"
    log_success "Deployment completed successfully!"
    
    # Show usage instructions
    echo ""
    log_info "🎉 ALSA utilities are now available on your JetKVM device!"
    echo ""
    echo "Usage examples on device:"
    echo "  /userdata/jetkvm/alsa/aplay -l                    # List playback devices"
    echo "  /userdata/jetkvm/alsa/arecord -l                  # List capture devices"
    echo "  /userdata/jetkvm/alsa/aplay -D hw:1,0 test.wav    # Play audio file"
    echo "  /userdata/jetkvm/alsa/arecord -D hw:1,0 -f cd test.wav  # Record audio"
    echo "  /userdata/jetkvm/alsa/amixer                      # Control audio mixer"
    echo "  /userdata/jetkvm/alsa/speaker-test -D hw:1,0      # Test speakers"
    echo ""
    echo "To add to PATH permanently on device:"
    echo "  echo 'export PATH=\$PATH:/userdata/jetkvm/alsa' >> ~/.profile"
else
    log_info "Step 4/4: Skipping deployment (use -d option to deploy)"
    echo ""
    log_success "🎉 ALSA utilities built successfully!"
    echo ""
    echo "To deploy to your JetKVM device:"
    echo "  $0 -d <device-ip>                    # Deploy only"
    echo "  $0 -d <device-ip> -t                 # Deploy and test"
    echo ""
    echo "Or use the deploy script directly:"
    echo "  bash tools/deploy_alsa_utils.sh -r <device-ip>"
fi

log_success "All done! 🚀"