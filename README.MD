# Debian Podman 5.x Installation Scripts

A complete set of scripts to install podman v5.x as a modern container tools on Debian 12 (bookworm), bypassing outdated repository packages.

## Purpose

Debian 12's repositories contain severely outdated container packages that don't support modern Podman 5.x features. This project provides scripts to:
- **Install Podman 5.3.1** from source with full feature support
- **Install crun 1.19.2** for optimal performance vs runc
- **Install latest passt/pasta** for advanced networking
- **Install latest conmon** for advanced healthchecks
- **Install podman-compose** from upstream GitHub
- **Build everything from source** to get latest features and healthcheck support

## Key Features Enabled
- ✅ **Healthcheck Support** - Full container health monitoring
- ✅ **Rootless Containers** - Enhanced security without root
- ✅ **Advanced Networking** - passt/pasta integration  
- ✅ **crun Performance** - Faster than runc runtime
- ✅ **Modern Compose** - Latest podman-compose features

## What Gets Installed

| Component | Version | Source | Why |
|-----------|---------|--------|-----|
| **Podman** | 5.3.1 | GitHub source | Debian has 4.x with missing features |
| **crun** | 1.19.2+ | GitHub source | Debian has old incompatible version |
| **passt/pasta** | latest | GitLab source | Not in Debian repos |
| **Go** | 1.23.4 | Official binary | Required for Podman build |
| **conmon** | latest | GitHub source | Healthcheck support vs. Debian repos |
| **podman-compose** | latest | GitHub | Comply with podman v5.x |

## Prerequisites

### System Requirements
- **Debian 12** (Bookworm)
- **Non-root user** with sudo privileges  
- **Internet connection** for downloading sources
- **~2GB free space** for build dependencies and sources

### User Setup
The installation user must:
- Be in the `sudo` group (password required for security)
- Have a proper home directory (`/home/username`)
- **Not be root** (rootless containers only)

### Directory Setup
**IMPORTANT**: Create the required project directory structure:
```bash
mkdir -p $HOME/Projects/InstallationScripts/
cd $HOME/Projects/InstallationScripts/
```

This directory structure is required by the installation scripts.

#

## Installation Files

### Repository Structure
podman-v5x-debian12/
├── 📋 README.md          # Complete installation guide
├── 🔧 functions.sh       # Shared utility functions
├── 🚀 install_podman.sh  # Main installation orchestrator
├── ⚙️  install_crun.sh   # Build crun runtime from source
├── 🌐 install_passt.sh   # Build passt networking from source
├── 🔍 install_conmon.sh  # Build conmon with healthcheck support
├── 🗑️ uninstall_crun.sh  # Clean removal of crun installations
└── ✅ check_podman.sh    # Verify installation and healthcheck

### Core Installation Scripts (run in order):
1. **`functions.sh`** - Shared utility functions library
2. **`install_podman.sh`** - Main installation orchestrator  
3. **`install_crun.sh`** - Build crun 1.19.2+ from source
4. **`install_passt.sh`** - Build passt/pasta from source
5. **`uninstall_crun.sh`** - Remove all crun installations
6. **`install_conmon.sh`** - Build conmon with healthcheck support
7. **`check_podman.sh`** - Verify installation and healthcheck support

### Development/Testing Scripts:
- **`test_rm_secure.sh`** - Test secure removal function (development)

## Quick Start

### 1. Clone and Setup
```bash
git clone https://github.com/HornetGit/podman_v5.x_on_debian12.git
cd podman_v5.x_on_debian12
chmod +x *.sh
```

### 2. Create Required Directory Structure
```bash
mkdir -p $HOME/Projects/InstallationScripts/
```

### 3. Run Main Installation
```bash
./install_podman.sh
```

**The main script will automatically:**
- Check user prerequisites and permissions
- Remove old Docker/Podman installations completely
- Install build dependencies and tools
- Build and install all components in correct order
- Verify installation works with tests

### 4. Verify Installation
```bash
podman --version                    # Should show 5.3.1
crun --version                     # Should show 1.19.2+
podman info | grep -i runtime      # Should show crun
passt --version                    # Should work
podman-compose --version           # Should work (if installed)
conmon --version                   # Should show 2.1.13+
```

## Installation Process

### Phase 1: Complete Cleanup
- **Removes all existing Docker/Podman packages** from Debian repos
- **Cleans up old configurations** and containers
- **Removes conflicting packages** and directories
- **Removes old Go installations**

