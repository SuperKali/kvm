#!/usr/bin/env bash

# JetKVM Deployment Script
# Transfers jetkvm_app and checksum to JetKVM device via SSH (no SCP required)
# Based on the proven approach from dev_deploy.sh

set -e

# Configuration
JETKVM_IP=""
JETKVM_USER="root"
LOCAL_BIN="./bin/jetkvm_app"
LOCAL_CHECKSUM="./bin/jetkvm_app.sha256"
REMOTE_PATH="/userdata/jetkvm/bin"
FORCE_TRANSFER=false
BINARY_REMOVED=false

# Colors (using tput like dev_deploy.sh for better compatibility)
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

# Build binary using devpod if it doesn't exist
build_binary() {
    msg_info "▶ Building binary using devpod..."
    
    # Check if devpod is available
    if ! command -v devpod >/dev/null 2>&1; then
        msg_err "❌ devpod command not found"
        msg_err "Please install devpod or build manually with 'make build_dev'"
        exit 1
    fi
    
    msg_info "Running build command via devpod..."
    if devpod ssh jetkvm-build --command "make frontend && make build_dev && sha256sum bin/jetkvm_app > bin/jetkvm_app.sha256"; then
        msg_ok "✅ Binary built successfully via devpod"
    else
        msg_err "❌ Failed to build binary via devpod"
        msg_err "Please check the build environment and try again"
        exit 1
    fi
}

# Check if files exist
check_files() {
    msg_info "▶ Checking local files..."
    
    if [[ ! -f "$LOCAL_BIN" ]]; then
        msg_warn "Binary not found: $LOCAL_BIN"
        msg_info "Attempting to build automatically..."
        build_binary
        
        # Check again after build
        if [[ ! -f "$LOCAL_BIN" ]]; then
            msg_err "❌ Binary still not found after build attempt"
            msg_err "Please check the build process and try again"
            exit 1
        fi
    fi
    
    if [[ ! -f "$LOCAL_CHECKSUM" ]]; then
        msg_warn "Checksum not found: $LOCAL_CHECKSUM"
        msg_info "▶ Generating checksum..."
        shasum -a 256 "$LOCAL_BIN" | cut -d ' ' -f 1 > "$LOCAL_CHECKSUM"
    fi
    
    msg_ok "✅ Local files ready"
}

# Check if remote file exists and compare checksums
should_transfer_file() {
    local local_file="$1"
    local remote_file="$2"
    local description="$3"
    
    echo
    msg_info "📋 Checking $description..."
    
    # If we've removed the binary, we definitely need to transfer it
    if [[ "$BINARY_REMOVED" == "true" ]] && [[ "$description" == *"binary"* ]]; then
        msg_info "  → Transfer needed: Binary was removed"
        return 0  # Should transfer
    fi
    
    # Check if remote file exists
    if ! ssh "${JETKVM_USER}@${JETKVM_IP}" "test -f '$remote_file'" 2>/dev/null; then
        msg_info "  → Transfer needed: Remote file doesn't exist"
        return 0  # Should transfer
    fi
    
    # Get file sizes for comparison
    local local_size=$(stat -f%z "$local_file" 2>/dev/null || stat -c%s "$local_file" 2>/dev/null)
    local remote_size=$(ssh "${JETKVM_USER}@${JETKVM_IP}" "stat -c%s '$remote_file' 2>/dev/null || wc -c < '$remote_file'" 2>/dev/null)
    
    echo "  Local:  $(format_size $local_size)"
    echo "  Remote: $(format_size $remote_size)"
    
    # If sizes differ significantly, force transfer
    if [[ "$local_size" != "$remote_size" ]]; then
        msg_warn "  ⚠️  Transfer needed: File sizes differ"
        return 0  # Should transfer
    fi
    
    # Get local checksum
    local local_checksum
    if [[ "$local_file" == *".sha256" ]]; then
        # For checksum files, read the content directly
        local_checksum=$(cat "$local_file")
    else
        # For binary files, calculate checksum
        local_checksum=$(shasum -a 256 "$local_file" | cut -d ' ' -f 1)
    fi
    
    # Get remote checksum
    local remote_checksum=$(ssh "${JETKVM_USER}@${JETKVM_IP}" "sha256sum '$remote_file' | cut -d ' ' -f 1" 2>/dev/null)
    
    if [[ "$local_checksum" == "$remote_checksum" ]]; then
        if [[ "$FORCE_TRANSFER" == "true" ]]; then
            msg_info "  → Transfer needed: Force transfer requested"
            return 0  # Should transfer
        else
            msg_ok "  ✅ Files match (size and checksum) - skipping"
            return 1  # Should not transfer
        fi
    else
        msg_warn "  ⚠️  Transfer needed: Checksums differ"
        msg_info "    Local:  $local_checksum"
        msg_info "    Remote: $remote_checksum"
        return 0  # Should transfer
    fi
}

