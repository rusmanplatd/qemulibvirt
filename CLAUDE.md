# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains an enhanced QEMU/Libvirt management system focused on cluster management of virtual machines. The primary component is a comprehensive bash script (`qemu_libvirt_manager.sh`) that provides both command-line and interactive interfaces for managing VMs and VM clusters.

## Core Architecture

### Main Script: qemu_libvirt_manager.sh
- **Language**: Bash script (31k+ lines)
- **Version**: 2.1.0
- **Purpose**: Comprehensive VM and cluster management with desktop integration
- **Key Features**:
  - Individual VM management (create, start, stop, delete)
  - Cluster management (group VMs for coordinated operations)
  - Template system for reusable cluster configurations
  - Health monitoring and scaling operations
  - Backup/restore functionality
  - Desktop integration with GUI viewers and notifications
  - Interactive text-based UI

### Configuration Structure
```
~/.config/qemu-manager/
├── config                      # Main configuration
├── desktop-config             # Desktop integration settings
└── clusters/                  # Cluster configurations
    ├── <cluster-name>.conf    # Individual cluster configs
    ├── templates/             # Cluster templates
    └── backups/               # Cluster backups
```

### Logging
- Location: `~/.local/share/qemu-manager/qemu-manager.log`
- Max size: 10MB with rotation

## Common Development Commands

### Script Execution
```bash
# Main script entry point
./qemu_libvirt_manager.sh <command> [arguments]

# Check system dependencies and setup
./qemu_libvirt_manager.sh check

# Install desktop integration
./qemu_libvirt_manager.sh install-desktop

# Launch interactive mode for guided operations
./qemu_libvirt_manager.sh interactive

# View help for all available commands
./qemu_libvirt_manager.sh help
```

### VM Management
```bash
# List all VMs
./qemu_libvirt_manager.sh list

# Start/stop individual VMs
./qemu_libvirt_manager.sh start <vm_name>
./qemu_libvirt_manager.sh stop <vm_name>

# Create VM from ISO
./qemu_libvirt_manager.sh create-iso <name> <ram_mb> <vcpus> <iso_path> [disk_size_gb]
```

### Cluster Management
```bash
# List all clusters
./qemu_libvirt_manager.sh cluster-list

# Create cluster from existing VMs
./qemu_libvirt_manager.sh cluster-create <name> [description] <vm1> [vm2] [...]

# Start/stop clusters (sequential or parallel)
./qemu_libvirt_manager.sh cluster-start <name> [parallel]
./qemu_libvirt_manager.sh cluster-stop <name> [timeout] [parallel]

# Health monitoring
./qemu_libvirt_manager.sh cluster-health <name> [detailed]
./qemu_libvirt_manager.sh cluster-dashboard

# Scaling operations
./qemu_libvirt_manager.sh cluster-scale <name> <add|remove> <count> [create-vms]
```

## Key Functions and Architecture

### VM Operations
- `vm_exists()`, `vm_is_running()`: VM state validation
- `start_vm()`, `stop_vm()`: Basic VM lifecycle
- `create_vm_desktop_shortcut()`: Desktop integration

### Cluster Operations
- `create_cluster()`: Cluster creation and configuration
- `start_cluster()`, `stop_cluster()`: Coordinated VM operations
- `cluster_health_check()`: Health monitoring with scoring
- `scale_cluster()`: Dynamic scaling up/down
- `backup_cluster()`: Configuration backup

### Template System
- `create_cluster_template()`: Reusable cluster definitions
- `create_cluster_from_template()`: Rapid cluster deployment
- Templates include VM specs (RAM, vCPUs, disk), networking, and cluster behavior

### Desktop Integration
- `install_desktop_integration()`: Creates .desktop files and shortcuts
- `notify_desktop()`: System notifications via notify-send
- `vm_viewer()`: GUI VM console access with multiple viewer support

## Dependencies

### Required System Packages
- `qemu-kvm`, `libvirt-daemon-system`, `libvirt-clients`
- `bridge-utils`, `virtinst`
- Optional: `virt-viewer`, `virt-manager`, `vinagre` (for GUI)

### User Permissions
- User must be in `libvirt` group
- libvirtd service must be running

## Development Patterns

### Error Handling
- Uses `set -euo pipefail` for strict error handling
- `error_exit()` function for consistent error reporting
- Comprehensive validation functions for inputs

### Logging
- Structured logging with levels (INFO, WARN, ERROR, DEBUG)
- Desktop notifications for important events
- Log rotation at 10MB

### Configuration Management
- INI-style configuration files for clusters and templates
- Atomic operations with validation before execution
- Backup creation before destructive operations

## No Build/Test System

This is a standalone bash script project with no formal build system, test framework, or package management. Development workflow is:

1. Edit the main script directly
2. Test manually using the script commands
3. Use the interactive mode for guided testing
4. Check logs for debugging

## Documentation

The repository includes comprehensive documentation:
- `CLUSTER_MANAGEMENT_DOCUMENTATION.md`: Complete feature documentation
- `QUICK_REFERENCE.md`: Essential commands and workflows
- Built-in help system via `./qemu_libvirt_manager.sh help`

## Usage Notes

- The script is designed for defensive security use cases (VM management, not exploitation)
- All operations are logged and can be monitored
- Cluster operations support both sequential and parallel execution
- Template system enables consistent, repeatable deployments
- Desktop integration provides user-friendly access to VM consoles