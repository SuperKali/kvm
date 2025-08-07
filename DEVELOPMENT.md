<div align="center">
    <img alt="JetKVM logo" src="https://jetkvm.com/logo-blue.png" height="28">

### Development Guide

[Discord](https://jetkvm.com/discord) | [Website](https://jetkvm.com) | [Issues](https://github.com/jetkvm/cloud-api/issues) | [Docs](https://jetkvm.com/docs)

[![Twitter](https://img.shields.io/twitter/url/https/twitter.com/jetkvm.svg?style=social&label=Follow%20%40JetKVM)](https://twitter.com/jetkvm)

[![Go Report Card](https://goreportcard.com/badge/github.com/jetkvm/kvm)](https://goreportcard.com/report/github.com/jetkvm/kvm)

</div>


# JetKVM Development Guide


Welcome to JetKVM development! This guide will help you get started quickly, whether you're fixing bugs, adding features, or just exploring the codebase.

## Get Started


### Prerequisites
- **A JetKVM device** (for full development)
- **[Go 1.24.4+](https://go.dev/doc/install)** and **[Node.js 22.15.0](https://nodejs.org/en/download/)**
- **[Git](https://git-scm.com/downloads)** for version control
- **[SSH access](https://jetkvm.com/docs/advanced-usage/developing#developer-mode)** to your JetKVM device
- **Audio build dependencies:**
   - **New in this release:** The audio pipeline is now fully in-process using CGO, ALSA, and Opus. You must run the provided scripts in `tools/` to set up the cross-compiler and build static ALSA/Opus libraries for ARM. See below.


### Development Environment

**Recommended:** Development is best done on **Linux** or **macOS**.

#### Apple Silicon (M1/M2/M3) Mac Users

If you are developing on an Apple Silicon Mac, you should use a devcontainer to ensure compatibility with the JetKVM build environment (which targets linux/amd64 and ARM). There are two main options:

- **VS Code Dev Containers**: Open the project in VS Code and use the built-in Dev Containers support. The configuration is in `.devcontainer/devcontainer.json`.
- **Devpod**: [Devpod](https://devpod.sh/) is a fast, open-source tool for running devcontainers anywhere. If you use Devpod, go to **Settings → Experimental → Additional Environmental Variables** and add:
   - `DOCKER_DEFAULT_PLATFORM=linux/amd64`
   This ensures all builds run in the correct architecture.
- **devcontainer CLI**: You can also use the [devcontainer CLI](https://github.com/devcontainers/cli) to launch the devcontainer from the terminal.

This approach ensures compatibility with all shell scripts, build tools, and cross-compilation steps used in the project.

If you're using Windows, we strongly recommend using **WSL (Windows Subsystem for Linux)** for the best development experience:
- [Install WSL on Windows](https://docs.microsoft.com/en-us/windows/wsl/install)
- [WSL Setup Guide](https://docs.microsoft.com/en-us/windows/wsl/setup/environment)

This ensures compatibility with shell scripts and build tools used in the project.


### Project Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/jetkvm/kvm.git
   cd kvm
   ```

2. **Check your tools:**
   ```bash
   go version && node --version
   ```

3. **Set up the cross-compiler and audio dependencies:**
   ```bash
   make dev_env
   # This will run tools/setup_rv1106_toolchain.sh and tools/build_audio_deps.sh
   # It will clone the cross-compiler and build ALSA/Opus static libs in $HOME/.jetkvm
   #
   # **Note:** This is required for the new in-process audio pipeline. If you skip this step, audio will not work.
   ```
   
   > 💡 **Tip:** Use `make help` to see all available build targets, or see the [Build System Reference](#build-system-reference) section for comprehensive documentation of all Makefile targets and tools.

4. **Find your JetKVM IP address** (check your router or device screen)

5. **Deploy and test:**
   ```bash
   ./dev_deploy.sh -r 192.168.1.100  # Replace with your device IP
   ```

6. **Open in browser:** `http://192.168.1.100`

That's it! You're now running your own development version of JetKVM, **with in-process audio streaming for the first time.**

---

## Common Tasks

### Modify the UI

```bash
cd ui
npm install
./dev_device.sh 192.168.1.100  # Replace with your device IP
```

Now edit files in `ui/src/` and see changes live in your browser!


### Modify the backend (including audio)

```bash
# Edit Go files (config.go, web.go, internal/audio, etc.)
./dev_deploy.sh -r 192.168.1.100 --skip-ui-build
```


### Run tests

```bash
./dev_deploy.sh -r 192.168.1.100 --run-go-tests
```

### View logs

```bash
ssh root@192.168.1.100
tail -f /var/log/jetkvm.log
```

---


## Project Layout

```
/kvm/
├── main.go              # App entry point
├── config.go            # Settings & configuration
├── web.go               # API endpoints
├── ui/                  # React frontend
│   ├── src/routes/      # Pages (login, settings, etc.)
│   └── src/components/  # UI components
├── internal/            # Internal Go packages
│   └── audio/           # In-process audio pipeline (CGO, ALSA, Opus) [NEW]
├── tools/               # Toolchain and audio dependency setup scripts
└── Makefile             # Build and dev automation (see audio targets)
```

**Key files for beginners:**

- `internal/audio/` - [NEW] In-process audio pipeline (CGO, ALSA, Opus)
- `web.go` - Add new API endpoints here
- `config.go` - Add new settings here
- `ui/src/routes/` - Add new pages here
- `ui/src/components/` - Add new UI components here

---

## Development Modes

### Full Development (Recommended)

*Best for: Complete feature development*

```bash
# Deploy everything to your JetKVM device
./dev_deploy.sh -r <YOUR_DEVICE_IP>
```

### Frontend Only

*Best for: UI changes without device*

```bash
cd ui
npm install
./dev_device.sh <YOUR_DEVICE_IP>
```


### Quick Backend Changes

*Best for: API, backend, or audio logic changes (including audio pipeline)*

```bash
# Skip frontend build for faster deployment
./dev_deploy.sh -r <YOUR_DEVICE_IP> --skip-ui-build
```

---

## Debugging Made Easy

### Check if everything is working

```bash
# Test connection to device
ping 192.168.1.100

# Check if JetKVM is running
ssh root@192.168.1.100 ps aux | grep jetkvm
```

### View live logs

```bash
ssh root@192.168.1.100
tail -f /var/log/jetkvm.log
```

### Reset everything (if stuck)

```bash
ssh root@192.168.1.100
rm /userdata/kvm_config.json
systemctl restart jetkvm
```

---

## Testing Your Changes

### Manual Testing

1. Deploy your changes: `./dev_deploy.sh -r <IP>`
2. Open browser: `http://<IP>`
3. Test your feature
4. Check logs: `ssh root@<IP> tail -f /var/log/jetkvm.log`

### Automated Testing

```bash
# Run all tests
./dev_deploy.sh -r <IP> --run-go-tests

# Frontend linting
cd ui && npm run lint
```

### API Testing

```bash
# Test login endpoint
curl -X POST http://<IP>/auth/password-local \
  -H "Content-Type: application/json" \
  -d '{"password": "test123"}'
```

---


### Common Issues & Solutions

### "Build failed" or "Permission denied"

```bash
# Fix permissions
ssh root@<IP> chmod +x /userdata/jetkvm/bin/jetkvm_app_debug

# Clean and rebuild
go clean -modcache
go mod tidy
make build_dev
# If you see errors about missing ALSA/Opus or toolchain, run:
make dev_env  # Required for new audio support
```

### "Can't connect to device"

```bash
# Check network
ping <IP>

# Check SSH
ssh root@<IP> echo "Connection OK"
```


### "Audio not working"

```bash
# Make sure you have run:
make dev_env
# If you see errors about ALSA/Opus, check logs and re-run the setup scripts in tools/.
```

### "Frontend not updating"

```bash
# Clear cache and rebuild
cd ui
npm cache clean --force
rm -rf node_modules
npm install
```

---

## Next Steps


### Adding a New Feature

1. **Backend:** Add API endpoint in `web.go` or extend audio in `internal/audio/`
2. **Config:** Add settings in `config.go`
3. **Frontend:** Add UI in `ui/src/routes/`
4. **Test:** Deploy and test with `./dev_deploy.sh`


### Code Style

- **Go:** Follow standard Go conventions
- **TypeScript:** Use TypeScript for type safety
- **React:** Keep components small and reusable
- **Audio/CGO:** Keep C/Go integration minimal, robust, and well-documented. Use zerolog for all logging.

### Environment Variables

```bash
# Enable debug logging
export LOG_TRACE_SCOPES="jetkvm,cloud,websocket,native,jsonrpc"

# Frontend development
export JETKVM_PROXY_URL="ws://<IP>"
```

---

## Need Help?

1. **Check logs first:** `ssh root@<IP> tail -f /var/log/jetkvm.log`
2. **Search issues:** [GitHub Issues](https://github.com/jetkvm/kvm/issues)
3. **Ask on Discord:** [JetKVM Discord](https://jetkvm.com/discord)
4. **Read docs:** [JetKVM Documentation](https://jetkvm.com/docs)

---

## Contributing

### Ready to contribute?

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

### Before submitting:

- [ ] Code works on device
- [ ] Tests pass
- [ ] Code follows style guidelines
- [ ] Documentation updated (if needed)

---

## Build System Reference

### Makefile Targets

The JetKVM build system provides a comprehensive set of Make targets for development, building, testing, and deployment. Use `make help` to see all available targets.

#### Development Environment Setup

| Target | Description | Dependencies | Environment Variables |
|--------|-------------|--------------|----------------------|
| `setup_toolchain` | Clone RV1106 cross-compilation toolchain | None | `JETKVM_HOME` |
| `build_audio_deps` | Build ALSA and Opus static libraries for ARM | `setup_toolchain` | `JETKVM_HOME`, `TOOLCHAIN_DIR`, `AUDIO_LIBS_DIR` |
| `dev_env` | Complete development environment setup | `build_audio_deps` | All above |

#### Building Targets

| Target | Description | Dependencies | Environment Variables |
|--------|-------------|--------------|----------------------|
| `build_dev` | Build development version with audio support | `build_audio_deps`, `hash_resource` | `VERSION_DEV`, `TOOLCHAIN_DIR`, `AUDIO_LIBS_DIR` |
| `build_release` | Build production release version | `frontend`, `build_audio_deps`, `hash_resource` | `VERSION`, `TOOLCHAIN_DIR`, `AUDIO_LIBS_DIR` |
| `frontend` | Build React frontend only | None | None |
| `hash_resource` | Generate SHA256 hash for jetkvm_native | None | None |

#### Testing Targets

| Target | Description | Dependencies | Environment Variables |
|--------|-------------|--------------|----------------------|
| `build_test2json` | Build test2json utility for ARM | None | `GO_CMD` |
| `build_gotestsum` | Build gotestsum test runner for ARM | None | `GO_CMD` |
| `build_dev_test` | Build all tests for device deployment | `build_test2json`, `build_gotestsum` | `TEST_DIRS`, `KVM_PKG_NAME` |

#### Release Management

| Target | Description | Dependencies | Environment Variables |
|--------|-------------|--------------|----------------------|
| `dev_release` | Build and upload development release to R2 | `frontend`, `build_dev` | `VERSION_DEV` |
| `release` | Build and upload production release to R2 | `build_release` | `VERSION` |

#### Key Environment Variables

| Variable | Default Value | Description |
|----------|---------------|-------------|
| `JETKVM_HOME` | `$HOME/.jetkvm` | JetKVM home directory for toolchain and libraries |
| `TOOLCHAIN_DIR` | `$JETKVM_HOME/rv1106-system` | RV1106 cross-compilation toolchain directory |
| `AUDIO_LIBS_DIR` | `$JETKVM_HOME/audio-libs` | ALSA and Opus static libraries directory |
| `VERSION` | `0.4.6` | Production version number |
| `VERSION_DEV` | `0.4.7-dev<timestamp>` | Development version with timestamp |
| `BRANCH` | Auto-detected | Current git branch |
| `BIN_DIR` | `./bin` | Binary output directory |
| `BUILDDATE` | Auto-generated | Build timestamp |
| `REVISION` | Auto-detected | Git commit hash |

#### Usage Examples

```bash
# Set up complete development environment
make dev_env

# Build development version
make build_dev

# Build with custom version
VERSION=1.0.0 make release

# Build frontend then backend
make frontend build_dev

# View all available targets
make help
```

### Tools Directory Scripts

The `tools/` directory contains essential scripts for cross-compilation, audio library building, and deployment. Each script is designed to be run independently or as part of the Makefile targets.

#### Core Build Scripts

**`setup_rv1106_toolchain.sh`**
- **Purpose**: Downloads and sets up the RV1106 ARM cross-compilation toolchain
- **Location**: Clones to `$HOME/.jetkvm/rv1106-system`
- **Repository**: `https://github.com/jetkvm/rv1106-system.git`
- **Usage**: `bash tools/setup_rv1106_toolchain.sh`
- **Dependencies**: Git, internet connection
- **Output**: Cross-compilation toolchain for ARM RV1106 architecture

**`build_audio_deps.sh`**
- **Purpose**: Cross-compiles ALSA library and Opus codec as static libraries for ARM
- **Dependencies**: `setup_rv1106_toolchain.sh` must be run first
- **Libraries Built**:
  - ALSA lib 1.2.14 (with PCM plugins, topology support)
  - Opus 1.5.2 (with fixed-point optimization)
- **Output Directory**: `$HOME/.jetkvm/audio-libs`
- **Usage**: `bash tools/build_audio_deps.sh`
- **Configuration**: Static linking, ARM-optimized builds

**`build_alsa_utils.sh`**
- **Purpose**: Cross-compiles ALSA utilities (aplay, arecord, amixer, etc.) for ARM
- **Dependencies**: Both `setup_rv1106_toolchain.sh` and `build_audio_deps.sh`
- **Utilities Built**:
  - `aplay` - Audio playback utility
  - `arecord` - Audio recording utility
  - `amixer` - Audio mixer control
  - `alsactl` - ALSA control utility
  - `speaker-test` - Speaker testing utility
- **Output Directory**: `$HOME/.jetkvm/audio-libs/alsa-utils-bin/`
- **Usage**: `bash tools/build_alsa_utils.sh`

#### Deployment Scripts

**`deploy_alsa_utils.sh`**
- **Purpose**: Deploy built ALSA utilities to JetKVM device via SSH
- **Target Directory**: `/userdata/jetkvm/alsa/` on device
- **Features**:
  - SSH-based deployment (no SCP required)
  - Optional testing after deployment
  - Configurable target path and user
- **Usage**: 
  ```bash
  bash tools/deploy_alsa_utils.sh -r 192.168.1.100
  bash tools/deploy_alsa_utils.sh -r 192.168.1.100 --test
  ```
- **Options**:
  - `-r, --remote <ip>` - Target device IP (required)
  - `-u, --user <user>` - SSH user (default: root)
  - `-p, --path <path>` - Target path (default: /userdata/jetkvm/alsa)
  - `-t, --test` - Run tests after deployment

**`deploy_to_jetkvm.sh`**
- **Purpose**: Deploy main JetKVM application binary to device
- **Features**:
  - Automatic binary building via devpod if needed
  - Checksum verification
  - Service management (stop/start)
  - Force transfer option
- **Target**: `/userdata/jetkvm/bin/jetkvm_app` on device
- **Usage**: 
  ```bash
  bash tools/deploy_to_jetkvm.sh -r 192.168.1.100
  bash tools/deploy_to_jetkvm.sh -r 192.168.1.100 --force
  ```

**`build_and_deploy_alsa.sh`**
- **Purpose**: Complete ALSA workflow - build toolchain, dependencies, utilities, and deploy
- **Features**:
  - Intelligent caching (skips already-built components)
  - Colored output with progress indicators
  - Force rebuild option
  - Optional testing
  - Comprehensive error handling
- **Usage**:
  ```bash
  # Build only
  bash tools/build_and_deploy_alsa.sh
  
  # Build and deploy
  bash tools/build_and_deploy_alsa.sh -d 192.168.1.100
  
  # Build, deploy, and test
  bash tools/build_and_deploy_alsa.sh -d 192.168.1.100 -t
  
  # Force rebuild everything
  bash tools/build_and_deploy_alsa.sh -f -d 192.168.1.100
  ```
- **Options**:
  - `-d, --deploy <ip>` - Deploy to device IP
  - `-t, --test` - Run tests after deployment
  - `-f, --force` - Force rebuild all components
  - `-v, --verbose` - Enable verbose output

#### Script Dependencies and Workflow

```
setup_rv1106_toolchain.sh
         ↓
build_audio_deps.sh
         ↓
build_alsa_utils.sh
         ↓
deploy_alsa_utils.sh (optional)
```

**Complete Workflow Example:**
```bash
# Method 1: Using individual scripts
bash tools/setup_rv1106_toolchain.sh
bash tools/build_audio_deps.sh
bash tools/build_alsa_utils.sh
bash tools/deploy_alsa_utils.sh -r 192.168.1.100 --test

# Method 2: Using combined script
bash tools/build_and_deploy_alsa.sh -d 192.168.1.100 -t

# Method 3: Using Makefile
make dev_env  # Sets up toolchain and builds audio deps
make build_dev  # Builds main application
```

#### Output Locations

| Component | Location | Description |
|-----------|----------|-------------|
| Toolchain | `$HOME/.jetkvm/rv1106-system/` | ARM cross-compilation toolchain |
| ALSA Library | `$HOME/.jetkvm/audio-libs/alsa-lib-1.2.14/` | Static ALSA library |
| Opus Library | `$HOME/.jetkvm/audio-libs/opus-1.5.2/` | Static Opus codec library |
| ALSA Utilities | `$HOME/.jetkvm/audio-libs/alsa-utils-bin/` | Cross-compiled ALSA utilities |
| Main Binary | `./bin/jetkvm_app` | JetKVM application binary |
| Device ALSA Utils | `/userdata/jetkvm/alsa/` | ALSA utilities on device |
| Device Binary | `/userdata/jetkvm/bin/jetkvm_app` | Main application on device |

---

## Advanced Topics

### Performance Profiling

```bash
# Enable profiling
go build -o bin/jetkvm_app -ldflags="-X main.enableProfiling=true" cmd/main.go

# Access profiling
curl http://<IP>:6060/debug/pprof/
```
### Advanced Environment Variables

```bash
# Enable trace logging (useful for debugging)
export LOG_TRACE_SCOPES="jetkvm,cloud,websocket,native,jsonrpc"

# For frontend development
export JETKVM_PROXY_URL="ws://<JETKVM_IP>"

# Enable SSL in development
export USE_SSL=true
```

### Configuration Management

The application uses a JSON configuration file stored at `/userdata/kvm_config.json`.

#### Adding New Configuration Options

1. **Update the Config struct in `config.go`:**

   ```go
   type Config struct {
       // ... existing fields
       NewFeatureEnabled bool `json:"new_feature_enabled"`
   }
   ```

2. **Update the default configuration:**

   ```go
   var defaultConfig = &Config{
       // ... existing defaults
       NewFeatureEnabled: false,
   }
   ```

3. **Add migration logic if needed for existing installations**


---

**Happy coding!**

For more information, visit the [JetKVM Documentation](https://jetkvm.com/docs) or join our [Discord Server](https://jetkvm.com/discord).
