# Podman v5.x Installer for Debian 12/13

Build and install Podman 5.3.1+ from source on Debian 12 (Bookworm) or Debian 13 (Trixie), with full healthcheck support and rootless operation.

## Why This Exists

Debian's official repositories contain severely outdated container packages:

| Package | Debian Version | This Installer |
|---------|----------------|----------------|
| Podman | 4.x | **5.3.1** |
| crun | outdated | **1.22** |
| conmon | outdated | **latest** |
| passt/pasta | missing | **latest** |

**Key Problem:** Debian's podman 4.x does NOT support HEALTHCHECK in Dockerfiles - you're forced to use compose files for healthchecks. This installer fixes that.

## What Gets Installed

| Component | Version | Purpose |
|-----------|---------|---------|
| Podman | 5.3.1 | Container engine with healthcheck support |
| crun | 1.22 | Fast OCI runtime (faster than runc) |
| conmon | latest | Container monitor (enables healthchecks) |
| passt/pasta | latest | Rootless networking stack |
| Go | 1.23.4 | Build dependency |
| podman-compose | latest | Docker Compose compatible orchestration |

## Prerequisites

- **Operating System:** Debian 12 (Bookworm) or Debian 13 (Trixie)
- **Admin user:** Non-root user WITH sudo access (runs the installer)
- **Podman user:** Non-root user WITHOUT sudo access (target user for containers)
- **Disk Space:** ~2GB free for build dependencies and compiled binaries
- **Network:** Internet access to download source code

### User Setup

Before running the installer, ensure both users exist:

```bash
# Create admin user (if not exists)
sudo useradd -m -s /bin/bash -G sudo admin_user

# Create podman user (non-sudoer)
sudo useradd -m -s /bin/bash podman_user
```

## Quick Start

```bash
# As admin user (sudoer):
git clone https://github.com/HornetGit/podman_v5.x_on_debian12.git
cd podman_v5.x_on_debian12
./install/install_podman.sh --user podman_user
```

## Usage

### Install

```bash
# Full installation for target user
./install/install_podman.sh --user podman_user

# Show help
./install/install_podman.sh --help
```

### Uninstall

```bash
# Complete uninstallation
./uninstall/uninstall_podman.sh --user podman_user
```

### Individual Components

```bash
# Install/uninstall specific components
./install/install_crun.sh --user podman_user
./install/install_passt.sh --user podman_user
./install/install_conmon.sh --user podman_user
./install/install_podman-compose.sh --user podman_user

./uninstall/uninstall_crun.sh --user podman_user
./uninstall/uninstall_passt.sh --user podman_user
./uninstall/uninstall_conmon.sh --user podman_user
./uninstall/uninstall_podman-compose.sh --user podman_user
```

## Directory Structure

```
podman_v5.x_on_debian12/
├── install/
│   ├── install_podman.sh          # Main orchestrator (12 phases)
│   ├── install_crun.sh            # crun OCI runtime
│   ├── install_conmon.sh          # conmon (healthcheck support)
│   ├── install_passt.sh           # pasta networking
│   └── install_podman-compose.sh  # podman-compose
├── uninstall/
│   ├── uninstall_podman.sh        # Main uninstaller (6 phases)
│   ├── uninstall_crun.sh
│   ├── uninstall_conmon.sh
│   ├── uninstall_passt.sh
│   └── uninstall_podman-compose.sh
├── lib/
│   ├── constants.sh               # Colors, paths
│   ├── log_functions.sh           # Logging utilities
│   ├── validation_functions.sh    # Prerequisites checks
│   ├── podman_functions.sh        # Podman operations
│   ├── ui_functions.sh            # Flag parsing, UI
│   ├── file_functions.sh          # File operations
│   └── utility_functions.sh       # General utilities
├── docs/
│   └── workflow_podman_installer.html  # Interactive documentation
├── README.md
└── LICENCE
```

## Installation Phases

The main installer (`install_podman.sh`) executes 12 phases:

1. **Complete Cleanup** - Remove existing podman/docker installations
2. **System Updates** - Install build dependencies
3. **Go 1.23.4** - Required for building Podman
4. **Build crun** - OCI runtime from source
5. **Build passt** - Rootless networking
6. **Build conmon** - Container monitor (healthchecks)
7. **Build Podman 5.3.1** - With seccomp, apparmor, systemd, pasta tags
8. **Verification** - Check all component versions
9. **Systemd Linger** - Enable user services
10. **Podman Socket** - Start and enable socket
11. **Security Guidance** - Point to validation tools
12. **PATH Consolidation** - Clean up .bashrc

For detailed documentation, see [workflow_podman_installer.html](docs/workflow_podman_installer.html).
For detailed documentation, see [workflow_podman_installer.html](https://htmlpreview.github.io/?https://github.com/HornetGit/podman_v5.x_on_debian12/blob/main/docs/workflow_podman_installer.html).


## Security Validation

After installation, validate your Podman setup using the official security benchmark:

```bash
git clone https://github.com/containers/podman-security-bench.git
cd podman-security-bench
sudo ./podman-security-bench.sh
```

## Security Considerations

- **Script launcher must be sudoer** - Scripts use sudo internally for privileged operations
- **Target user does NOT need sudo** - Podman runs rootless
- **Destructive cleanup** - Installation removes existing podman/docker packages
- **Review before production** - Always review scripts before running on production systems
- **Source builds** - All components built from official GitHub repositories

## Troubleshooting

**Important:** Most troubleshooting commands must be run AS the podman user, not as admin.

### Socket not found

```bash
# Switch to podman user first
su - podman_user

# Check socket status (as podman_user)
systemctl --user status podman.socket

# Restart socket (as podman_user)
systemctl --user restart podman.socket

# Verify socket path
ls -la /run/user/$(id -u)/podman/podman.sock
```

### Permission denied

```bash
# As admin user: Ensure linger is enabled for podman user
sudo loginctl enable-linger podman_user

# As podman_user: Check runtime directory
su - podman_user
ls -la /run/user/$(id -u)/
```

### crun not found

```bash
# Verify crun location
ls -la ~/.local/bin/crun

# Check PATH
echo $PATH | grep -o '.local/bin'
```

### Healthcheck not working

```bash
# Verify conmon is installed
which conmon
conmon --version

# Check podman info
podman info | grep -A5 conmon
```

## Configuration Files

After installation, these files are created:

| File | Location | Purpose |
|------|----------|---------|
| containers.conf | ~/.config/containers/ | Runtime config (crun, pasta) |
| crun | ~/.local/bin/ | OCI runtime |
| passt/pasta | ~/.local/bin/ | Networking |
| podman-compose | ~/bin/ | Compose tool |
| podman | /usr/local/bin/ | Container engine |
| conmon | /usr/local/bin/ | Container monitor |

## Tested On

- Debian 12 (Bookworm)
- Debian 13 (Trixie)

## License

MIT License - See [LICENCE](LICENCE) file.

## Contributing

Issues and pull requests welcome at:
https://github.com/HornetGit/podman_v5.x_on_debian12

## Acknowledgments

- [Podman](https://podman.io/) - The daemonless container engine
- [crun](https://github.com/containers/crun) - Fast OCI runtime
- [passt](https://passt.top/) - Rootless networking
- [conmon](https://github.com/containers/conmon) - Container monitor