# Format file size for human readability
format_size() {
    local size=$1
    if [[ $size -gt 1048576 ]]; then
        echo "$(( size / 1048576 )) MB ($(printf "%'d" $size) bytes)"
    elif [[ $size -gt 1024 ]]; then
        echo "$(( size / 1024 )) KB ($(printf "%'d" $size) bytes)"
    else
        echo "$(printf "%'d" $size) bytes"
    fi
}

# Transfer file using SSH with progress indication
transfer_file() {
    local local_file="$1"
    local remote_file="$2"
    local description="$3"
    
    # Check if transfer is needed
    if ! should_transfer_file "$local_file" "$remote_file" "$description"; then
        return 0  # File is up-to-date, skip transfer
    fi
    
    echo
    msg_info "▶ Transferring $description..."
    
    # Get local file size for verification and progress
    local local_size=$(stat -f%z "$local_file" 2>/dev/null || stat -c%s "$local_file" 2>/dev/null)
    local formatted_size=$(format_size $local_size)
    msg_info "  File size: $formatted_size"
    
    # Create a progress monitoring function
    show_progress() {
        local target_file="$1"
        local expected_size="$2"
        local start_time=$(date +%s)
        local last_size=0
        
        while true; do
            sleep 1
            local current_size=$(ssh "${JETKVM_USER}@${JETKVM_IP}" "stat -c%s '$target_file' 2>/dev/null || echo 0")
            
            if [[ $current_size -eq 0 ]]; then
                continue  # File doesn't exist yet
            fi
            
            local percent=$((current_size * 100 / expected_size))
            local elapsed=$(($(date +%s) - start_time))
            local rate=0
            if [[ $elapsed -gt 0 ]]; then
                rate=$((current_size / elapsed))
            fi
            
            local formatted_current=$(format_size $current_size)
            local formatted_rate=""
            if [[ $rate -gt 0 ]]; then
                formatted_rate=" @ $(format_size $rate)/s"
            fi
            
            printf "\r  Progress: %d%% (%s)%s" "$percent" "$formatted_current" "$formatted_rate"
            
            # Exit if transfer is complete or no progress for 5 seconds
            if [[ $current_size -ge $expected_size ]]; then
                echo
                break
            fi
            
            # Check if transfer has stalled
            if [[ $current_size -eq $last_size ]] && [[ $current_size -gt 0 ]]; then
                local stall_count=$((stall_count + 1))
                if [[ $stall_count -gt 10 ]]; then  # 10 seconds of no progress
                    echo
                    msg_err "  Transfer appears to have stalled"
                    break
                fi
            else
                stall_count=0
            fi
            last_size=$current_size
        done
    }
    
    msg_info "  Starting transfer via SSH..."
    msg_info "  Source: $local_file"
    msg_info "  Target: ${JETKVM_USER}@${JETKVM_IP}:$remote_file"
    
    # Start progress monitoring in background
    show_progress "$remote_file" "$local_size" &
    local progress_pid=$!
    
    # Use cat over SSH for reliable file transfer (doesn't require sftp-server)
    local transfer_result=0
    local transfer_output=""
    transfer_output=$(timeout 120 bash -c "cat '$local_file' | ssh -o ConnectTimeout=30 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 '${JETKVM_USER}@${JETKVM_IP}' 'cat > \"$remote_file\"'" 2>&1) || transfer_result=$?
    
    # Stop progress monitoring
    kill $progress_pid 2>/dev/null || true
    wait $progress_pid 2>/dev/null || true
    
    if [[ $transfer_result -eq 0 ]]; then
        # Verify the transfer was complete by checking file size
        local remote_size=$(ssh "${JETKVM_USER}@${JETKVM_IP}" "stat -c%s '$remote_file' 2>/dev/null || wc -c < '$remote_file'" 2>/dev/null)
        
        if [[ "$local_size" == "$remote_size" ]]; then
            msg_ok "✅ $description transferred successfully"
            msg_info "  Verified: $(format_size $remote_size)"
            
            # Reset the binary removed flag if we successfully transferred the binary
            if [[ "$description" == *"binary"* ]]; then
                BINARY_REMOVED=false
            fi
        else
            msg_err "❌ Transfer incomplete! Size mismatch:"
            msg_err "  Expected: $(format_size $local_size)"
            msg_err "  Received: $(format_size $remote_size)"
            msg_err "  This may indicate a network issue or insufficient disk space"
            exit 1
        fi
    else
        msg_err "❌ Failed to transfer $description"
        if [[ $transfer_result -eq 124 ]]; then
            msg_err "  Transfer timed out after 120 seconds"
        else
            msg_err "  Transfer error code: $transfer_result"
        fi
        
        # Show transfer output if available
        if [[ -n "$transfer_output" ]]; then
            msg_err "  Transfer output: $transfer_output"
        fi
        
        # Check if partial file exists and remove it
        local partial_size=$(ssh "${JETKVM_USER}@${JETKVM_IP}" "stat -c%s '$remote_file' 2>/dev/null || echo 0")
        if [[ $partial_size -gt 0 ]]; then
            msg_err "  Removing partial file ($(format_size $partial_size))"
            ssh "${JETKVM_USER}@${JETKVM_IP}" "rm -f '$remote_file'" 2>/dev/null || true
        fi
        exit 1
    fi
}

