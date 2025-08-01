# QEMU/Libvirt Cluster Management - Quick Reference

## 🚀 Quick Start

```bash
# Check system
./qemu_libvirt_manager.sh check

# Install desktop integration
./qemu_libvirt_manager.sh install-desktop

# Launch interactive mode
./qemu_libvirt_manager.sh interactive
```

## 📋 Essential Commands

### Basic Operations
```bash
# List everything
./qemu_libvirt_manager.sh list                    # List VMs
./qemu_libvirt_manager.sh cluster-list            # List clusters
./qemu_libvirt_manager.sh template-list           # List templates

# Create cluster from existing VMs
./qemu_libvirt_manager.sh cluster-create webcluster "Web servers" web1 web2 web3

# Start/Stop clusters
./qemu_libvirt_manager.sh cluster-start webcluster         # Sequential
./qemu_libvirt_manager.sh cluster-start webcluster true    # Parallel
./qemu_libvirt_manager.sh cluster-stop webcluster 60 true  # 60s timeout, parallel
```

### Templates
```bash
# Create template
./qemu_libvirt_manager.sh template-create web-template "Web Server" 2048 2 20 3

# Create cluster from template (with VMs)
./qemu_libvirt_manager.sh cluster-from-template newcluster web-template true
```

### Health & Monitoring
```bash
# Dashboard overview
./qemu_libvirt_manager.sh cluster-dashboard

# Health check
./qemu_libvirt_manager.sh cluster-health webcluster true   # Detailed

# System resources
./qemu_libvirt_manager.sh resources
```

### Scaling
```bash
# Scale up (add 2 VMs)
./qemu_libvirt_manager.sh cluster-scale webcluster add 2 true

# Scale down (remove 1 VM)
./qemu_libvirt_manager.sh cluster-scale webcluster remove 1
```

### Backup
```bash
# Create backup
./qemu_libvirt_manager.sh cluster-backup webcluster prod-backup

# List backups
./qemu_libvirt_manager.sh cluster-backups webcluster
```

## 🎛️ Interactive Mode Menu

```
VM Management (1-8):
1) List VMs          2) Running VMs       3) Start VM         4) Stop VM
5) Create VM         6) VM viewer         7) VM info          8) Desktop shortcut

Cluster Management (11-18):
11) List clusters    12) Create cluster   13) Start cluster   14) Stop cluster
15) Cluster info     16) Add VM           17) Remove VM       18) Delete cluster

Advanced Cluster (21-28):
21) Dashboard        22) Create template  23) List templates  24) From template
25) Health check     26) Scale cluster    27) Backup cluster  28) List backups

System (9):
9) System resources  0) Exit
```

## 📁 File Locations

```bash
# Configuration
~/.config/qemu-manager/clusters/           # Cluster configs
~/.config/qemu-manager/clusters/templates/ # Templates
~/.config/qemu-manager/clusters/backups/   # Backups

# Logs
~/.local/share/qemu-manager/qemu-manager.log

# Desktop integration
~/.local/share/applications/               # Desktop files
```

## 🔧 Common Workflows

### Create Production Web Cluster
```bash
# 1. Create template
./qemu_libvirt_manager.sh template-create web-prod "Production Web" 4096 4 50 3

# 2. Create cluster with VMs
./qemu_libvirt_manager.sh cluster-from-template web-prod-cluster web-prod true

# 3. Check health
./qemu_libvirt_manager.sh cluster-health web-prod-cluster true

# 4. Create backup
./qemu_libvirt_manager.sh cluster-backup web-prod-cluster initial-deployment
```

### Daily Maintenance
```bash
# 1. Check dashboard
./qemu_libvirt_manager.sh cluster-dashboard

# 2. Health check critical clusters
./qemu_libvirt_manager.sh cluster-health production-web true
./qemu_libvirt_manager.sh cluster-health production-db true

# 3. Create daily backup
./qemu_libvirt_manager.sh cluster-backup production-web daily-$(date +%Y%m%d)
```

### Emergency Scale-Up
```bash
# 1. Check current status
./qemu_libvirt_manager.sh cluster-info webcluster

# 2. Scale up quickly
./qemu_libvirt_manager.sh cluster-scale webcluster add 3 true

# 3. Verify health
./qemu_libvirt_manager.sh cluster-health webcluster true
```

## ⚡ Tips & Tricks

### Performance
- Use `parallel=true` for faster start/stop operations
- Monitor resources with dashboard before scaling
- Use appropriate startup delays based on storage speed

### Reliability
- Always backup before major changes
- Use health checks to verify operations
- Scale gradually and monitor

### Organization
- Use descriptive cluster names (e.g., `web-prod`, `db-staging`)
- Create templates for common configurations
- Regular backup schedule for critical clusters

## 🚨 Emergency Commands

```bash
# Force stop all VMs in cluster
for vm in $(./qemu_libvirt_manager.sh cluster-info CLUSTER | grep running | awk '{print $1}'); do
    virsh destroy $vm
done

# Quick cluster status
./qemu_libvirt_manager.sh cluster-dashboard | grep -A 20 "Cluster Status"

# Check logs for errors
tail -50 ~/.local/share/qemu-manager/qemu-manager.log | grep ERROR
```

## 📞 Get Help

```bash
# Full help
./qemu_libvirt_manager.sh help

# Check dependencies
./qemu_libvirt_manager.sh check

# View version
./qemu_libvirt_manager.sh version
```

---

💡 **Pro Tip**: Use the interactive mode (`./qemu_libvirt_manager.sh interactive`) for guided operations and menu-driven management!