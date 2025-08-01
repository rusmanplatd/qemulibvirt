# QEMU/Libvirt Cluster Management Documentation

## Table of Contents
1. [Overview](#overview)
2. [Installation & Setup](#installation--setup)
3. [Basic Cluster Operations](#basic-cluster-operations)
4. [Advanced Cluster Features](#advanced-cluster-features)
5. [Cluster Templates](#cluster-templates)
6. [Health Monitoring & Scaling](#health-monitoring--scaling)
7. [Backup & Restore](#backup--restore)
8. [Interactive Management](#interactive-management)
9. [Configuration Reference](#configuration-reference)
10. [Troubleshooting](#troubleshooting)
11. [Best Practices](#best-practices)

---

## Overview

The Enhanced QEMU/Libvirt Cluster Management system provides comprehensive tools for managing groups of virtual machines as unified clusters. This system offers:

- **Dynamic Cluster Management**: Create, configure, and manage VM clusters
- **Template System**: Reusable cluster configurations for rapid deployment
- **Health Monitoring**: Real-time cluster health checks and status reporting
- **Scaling Operations**: Add or remove VMs from clusters dynamically
- **Backup & Restore**: Cluster configuration backup and recovery
- **Advanced Orchestration**: Sequential or parallel VM operations
- **Desktop Integration**: GUI notifications and desktop shortcuts

### Key Features

- ✅ Multi-cluster management
- ✅ Template-based cluster creation
- ✅ Health monitoring and diagnostics
- ✅ Dynamic scaling (up/down)
- ✅ Configuration backup/restore
- ✅ Sequential/parallel operations
- ✅ Desktop notifications
- ✅ Interactive TUI management
- ✅ Comprehensive logging

---

## Installation & Setup

### Prerequisites

```bash
# Ubuntu/Debian
sudo apt-get install qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst

# RHEL/CentOS/Fedora
sudo yum install qemu-kvm libvirt libvirt-python libvirt-client

# Arch Linux
sudo pacman -S qemu libvirt virt-manager
```

### Initial Setup

1. **Add user to libvirt group:**
   ```bash
   sudo usermod -a -G libvirt $USER
   ```

2. **Start libvirt service:**
   ```bash
   sudo systemctl start libvirtd
   sudo systemctl enable libvirtd
   ```

3. **Install desktop integration:**
   ```bash
   ./qemu_libvirt_manager.sh install-desktop
   ```

4. **Check dependencies:**
   ```bash
   ./qemu_libvirt_manager.sh check
   ```

---

## Basic Cluster Operations

### Creating Clusters

#### Method 1: From Existing VMs
```bash
# Create cluster with existing VMs
./qemu_libvirt_manager.sh cluster-create webcluster "Web Server Cluster" web1 web2 web3

# Create cluster with single VM
./qemu_libvirt_manager.sh cluster-create dbcluster "Database Cluster" db-master
```

#### Method 2: Using Interactive Mode
```bash
./qemu_libvirt_manager.sh interactive
# Select option 12 for "Create cluster"
```

### Managing Clusters

#### List All Clusters
```bash
./qemu_libvirt_manager.sh cluster-list
```

**Output Example:**
```
Cluster Name         Status          VMs        Description                             
---------------------------------------------------------------------------------
webcluster           Running         3/3        Web Server Cluster
dbcluster            Partial         1/2        Database Cluster
testcluster          Stopped         0/3        Test Environment
```

#### View Cluster Details
```bash
./qemu_libvirt_manager.sh cluster-info webcluster
```

**Output Example:**
```
Cluster Information: webcluster
===============================================

DESCRIPTION    : Web Server Cluster
CREATED        : 2025-08-01 13:38:00
STARTUP_ORDER  : sequential
STARTUP_DELAY  : 5
SHUTDOWN_ORDER : reverse
SHUTDOWN_DELAY : 10
AUTO_START     : false

Virtual Machines:
-----------------
VM Name              Status     Memory         
-----------------------------------------------
web1                 running    2097152 KiB    
web2                 running    2097152 KiB    
web3                 stopped    N/A
```

### Starting and Stopping Clusters

#### Start Cluster (Sequential)
```bash
./qemu_libvirt_manager.sh cluster-start webcluster
```

#### Start Cluster (Parallel)
```bash
./qemu_libvirt_manager.sh cluster-start webcluster true
```

#### Stop Cluster with Timeout
```bash
# Stop with 60s timeout (default)
./qemu_libvirt_manager.sh cluster-stop webcluster

# Stop with custom timeout and parallel mode
./qemu_libvirt_manager.sh cluster-stop webcluster 30 true
```

### Adding and Removing VMs

#### Add VM to Cluster
```bash
./qemu_libvirt_manager.sh cluster-add webcluster web4
```

#### Remove VM from Cluster
```bash
./qemu_libvirt_manager.sh cluster-remove webcluster web4
```

### Deleting Clusters

#### Delete Cluster Only (Keep VMs)
```bash
./qemu_libvirt_manager.sh cluster-delete webcluster
```

#### Delete Cluster and All VMs
```bash
./qemu_libvirt_manager.sh cluster-delete webcluster true
```

---

## Advanced Cluster Features

### Cluster Dashboard

View comprehensive cluster statistics and status:

```bash
./qemu_libvirt_manager.sh cluster-dashboard
```

**Dashboard Output:**
```
Cluster Management Dashboard
============================

Cluster Overview:
Total Clusters      : 3
Running Clusters    : 2
Total VMs          : 8
Running VMs        : 6
Total Memory       : 16384 MB
Total vCPUs        : 16

Cluster Status:
Cluster              Status     VMs (Run/Total)  Health    
---------------------------------------------------------------
webcluster           Running    3/3             100%      
dbcluster            Partial    1/2             50%       
testcluster          Stopped    0/3             0%
```

### Health Monitoring

#### Basic Health Check
```bash
./qemu_libvirt_manager.sh cluster-health webcluster
```

#### Detailed Health Check
```bash
./qemu_libvirt_manager.sh cluster-health webcluster true
```

**Health Check Output:**
```
Cluster Health Check: webcluster
========================================
✓ web1               : Running (CPU: 1234567890, Memory: 2097152 KiB)
✓ web2               : Running (CPU: 1234567891, Memory: 2097152 KiB)
○ web3               : Stopped

Health Summary:
  Total VMs: 3
  Running: 2
  Stopped: 1
  Failed/Issues: 0
  Health Score: 67%
  
Cluster Status: MOSTLY HEALTHY
```

### Cluster Scaling

#### Scale Up (Add VMs)
```bash
# Add 2 VMs without creating them
./qemu_libvirt_manager.sh cluster-scale webcluster add 2

# Add 2 VMs and create them automatically
./qemu_libvirt_manager.sh cluster-scale webcluster add 2 true
```

#### Scale Down (Remove VMs)
```bash
# Remove 1 VM from cluster
./qemu_libvirt_manager.sh cluster-scale webcluster remove 1
```

**Scaling Process:**
1. Validates cluster exists and scaling parameters
2. For scale-up: Creates new VMs if requested, adds to cluster
3. For scale-down: Removes VMs from cluster, optionally deletes VMs
4. Updates cluster configuration with new VM count
5. Provides detailed feedback on success/failure

---

## Cluster Templates

Templates allow you to create reusable cluster configurations for rapid deployment.

### Creating Templates

#### Command Line
```bash
./qemu_libvirt_manager.sh template-create web-template "Web Server Template" 2048 2 20 3
```

**Parameters:**
- `web-template`: Template name
- `"Web Server Template"`: Description
- `2048`: RAM in MB per VM
- `2`: vCPUs per VM
- `20`: Disk size in GB per VM
- `3`: Number of VMs in cluster

#### Interactive Mode
```bash
./qemu_libvirt_manager.sh interactive
# Select option 22 for "Create template"
```

### Using Templates

#### List Available Templates
```bash
./qemu_libvirt_manager.sh template-list
```

**Output:**
```
Template Name        VM Count   RAM(MB)  vCPUs    Description                             
--------------------------------------------------------------------------------
web-template         3          2048     2        Web Server Template
db-template          2          4096     4        Database Server Template
dev-template         5          1024     1        Development Environment
```

#### Create Cluster from Template

```bash
# Create cluster without VMs
./qemu_libvirt_manager.sh cluster-from-template newcluster web-template

# Create cluster and VMs automatically
./qemu_libvirt_manager.sh cluster-from-template newcluster web-template true
```

### Template Configuration

Templates are stored in `~/.config/qemu-manager/clusters/templates/` and contain:

```ini
# Cluster Template: web-template
TEMPLATE_NAME=web-template
DESCRIPTION=Web Server Template
CREATED=2025-08-01 13:38:00
VM_COUNT=3
VM_RAM=2048
VM_VCPUS=2
VM_DISK_SIZE=20
VM_OS_VARIANT=ubuntu22.04
STARTUP_ORDER=sequential
STARTUP_DELAY=5
SHUTDOWN_ORDER=reverse
SHUTDOWN_DELAY=10
AUTO_START=false
NETWORK=default
STORAGE_POOL=default
VM_PREFIX=web-template-vm
```

---

## Health Monitoring & Scaling

### Health Status Levels

| Health Score | Status | Description |
|-------------|--------|-------------|
| 100% | HEALTHY | All VMs running normally |
| 80-99% | MOSTLY HEALTHY | Most VMs running, minor issues |
| 50-79% | DEGRADED | Significant issues, reduced capacity |
| 0-49% | CRITICAL | Major problems, most VMs down |

### Health Check Types

#### Quick Health Check
- VM existence verification
- Basic state checking (running/stopped/failed)
- Health score calculation
- Status summary

#### Detailed Health Check
- All quick check features
- CPU utilization stats
- Memory usage information
- Network interface status
- Detailed per-VM reporting

### Automated Scaling Scenarios

#### Load-Based Scaling
```bash
# Monitor cluster and scale based on load
# (This would typically be done via external monitoring)

# Example: Scale up during high load
./qemu_libvirt_manager.sh cluster-scale webcluster add 2 true

# Example: Scale down during low load
./qemu_libvirt_manager.sh cluster-scale webcluster remove 1
```

#### Maintenance Scaling
```bash
# Temporarily remove VMs for maintenance
./qemu_libvirt_manager.sh cluster-scale webcluster remove 1

# Add back after maintenance
./qemu_libvirt_manager.sh cluster-scale webcluster add 1 true
```

---

## Backup & Restore

### Creating Backups

#### Automatic Backup (timestamp-based)
```bash
./qemu_libvirt_manager.sh cluster-backup webcluster
```

#### Named Backup
```bash
./qemu_libvirt_manager.sh cluster-backup webcluster production-v1.0
```

### Backup Contents

Each backup includes:
- **cluster.conf**: Complete cluster configuration
- **VM XML files**: Individual VM configurations
- **manifest.txt**: Backup metadata and file listing

### Backup Structure
```
~/.config/qemu-manager/clusters/backups/
├── webcluster_20250801_133000/
│   ├── cluster.conf
│   ├── web1.xml
│   ├── web2.xml
│   ├── web3.xml
│   └── manifest.txt
└── webcluster_production-v1.0/
    ├── cluster.conf
    ├── web1.xml
    ├── web2.xml
    └── manifest.txt
```

### Listing Backups

#### All Backups
```bash
./qemu_libvirt_manager.sh cluster-backups
```

#### Specific Cluster Backups
```bash
./qemu_libvirt_manager.sh cluster-backups webcluster
```

**Output:**
```
Backup Directory               Cluster              Created              VM Count  
--------------------------------------------------------------------------------
webcluster_20250801_133000     webcluster          2025-08-01 13:30:00  3         
webcluster_production-v1.0     webcluster          2025-08-01 14:15:22  3         
dbcluster_20250801_140000      dbcluster           2025-08-01 14:00:00  2
```

### Manual Restore Process

Currently, restore is a manual process:

1. **Locate backup:**
   ```bash
   ls ~/.config/qemu-manager/clusters/backups/
   ```

2. **Restore cluster configuration:**
   ```bash
   cp ~/.config/qemu-manager/clusters/backups/webcluster_backup/cluster.conf \
      ~/.config/qemu-manager/clusters/webcluster.conf
   ```

3. **Restore VM configurations:**
   ```bash
   # For each VM in the backup
   virsh define ~/.config/qemu-manager/clusters/backups/webcluster_backup/web1.xml
   ```

---

## Interactive Management

### Launching Interactive Mode
```bash
./qemu_libvirt_manager.sh interactive
```

### Menu Structure

#### VM Management (1-8)
- List VMs, start/stop individual VMs
- Create VMs, open viewers
- VM information and desktop shortcuts

#### Basic Cluster Management (11-18)
- List, create, start, stop clusters
- Cluster information and VM management
- Add/remove VMs, delete clusters

#### Advanced Cluster Features (21-28)
- Cluster dashboard and templates
- Health checks and scaling
- Backup management

#### System Tools (9)
- System resource monitoring
- Service status checks

### Interactive Examples

#### Creating a Cluster Interactively
1. Run `./qemu_libvirt_manager.sh interactive`
2. Select option `12` (Create cluster)
3. Enter cluster details:
   ```
   Cluster name: webcluster
   Description: Web Server Cluster
   VM names (space-separated): web1 web2 web3
   ```

#### Health Check with Interactive Mode
1. Run `./qemu_libvirt_manager.sh interactive`
2. Select option `25` (Health check)
3. Enter details:
   ```
   Cluster name for health check: webcluster
   Detailed check? [y/N]: y
   ```

---

## Configuration Reference

### Cluster Configuration File

Location: `~/.config/qemu-manager/clusters/<cluster-name>.conf`

```ini
# Cluster Configuration: webcluster
CLUSTER_NAME=webcluster
DESCRIPTION=Web Server Cluster
CREATED=2025-08-01 13:38:00
TEMPLATE_USED=web-template
VM=web1,web2,web3
VM_COUNT=3
VM_RAM=2048
VM_VCPUS=2
VM_DISK_SIZE=20
STARTUP_ORDER=sequential
STARTUP_DELAY=5
SHUTDOWN_ORDER=reverse
SHUTDOWN_DELAY=10
AUTO_START=false
```

### Configuration Parameters

| Parameter | Description | Values | Default |
|-----------|-------------|--------|---------|
| `CLUSTER_NAME` | Unique cluster identifier | String | Required |
| `DESCRIPTION` | Human-readable description | String | Required |
| `CREATED` | Timestamp of creation | ISO DateTime | Auto-generated |
| `TEMPLATE_USED` | Source template (if any) | Template name | Optional |
| `VM` | Comma-separated VM list | VM names | Required |
| `VM_COUNT` | Number of VMs | Integer | Auto-calculated |
| `VM_RAM` | RAM per VM (MB) | Integer | From template |
| `VM_VCPUS` | vCPUs per VM | Integer | From template |
| `VM_DISK_SIZE` | Disk size per VM (GB) | Integer | From template |
| `STARTUP_ORDER` | VM startup sequence | `sequential`/`reverse` | `sequential` |
| `STARTUP_DELAY` | Delay between starts (s) | Integer | `5` |
| `SHUTDOWN_ORDER` | VM shutdown sequence | `sequential`/`reverse` | `reverse` |
| `SHUTDOWN_DELAY` | Delay between stops (s) | Integer | `10` |
| `AUTO_START` | Auto-start on boot | `true`/`false` | `false` |

### Directory Structure

```
~/.config/qemu-manager/
├── clusters/                    # Cluster configurations
│   ├── webcluster.conf         # Individual cluster config
│   ├── dbcluster.conf
│   ├── templates/              # Cluster templates
│   │   ├── web-template.template
│   │   └── db-template.template
│   └── backups/                # Cluster backups
│       ├── webcluster_20250801_133000/
│       └── dbcluster_backup/
├── config                      # Main configuration
└── desktop-config             # Desktop integration settings
```

---

## Troubleshooting

### Common Issues

#### 1. Permission Denied Errors
**Problem**: `Permission denied` when accessing libvirt
**Solution**:
```bash
# Add user to libvirt group
sudo usermod -a -G libvirt $USER
# Logout and login again, or:
newgrp libvirt
```

#### 2. VMs Not Found
**Problem**: `VM 'name' does not exist` when creating cluster
**Solution**:
```bash
# Check existing VMs
./qemu_libvirt_manager.sh list
# Verify VM names are correct
virsh list --all
```

#### 3. Cluster Configuration Issues
**Problem**: Cluster commands fail or show wrong information
**Solution**:
```bash
# Check cluster configuration file
cat ~/.config/qemu-manager/clusters/<cluster-name>.conf
# Verify VM list format (comma-separated, no spaces)
```

#### 4. Template Creation Fails
**Problem**: Template creation reports validation errors
**Solution**:
```bash
# Check parameter types
./qemu_libvirt_manager.sh template-create name "desc" 2048 2 20 3
# Ensure numeric values are integers
# Ensure names contain only alphanumeric, hyphens, underscores
```

#### 5. Scaling Operations Fail
**Problem**: Scaling up/down doesn't work correctly
**Solution**:
```bash
# Check cluster exists
./qemu_libvirt_manager.sh cluster-list
# Verify VM naming convention
./qemu_libvirt_manager.sh cluster-info <cluster-name>
# Check available resources
./qemu_libvirt_manager.sh resources
```

### Debug Mode

Enable detailed logging:
```bash
# Check logs
tail -f ~/.local/share/qemu-manager/qemu-manager.log

# Manual debug commands
virsh list --all                    # Check all VMs
virsh domstate <vm-name>            # Check specific VM state
virsh dominfo <vm-name>             # Get VM details
```

### Recovery Procedures

#### Corrupted Cluster Configuration
1. **Backup current config:**
   ```bash
   cp ~/.config/qemu-manager/clusters/<cluster>.conf \
      ~/.config/qemu-manager/clusters/<cluster>.conf.backup
   ```

2. **Recreate from template or manually:**
   ```bash
   # From template
   ./qemu_libvirt_manager.sh cluster-from-template <cluster> <template>
   
   # Or recreate manually
   ./qemu_libvirt_manager.sh cluster-create <cluster> "desc" vm1 vm2 vm3
   ```

#### Missing VMs in Cluster
1. **Check VM existence:**
   ```bash
   virsh list --all
   ```

2. **Remove missing VMs:**
   ```bash
   ./qemu_libvirt_manager.sh cluster-remove <cluster> <missing-vm>
   ```

3. **Add replacement VMs:**
   ```bash
   ./qemu_libvirt_manager.sh cluster-add <cluster> <new-vm>
   ```

---

## Best Practices

### Cluster Design

#### 1. Naming Conventions
```bash
# Good naming patterns
webcluster-prod         # Environment-specific
db-cluster-mysql        # Service-specific
dev-env-team1          # Team/purpose-specific

# VM naming within clusters
webcluster-web1, webcluster-web2, webcluster-web3
db-cluster-master, db-cluster-slave1, db-cluster-slave2
```

#### 2. Resource Planning
```bash
# Check available resources before creating clusters
./qemu_libvirt_manager.sh resources

# Plan cluster sizes based on host capacity
# Example: 32GB host → max 4 VMs with 4GB each (+ host overhead)
```

#### 3. Template Strategy
```bash
# Create templates for common configurations
./qemu_libvirt_manager.sh template-create web-small "Small Web Server" 1024 1 10 3
./qemu_libvirt_manager.sh template-create web-large "Large Web Server" 4096 4 50 2
./qemu_libvirt_manager.sh template-create db-standard "Standard Database" 8192 4 100 1
```

### Operational Best Practices

#### 1. Regular Health Checks
```bash
# Daily health monitoring
./qemu_libvirt_manager.sh cluster-dashboard

# Detailed checks for critical clusters
./qemu_libvirt_manager.sh cluster-health production-web true
./qemu_libvirt_manager.sh cluster-health production-db true
```

#### 2. Backup Strategy
```bash
# Regular backups before changes
./qemu_libvirt_manager.sh cluster-backup production-web daily-$(date +%Y%m%d)

# Pre-maintenance backups
./qemu_libvirt_manager.sh cluster-backup production-web pre-maintenance-$(date +%Y%m%d)
```

#### 3. Scaling Guidelines
```bash
# Scale gradually
./qemu_libvirt_manager.sh cluster-scale webcluster add 1 true
# Wait and monitor before adding more

# Plan for peak loads
# Create templates for rapid scaling during expected high load
```

#### 4. Maintenance Procedures
```bash
# 1. Create backup
./qemu_libvirt_manager.sh cluster-backup <cluster> maintenance-backup

# 2. Health check before maintenance
./qemu_libvirt_manager.sh cluster-health <cluster> true

# 3. Graceful shutdown
./qemu_libvirt_manager.sh cluster-stop <cluster> 120 false

# 4. Perform maintenance
# ... maintenance tasks ...

# 5. Restart cluster
./qemu_libvirt_manager.sh cluster-start <cluster> false

# 6. Post-maintenance health check
./qemu_libvirt_manager.sh cluster-health <cluster> true
```

### Security Considerations

#### 1. File Permissions
```bash
# Ensure proper permissions on configuration files
chmod 600 ~/.config/qemu-manager/clusters/*.conf
chmod 700 ~/.config/qemu-manager/clusters/
```

#### 2. Network Security
- Use appropriate libvirt network configurations
- Implement proper firewall rules for cluster communication
- Consider network isolation between clusters

#### 3. Access Control
- Use libvirt group membership for access control
- Avoid running cluster operations as root
- Implement proper sudo policies if needed

### Performance Optimization

#### 1. Resource Allocation
```bash
# Monitor resource usage
./qemu_libvirt_manager.sh resources
./qemu_libvirt_manager.sh cluster-dashboard

# Adjust VM resources based on actual usage
# Use templates to standardize optimal configurations
```

#### 2. Startup Optimization
```bash
# Use appropriate startup delays
STARTUP_DELAY=3    # For fast SSD storage
STARTUP_DELAY=5    # For standard storage
STARTUP_DELAY=10   # For slow storage or heavy VMs
```

#### 3. Parallel Operations
```bash
# Use parallel operations for better performance
./qemu_libvirt_manager.sh cluster-start <cluster> true    # Parallel start
./qemu_libvirt_manager.sh cluster-stop <cluster> 60 true  # Parallel stop
```

---

## Command Reference Summary

### Basic Cluster Commands
```bash
./qemu_libvirt_manager.sh cluster-list
./qemu_libvirt_manager.sh cluster-create <name> [description] <vm1> [vm2] [...]
./qemu_libvirt_manager.sh cluster-start <name> [parallel]
./qemu_libvirt_manager.sh cluster-stop <name> [timeout] [parallel]
./qemu_libvirt_manager.sh cluster-info <name>
./qemu_libvirt_manager.sh cluster-add <cluster> <vm>
./qemu_libvirt_manager.sh cluster-remove <cluster> <vm>
./qemu_libvirt_manager.sh cluster-delete <name> [delete-vms]
```

### Advanced Cluster Commands
```bash
./qemu_libvirt_manager.sh cluster-dashboard
./qemu_libvirt_manager.sh cluster-health <name> [detailed]
./qemu_libvirt_manager.sh cluster-scale <name> <add|remove> <count> [create-vms]
./qemu_libvirt_manager.sh cluster-backup <name> [backup-name]
./qemu_libvirt_manager.sh cluster-backups [cluster-name]
```

### Template Commands
```bash
./qemu_libvirt_manager.sh template-create <name> <description> <ram> <vcpus> <disk> [count]
./qemu_libvirt_manager.sh template-list
./qemu_libvirt_manager.sh cluster-from-template <cluster> <template> [create-vms]
```

### Interactive Mode
```bash
./qemu_libvirt_manager.sh interactive
```

---

*This documentation covers the enhanced QEMU/Libvirt Cluster Management system. For additional support or feature requests, please refer to the script's help system or create an issue in the project repository.*