# Final verification that both files are correctly deployed
verify_deployment() {
    msg_info "▶ Final deployment verification..."
    
    # Verify binary exists and is executable
    if ! ssh "${JETKVM_USER}@${JETKVM_IP}" "test -x '$REMOTE_PATH/jetkvm_app'" 2>/dev/null; then
        msg_err "❌ Binary is not executable on remote device"
        exit 1
    fi
    
    # Verify checksum file exists
    if ! ssh "${JETKVM_USER}@${JETKVM_IP}" "test -f '$REMOTE_PATH/jetkvm_app.sha256'" 2>/dev/null; then
        msg_err "❌ Checksum file missing on remote device"
        exit 1
    fi
    
    # Compare file sizes after transfer
    msg_info "▶ Verifying file sizes after transfer..."
    
    # Binary file size comparison
    local local_bin_size=$(stat -f%z "$LOCAL_BIN" 2>/dev/null || stat -c%s "$LOCAL_BIN" 2>/dev/null)
    local remote_bin_size=$(ssh "${JETKVM_USER}@${JETKVM_IP}" "stat -c%s '$REMOTE_PATH/jetkvm_app' 2>/dev/null || wc -c < '$REMOTE_PATH/jetkvm_app'" 2>/dev/null)
    
    msg_info "Binary file size comparison:"
    msg_info "  Local:  $local_bin_size bytes"
    msg_info "  Remote: $remote_bin_size bytes"
    
    if [[ "$local_bin_size" != "$remote_bin_size" ]]; then
        msg_err "❌ Binary file size mismatch after transfer!"
        msg_err "  Expected: $local_bin_size bytes"
        msg_err "  Got:      $remote_bin_size bytes"
        exit 1
    fi
    msg_ok "✅ Binary file size matches"
    
    # Checksum file size comparison
    local local_checksum_size=$(stat -f%z "$LOCAL_CHECKSUM" 2>/dev/null || stat -c%s "$LOCAL_CHECKSUM" 2>/dev/null)
    local remote_checksum_size=$(ssh "${JETKVM_USER}@${JETKVM_IP}" "stat -c%s '$REMOTE_PATH/jetkvm_app.sha256' 2>/dev/null || wc -c < '$REMOTE_PATH/jetkvm_app.sha256'" 2>/dev/null)
    
    msg_info "Checksum file size comparison:"
    msg_info "  Local:  $local_checksum_size bytes"
    msg_info "  Remote: $remote_checksum_size bytes"
    
    if [[ "$local_checksum_size" != "$remote_checksum_size" ]]; then
        msg_err "❌ Checksum file size mismatch after transfer!"
        msg_err "  Expected: $local_checksum_size bytes"
        msg_err "  Got:      $remote_checksum_size bytes"
        exit 1
    fi
    msg_ok "✅ Checksum file size matches"
    
    # Compare SHA256 checksums after transfer
    msg_info "▶ Verifying SHA256 checksums after transfer..."
    
    # Binary checksum verification
    local remote_bin_checksum=$(ssh "${JETKVM_USER}@${JETKVM_IP}" "sha256sum '$REMOTE_PATH/jetkvm_app' | cut -d ' ' -f 1")
    local local_bin_checksum=$(cat "$LOCAL_CHECKSUM" | cut -d ' ' -f 1)
    
    msg_info "Binary SHA256 comparison:"
    msg_info "  Local:  $local_bin_checksum"
    msg_info "  Remote: $remote_bin_checksum"
    
    if [[ "$remote_bin_checksum" != "$local_bin_checksum" ]]; then
        msg_err "❌ Binary SHA256 checksum verification failed!"
        msg_err "  Expected: $local_bin_checksum"
        msg_err "  Got:      $remote_bin_checksum"
        exit 1
    fi
    msg_ok "✅ Binary SHA256 checksum matches"
    
    # Checksum file content verification
    local remote_checksum_content=$(ssh "${JETKVM_USER}@${JETKVM_IP}" "cat '$REMOTE_PATH/jetkvm_app.sha256'")
    local local_checksum_content=$(cat "$LOCAL_CHECKSUM")
    
    msg_info "Checksum file content comparison:"
    msg_info "  Local:  $local_checksum_content"
    msg_info "  Remote: $remote_checksum_content"
    
    if [[ "$remote_checksum_content" != "$local_checksum_content" ]]; then
        msg_err "❌ Checksum file content verification failed!"
        msg_err "  Expected: $local_checksum_content"
        msg_err "  Got:      $remote_checksum_content"
        exit 1
    fi
    msg_ok "✅ Checksum file content matches"
    
    msg_ok "✅ All verification checks passed - deployment successful"
}