### Phase 2: System Updates & Dependencies  
- Updates system packages and security components
- **Installs comprehensive build dependencies**:
  - gcc, make, build-essential
  - libsystemd-dev, libgpgme-dev, libseccomp-dev
  - libbtrfs-dev, libdevmapper-dev, libyajl-dev
  - autotools, pkg-config, and more

### Phase 3: Install Go 1.23.4
- Downloads and installs Go compiler from official source
- Creates system-wide symlinks for sudo access
- Updates PATH in ~/.bashrc

### Phase 4: Build crun 1.19.2+ 
- **Uninstalls any existing crun** (system and user)
- **Builds crun from GitHub source** for rootless user
- **Configures Podman to use crun** as default runtime
- **Significantly faster than runc** for container operations
- **Validates installation** with multiple checks

### Phase 5: Build passt/pasta (Latest)
- **Removes old Debian passt package**
- **Builds latest passt from GitLab source**
- **Enables advanced rootless networking** capabilities
- **Installs to user bin directory** for security
- **Sets up PODMAN_PASST environment variable**

### Phase 6: Build Podman 5.3.1
- **Clones Podman source from GitHub**
- **Builds with official recommended build tags**: `seccomp apparmor systemd`
- **Installs system-wide** with proper permissions
- **Includes all modern features** missing from Debian packages

### Phase 7-9: Verification & Testing
- **Verifies all components** are properly installed
- **Tests basic container functionality**
- **Tests networking with pasta**
- **Tests healthcheck support** (main upgrade reason)
- **Validates runtime configuration**

## Configuration Files Created

The installation creates/modifies:
- **`~/.config/containers/containers.conf`** - Podman runtime configuration, specifically for ROOTLESS user
- **`~/.bashrc`** - PATH updates for Go, crun, passt
- **System binaries** in `/usr/local/bin/`

## Advanced Usage

### Manual Component Installation
Run individual scripts if needed:
```bash
./uninstall_crun.sh      # Remove crun completely  
./install_crun.sh        # Install crun only
./install_passt.sh       # Install passt only
./check_podman.sh        # Test healthcheck support
```

### Reinstalling Components
```bash
# Reinstall just crun
./uninstall_crun.sh && ./install_crun.sh

# Test specific functionality
./check_podman.sh
```

### Install podman-compose (Optional)
```bash
# See install_podman-compose.txt for commands
mkdir -p ~/bin
curl -L https://raw.githubusercontent.com/containers/podman-compose/main/podman_compose.py -o ~/bin/podman-compose
chmod +x ~/bin/podman-compose
sudo ln -sf ~/bin/podman-compose /usr/local/bin/podman-compose
```

## Why This Project Exists

### Debian Repository Problems:
- **Podman 4.x** instead of 5.x (missing healthcheck, latest features)
- **Old crun** that doesn't work with Podman 5.x
- **No passt/pasta** for advanced networking
- **Broken dependencies** and compatibility issues

### Benefits of Source Installation:
- **Latest features** and security fixes
- **Healthcheck support** for production deployments
- **Better performance** with crun vs runc
- **Advanced networking** with passt/pasta
- **No dependency conflicts** with Debian packages

## Troubleshooting

### Permission Errors
```bash
# Ensure user is in sudo group
sudo usermod -aG sudo $USER
# Then logout/login
```

### Build Failures
```bash
# Check build dependencies are installed
sudo apt update && sudo apt install build-essential
```

### Socket Issues
```bash
# Restart Podman socket
systemctl --user restart podman.socket
# or use the functions.sh lib: see 'reset_socket()'
```

### crun Not Found
```bash
# Check PATH includes ~/.local/bin
echo $PATH | grep .local/bin
source ~/.bashrc
```

## Security Notes

⚠️ **Important Security Considerations:**
- **cleanup_podman() function WIPES OUT former setups** - remove `--force` flags if you want to keep old crun and containers.conf
- Scripts require **sudo access with password** (no passwordless sudo)
- Installs tools to **user directories** when possible
- **Removes Docker completely** - this is intentional
- **Always review scripts** before running with sudo
- **NOT recommended for production servers** without review


## Contributing

This project addresses real pain points with Debian's container ecosystem. Contributions welcome for:
- **Support for other Debian versions**
- **Additional error handling**
- **Performance optimizations**
- **Security improvements**

## License

MIT License - see LICENSE file for details.

---

**Created**: July 2025  
**Author**: XCS HornetGit  
**Version**: Debian 12, Podman 5.3.1, crun 1.19.2+, Go 1.23.4  
**Purpose**: Bypass outdated Debian container packages