# Stop all running instances of jetkvm_app
stop_jetkvm_processes() {
    msg_info "▶ Checking for running JetKVM processes..."
    
    # Use ps command to check for running processes more reliably
    local running_processes=$(ssh "${JETKVM_USER}@${JETKVM_IP}" "ps aux | grep '[j]etkvm_app' | grep -v grep" 2>/dev/null || true)
    
    if [[ -z "$running_processes" ]]; then
        msg_ok "✅ No running JetKVM processes found"
        return 0
    fi
    
    # Count the processes
    local process_count=$(echo "$running_processes" | wc -l | tr -d ' ')
    msg_info "Found $process_count running JetKVM process(es)"
    
    # Show the running processes
    msg_info "Running processes:"
    echo "$running_processes" | while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            echo "  $line"
        fi
    done
    
    # Get PIDs for stopping
    local running_pids=$(ssh "${JETKVM_USER}@${JETKVM_IP}" "pgrep -f 'jetkvm_app' 2>/dev/null || true")
    
    if [[ -z "$running_pids" ]]; then
        msg_warn "⚠️  Could not get PIDs for running processes"
        return 0
    fi
    
    # Attempt graceful shutdown first
    msg_info "▶ Attempting graceful shutdown (SIGTERM)..."
    ssh "${JETKVM_USER}@${JETKVM_IP}" "pkill -TERM -f 'jetkvm_app' 2>/dev/null || true"
    
    # Wait a few seconds for graceful shutdown
    sleep 3
    
    # Check if any processes are still running
    local remaining_pids=$(ssh "${JETKVM_USER}@${JETKVM_IP}" "pgrep -f 'jetkvm_app' 2>/dev/null || true")
    
    if [[ -z "$remaining_pids" ]]; then
        msg_ok "✅ All JetKVM processes stopped gracefully"
        return 0
    fi
    
    # Force kill any remaining processes
    local remaining_count=$(echo "$remaining_pids" | wc -l | tr -d ' ')
    msg_warn "⚠️  $remaining_count process(es) still running, forcing shutdown (SIGKILL)..."
    ssh "${JETKVM_USER}@${JETKVM_IP}" "pkill -KILL -f 'jetkvm_app' 2>/dev/null || true"
    
    # Wait a moment and verify
    sleep 2
    local final_check=$(ssh "${JETKVM_USER}@${JETKVM_IP}" "pgrep -f 'jetkvm_app' 2>/dev/null || true")
    
    if [[ -z "$final_check" ]]; then
        msg_ok "✅ All JetKVM processes stopped"
    else
        msg_err "❌ Failed to stop some JetKVM processes"
        msg_err "Remaining processes:"
        ssh "${JETKVM_USER}@${JETKVM_IP}" "ps aux | grep '[j]etkvm_app'" 2>/dev/null || true
        exit 1
    fi
}

# Remove existing binary file to ensure clean deployment
remove_existing_binary() {
    msg_info "▶ Checking for existing binary file..."
    
    # Check if the target binary exists
    if ssh "${JETKVM_USER}@${JETKVM_IP}" "test -f '$REMOTE_PATH/jetkvm_app'" 2>/dev/null; then
        msg_info "Found existing binary file"
        
        # Get file info before removal
        local existing_size=$(ssh "${JETKVM_USER}@${JETKVM_IP}" "stat -c%s '$REMOTE_PATH/jetkvm_app' 2>/dev/null || echo 0")
        local existing_date=$(ssh "${JETKVM_USER}@${JETKVM_IP}" "stat -c%y '$REMOTE_PATH/jetkvm_app' 2>/dev/null || echo 'unknown'")
        
        msg_info "  Size: $(format_size $existing_size)"
        msg_info "  Modified: $existing_date"
        
        # Remove the existing binary and its checksum
        msg_info "▶ Removing existing binary and checksum..."
        if ssh "${JETKVM_USER}@${JETKVM_IP}" "rm -f '$REMOTE_PATH/jetkvm_app' '$REMOTE_PATH/jetkvm_app.sha256'" 2>/dev/null; then
            msg_ok "✅ Existing files removed successfully"
            BINARY_REMOVED=true
        else
            msg_err "❌ Failed to remove existing files"
            msg_err "This may cause issues during deployment"
            exit 1
        fi
        
        # Verify removal
        if ssh "${JETKVM_USER}@${JETKVM_IP}" "test -f '$REMOTE_PATH/jetkvm_app'" 2>/dev/null; then
            msg_err "❌ Binary file still exists after removal attempt"
            exit 1
        fi
    else
        msg_ok "✅ No existing binary found - clean deployment"
    fi
}

# Ensure remote directory exists
ensure_remote_directory() {
    msg_info "▶ Ensuring remote directory exists..."
    
    ssh "${JETKVM_USER}@${JETKVM_IP}" "mkdir -p '$REMOTE_PATH'"
    
    if [[ $? -eq 0 ]]; then
        msg_ok "✅ Remote directory ready"
        
        # Check available disk space
        local available_space=$(ssh "${JETKVM_USER}@${JETKVM_IP}" "df '$REMOTE_PATH' | tail -1 | awk '{print \\\$4}'" 2>/dev/null)
        if [[ -n "$available_space" ]]; then
            # Convert KB to bytes (df usually reports in KB)
            available_space=$((available_space * 1024))
            msg_info "Available disk space: $(format_size $available_space)"
            
            # Get local binary size
            local binary_size=$(stat -f%z "$LOCAL_BIN" 2>/dev/null || stat -c%s "$LOCAL_BIN" 2>/dev/null)
            
            # Check if we have enough space (with 10MB buffer)
            local required_space=$((binary_size + 10485760))  # 10MB buffer
            if [[ $available_space -lt $required_space ]]; then
                msg_err "❌ Insufficient disk space on remote device"
                msg_err "  Required: $(format_size $required_space) (including buffer)"
                msg_err "  Available: $(format_size $available_space)"
                exit 1
            fi
        fi
    else
        msg_err "❌ Failed to create remote directory"
        exit 1
    fi
}

# Main execution
main() {
    msg_info "JetKVM Deployment Script"
    msg_info "Target: ${JETKVM_USER}@${JETKVM_IP}"
    echo
    
    check_files
    
    # Test SSH connectivity
    msg_info "▶ Testing SSH connectivity..."
    if ! ssh -o ConnectTimeout=5 "${JETKVM_USER}@${JETKVM_IP}" "echo 'SSH connection successful'" >/dev/null 2>&1; then
        msg_err "❌ Cannot connect to JetKVM via SSH"
        msg_err "Please check:"
        msg_err "  - JetKVM IP address: $JETKVM_IP"
        msg_err "  - SSH access is enabled"
        msg_err "  - Network connectivity"
        exit 1
    fi
    msg_ok "✅ SSH connectivity confirmed"
    
    # Stop any running JetKVM processes before deployment
    stop_jetkvm_processes
    
    # Remove existing binary file for clean deployment
    remove_existing_binary
    
    # Ensure remote directory exists
    ensure_remote_directory
    
    # Transfer files (with smart checksum comparison)
    transfer_file "$LOCAL_BIN" "$REMOTE_PATH/jetkvm_app" "JetKVM binary"
    transfer_file "$LOCAL_CHECKSUM" "$REMOTE_PATH/jetkvm_app.sha256" "checksum file"
    
    # Ensure binary is executable
    msg_info "▶ Setting executable permissions..."
    ssh "${JETKVM_USER}@${JETKVM_IP}" "chmod +x '$REMOTE_PATH/jetkvm_app'"
    msg_ok "✅ Executable permissions set"
    
    # Final verification
    verify_deployment
    
    echo
    msg_ok "✅ Files transferred successfully!"
    msg_info "Binary location: $REMOTE_PATH/jetkvm_app"
    msg_info "Checksum location: $REMOTE_PATH/jetkvm_app.sha256"
    msg_info "You can now handle the deployment as needed"
}

# Show usage
show_help() {
    echo "Usage: $0 [options] -r <JETKVM_IP>"
    echo
    echo "Transfers jetkvm_app and checksum files to JetKVM via SSH with smart checksum comparison"
    echo
    echo "Required:"
    echo "  -r, --remote <JETKVM_IP>   IP address of your JetKVM"
    echo
    echo "Optional:"
    echo "  -u, --user <USERNAME>      SSH username (default: root)"
    echo "  -f, --force                Force transfer even if checksums match"
    echo "  -h, --help                 Show this help message"
    echo
    echo "Features:"
    echo "  • Automatic stopping of running JetKVM processes before deployment"
    echo "  • Clean removal of existing binary files before replacement"
    echo "  • Smart checksum comparison - only transfers files that have changed"
    echo "  • Automatic checksum generation if missing"
    echo "  • Executable permission setting"
    echo "  • Comprehensive verification"
    echo
    echo "Examples:"
    echo "  $0 -r 192.168.100.214                    # Basic usage"
    echo "  $0 -r 192.168.1.100 -u admin            # Custom IP and user"
    echo "  $0 -r 192.168.100.214 --force           # Force transfer"
    echo
    echo "Files will be transferred to:"
    echo "  /userdata/jetkvm/bin/jetkvm_app"
    echo "  /userdata/jetkvm/bin/jetkvm_app.sha256"
    echo
    echo "Prerequisites:"
    echo "  - Build the binary first: make build_release"
    echo "  - SSH access to JetKVM"
    echo "  - Files: ./bin/jetkvm_app and ./bin/jetkvm_app.sha256"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--remote)
            JETKVM_IP="$2"
            shift 2
            ;;
        -u|--user)
            JETKVM_USER="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_TRANSFER=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Verify required parameters
if [[ -z "$JETKVM_IP" ]]; then
    msg_err "Error: JetKVM IP is required"
    echo
    show_help
    exit 1
fi

# Run main function
main "$@"