#!/bin/bash

# QEMU/Libvirt Management Script
# This script provides functions to manage QEMU/Libvirt virtual machines

set -e

# Colors for better output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if libvirt is installed
check_dependencies() {
    local missing_deps=()
    
    for cmd in virsh virt-install qemu-img virt-viewer virt-clone; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}Missing dependencies: ${missing_deps[*]}${NC}"
        echo -e "${YELLOW}Please install required packages:${NC}"
        echo -e "${BLUE}sudo apt-get install qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst virt-manager virt-viewer${NC}"
        exit 1
    fi
}

# Display status of libvirt service
check_service_status() {
    echo -e "${BLUE}Checking libvirt service status...${NC}"
    systemctl status libvirtd --no-pager
}

# List all VMs
list_vms() {
    echo -e "${BLUE}Listing all virtual machines:${NC}"
    virsh list --all
}

# List running VMs
list_running_vms() {
    echo -e "${BLUE}Listing running virtual machines:${NC}"
    virsh list
}

# Start a VM
start_vm() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: VM name required${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Starting VM: $1${NC}"
    virsh start "$1"
}

# Stop a VM
stop_vm() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: VM name required${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Stopping VM: $1${NC}"
    virsh shutdown "$1"
}

# Force stop a VM
force_stop_vm() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: VM name required${NC}"
        return 1
    fi
    
    echo -e "${RED}Force stopping VM: $1${NC}"
    virsh destroy "$1"
}

# Delete a VM
delete_vm() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: VM name required${NC}"
        return 1
    fi
    
    local vm_name="$1"
    echo -e "${RED}Deleting VM: $vm_name${NC}"
    
    # Check if VM exists
    if ! virsh dominfo "$vm_name" &> /dev/null; then
        echo -e "${RED}VM $vm_name does not exist${NC}"
        return 1
    fi
    
    # Ensure VM is stopped
    if virsh domstate "$vm_name" | grep -q "running"; then
        echo -e "${YELLOW}VM is running. Stopping it first...${NC}"
        virsh destroy "$vm_name"
    fi
    
    # Get storage info
    local storage_files=$(virsh domblklist "$vm_name" | grep -v "^$\|Target\|Source" | awk '{print $2}')
    
    # Undefine the VM
    virsh undefine "$vm_name" --remove-all-storage
    
    echo -e "${GREEN}VM $vm_name has been deleted${NC}"
}

# Get VM info
vm_info() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: VM name required${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Information for VM: $1${NC}"
    virsh dominfo "$1"
}

# Connect to VM console
vm_console() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: VM name required${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Connecting to console of VM: $1${NC}"
    echo -e "${YELLOW}To exit the console, press Ctrl+] or Ctrl+5${NC}"
    virsh console "$1"
}

# Open VM display with virt-viewer
vm_view() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: VM name required${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Opening display for VM: $1${NC}"
    virt-viewer "$1" &
}

# Get VNC connection info for VM
vm_vnc_info() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: VM name required${NC}"
        return 1
    fi
    
    echo -e "${BLUE}VNC connection information for VM: $1${NC}"
    virsh vncdisplay "$1"
}

# Get SPICE connection info for VM
vm_spice_info() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: VM name required${NC}"
        return 1
    fi
    
    echo -e "${BLUE}SPICE connection information for VM: $1${NC}"
    virsh domdisplay "$1" | grep spice
}

# Show host resource usage
show_resources() {
    echo -e "${BLUE}Host CPU usage:${NC}"
    virsh nodecpustats --percent
    
    echo -e "\n${BLUE}Host memory usage:${NC}"
    virsh nodememstats
    
    echo -e "\n${BLUE}Running VMs resource usage:${NC}"
    virsh list --name | grep -v "^$" | while read -r vm; do
        echo -e "\n${GREEN}VM: $vm${NC}"
        virsh domstats "$vm" --cpu-total --balloon --vcpu --interface
    done
}

# Enable/disable VM autostart
vm_autostart() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: VM name required${NC}"
        return 1
    fi
    
    local vm="$1"
    local state="${2:-on}"  # Default to enabling autostart
    
    if [ "$state" = "on" ]; then
        echo -e "${BLUE}Enabling autostart for VM: $vm${NC}"
        virsh autostart "$vm"
    else
        echo -e "${BLUE}Disabling autostart for VM: $vm${NC}"
        virsh autostart --disable "$vm"
    fi
}

# Create a new VM from ISO
create_vm_from_iso() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
        echo -e "${RED}Error: Missing required parameters${NC}"
        echo -e "${YELLOW}Usage: create_vm_from_iso <name> <ram_mb> <vcpus> <iso_path> [disk_size_gb]${NC}"
        return 1
    fi
    
    local name="$1"
    local ram="$2"
    local vcpus="$3"
    local iso="$4"
    local disk_size="${5:-20}"  # Default 20GB if not specified
    
    # Check if ISO exists
    if [ ! -f "$iso" ]; then
        echo -e "${RED}Error: ISO file not found: $iso${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Creating VM: $name${NC}"
    echo -e "${BLUE}RAM: ${ram}MB, vCPUs: $vcpus, Disk: ${disk_size}GB${NC}"
    
    virt-install \
        --name "$name" \
        --ram "$ram" \
        --vcpus "$vcpus" \
        --disk size="$disk_size" \
        --cdrom "$iso" \
        --os-variant generic \
        --network default \
        --graphics vnc
}

# Create a VM from an existing disk image
create_vm_from_image() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
        echo -e "${RED}Error: Missing required parameters${NC}"
        echo -e "${YELLOW}Usage: create_vm_from_image <name> <ram_mb> <vcpus> <disk_image_path>${NC}"
        return 1
    fi
    
    local name="$1"
    local ram="$2"
    local vcpus="$3"
    local disk_image="$4"
    
    # Check if disk image exists
    if [ ! -f "$disk_image" ]; then
        echo -e "${RED}Error: Disk image not found: $disk_image${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Creating VM: $name from existing disk image${NC}"
    echo -e "${BLUE}RAM: ${ram}MB, vCPUs: $vcpus${NC}"
    
    virt-install \
        --name "$name" \
        --ram "$ram" \
        --vcpus "$vcpus" \
        --import \
        --disk path="$disk_image" \
        --os-variant generic \
        --network default \
        --graphics vnc
}

# Clone an existing VM
clone_vm() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo -e "${RED}Error: Missing required parameters${NC}"
        echo -e "${YELLOW}Usage: clone_vm <source_vm> <new_vm_name>${NC}"
        return 1
    fi
    
    local source="$1"
    local target="$2"
    
    echo -e "${BLUE}Cloning VM: $source to $target${NC}"
    virt-clone --original "$source" --name "$target" --auto-clone
}

# Create a snapshot of a VM
create_snapshot() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo -e "${RED}Error: Missing required parameters${NC}"
        echo -e "${YELLOW}Usage: create_snapshot <vm_name> <snapshot_name>${NC}"
        return 1
    fi
    
    local vm="$1"
    local snapshot="$2"
    
    echo -e "${BLUE}Creating snapshot: $snapshot for VM: $vm${NC}"
    virsh snapshot-create-as "$vm" "$snapshot" --description "Snapshot created on $(date)"
}

# List snapshots for a VM
list_snapshots() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: VM name required${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Listing snapshots for VM: $1${NC}"
    virsh snapshot-list "$1"
}

# Restore a VM from a snapshot
restore_snapshot() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo -e "${RED}Error: Missing required parameters${NC}"
        echo -e "${YELLOW}Usage: restore_snapshot <vm_name> <snapshot_name>${NC}"
        return 1
    fi
    
    local vm="$1"
    local snapshot="$2"
    
    echo -e "${BLUE}Restoring VM: $vm to snapshot: $snapshot${NC}"
    virsh snapshot-revert "$vm" "$snapshot"
}

# Delete a snapshot
delete_snapshot() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo -e "${RED}Error: Missing required parameters${NC}"
        echo -e "${YELLOW}Usage: delete_snapshot <vm_name> <snapshot_name>${NC}"
        return 1
    fi
    
    local vm="$1"
    local snapshot="$2"
    
    echo -e "${BLUE}Deleting snapshot: $snapshot for VM: $vm${NC}"
    virsh snapshot-delete "$vm" "$snapshot"
}

# Show VM's network information
vm_network_info() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: VM name required${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Network information for VM: $1${NC}"
    virsh domifaddr "$1"
    
    echo -e "${BLUE}Network interfaces for VM: $1${NC}"
    virsh domiflist "$1"
}

# List storage pools
list_storage_pools() {
    echo -e "${BLUE}Listing storage pools:${NC}"
    virsh pool-list --all
}

# Create a new storage pool
create_storage_pool() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo -e "${RED}Error: Missing required parameters${NC}"
        echo -e "${YELLOW}Usage: create_storage_pool <name> <path>${NC}"
        return 1
    fi
    
    local name="$1"
    local path="$2"
    
    # Ensure directory exists
    mkdir -p "$path"
    
    echo -e "${BLUE}Creating storage pool: $name at $path${NC}"
    virsh pool-define-as "$name" dir --target "$path"
    virsh pool-build "$name"
    virsh pool-start "$name"
    virsh pool-autostart "$name"
}

# Delete a storage pool
delete_storage_pool() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Pool name required${NC}"
        return 1
    fi
    
    local pool="$1"
    echo -e "${RED}Deleting storage pool: $pool${NC}"
    
    # Check if pool is active
    if virsh pool-info "$pool" | grep -q "State:.*active"; then
        echo -e "${YELLOW}Pool is active. Stopping it first...${NC}"
        virsh pool-destroy "$pool"
    fi
    
    # Undefine the pool
    virsh pool-undefine "$pool"
    echo -e "${GREEN}Storage pool $pool has been deleted${NC}"
}

# List volumes in a storage pool
list_volumes() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Pool name required${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Listing volumes in storage pool: $1${NC}"
    virsh vol-list "$1"
}

# Create a new disk image
create_disk_image() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        echo -e "${RED}Error: Missing required parameters${NC}"
        echo -e "${YELLOW}Usage: create_disk_image <path> <size_gb> <format>${NC}"
        return 1
    fi
    
    local path="$1"
    local size="$2"
    local format="$3"
    
    echo -e "${BLUE}Creating disk image: $path, Size: ${size}GB, Format: $format${NC}"
    qemu-img create -f "$format" "$path" "${size}G"
}

# Show disk image info
disk_image_info() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Image path required${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Disk image information for: $1${NC}"
    qemu-img info "$1"
}

# Convert disk image format
convert_disk_image() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        echo -e "${RED}Error: Missing required parameters${NC}"
        echo -e "${YELLOW}Usage: convert_disk_image <input_path> <output_path> <output_format>${NC}"
        return 1
    fi
    
    local input="$1"
    local output="$2"
    local format="$3"
    
    echo -e "${BLUE}Converting disk image: $input to $output (format: $format)${NC}"
    qemu-img convert -f qcow2 -O "$format" "$input" "$output"
}

# Resize a disk image
resize_disk_image() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo -e "${RED}Error: Missing required parameters${NC}"
        echo -e "${YELLOW}Usage: resize_disk_image <path> <new_size_gb>${NC}"
        return 1
    fi
    
    local path="$1"
    local size="$2"
    
    echo -e "${BLUE}Resizing disk image: $path to ${size}GB${NC}"
    qemu-img resize "$path" "${size}G"
}

# List virtual networks
list_networks() {
    echo -e "${BLUE}Listing virtual networks:${NC}"
    virsh net-list --all
}

# Show virtual network information
network_info() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Network name required${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Information for network: $1${NC}"
    virsh net-info "$1"
    
    echo -e "\n${BLUE}XML definition for network: $1${NC}"
    virsh net-dumpxml "$1"
}

# Start a virtual network
start_network() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Network name required${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Starting network: $1${NC}"
    virsh net-start "$1"
}

# Stop a virtual network
stop_network() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Network name required${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Stopping network: $1${NC}"
    virsh net-destroy "$1"
}

# Show host information
host_info() {
    echo -e "${BLUE}Host information:${NC}"
    virsh nodeinfo
    
    echo -e "\n${BLUE}CPU information:${NC}"
    lscpu | grep -E "Model name|Socket|Core|Thread|CPU\(s\)"
    
    echo -e "\n${BLUE}Memory information:${NC}"
    free -h
    
    echo -e "\n${BLUE}Storage information:${NC}"
    df -h | grep -v tmpfs
}

# Backup a VM
backup_vm() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo -e "${RED}Error: Missing required parameters${NC}"
        echo -e "${YELLOW}Usage: backup_vm <vm_name> <backup_dir>${NC}"
        return 1
    fi
    
    local vm="$1"
    local backup_dir="$2"
    local date_str=$(date +"%Y%m%d_%H%M%S")
    local backup_path="${backup_dir}/${vm}_${date_str}"
    
    # Ensure backup directory exists
    mkdir -p "$backup_dir"
    
    echo -e "${BLUE}Backing up VM: $vm to $backup_path${NC}"
    
    # Export VM configuration
    echo -e "${YELLOW}Exporting VM configuration...${NC}"
    virsh dumpxml "$vm" > "${backup_path}.xml"
    
    # Check if VM is running
    local vm_running=false
    if virsh domstate "$vm" | grep -q "running"; then
        vm_running=true
        echo -e "${YELLOW}VM is running. Creating snapshot for backup...${NC}"
        virsh snapshot-create-as "$vm" "backup_snapshot_${date_str}" --disk-only --atomic
    fi
    
    # Get disk paths
    local disk_paths=$(virsh domblklist "$vm" | grep -v "^$\|Target\|Source" | awk '{print $2}' | grep -v "^-$")
    
    # Copy disk images
    for disk in $disk_paths; do
        if [ -f "$disk" ]; then
            local disk_name=$(basename "$disk")
            echo -e "${YELLOW}Copying disk: $disk_name...${NC}"
            cp "$disk" "${backup_path}_${disk_name}"
        fi
    done
    
    # Remove temporary snapshot if VM was running
    if [ "$vm_running" = true ]; then
        echo -e "${YELLOW}Removing temporary snapshot...${NC}"
        virsh blockcommit "$vm" vda --active --pivot
        virsh snapshot-delete "$vm" "backup_snapshot_${date_str}" --metadata
    fi
    
    echo -e "${GREEN}Backup of VM $vm completed at ${backup_path}${NC}"
}

# Restore a VM from backup
restore_vm() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        echo -e "${RED}Error: Missing required parameters${NC}"
        echo -e "${YELLOW}Usage: restore_vm <backup_xml> <disk_paths> <new_vm_name>${NC}"
        return 1
    fi
    
    local backup_xml="$1"
    local disk_paths="$2"
    local new_name="$3"
    
    # Check if XML file exists
    if [ ! -f "$backup_xml" ]; then
        echo -e "${RED}Error: Backup XML file not found: $backup_xml${NC}"
        return 1
    fi
    
    # Check if all disk images exist
    for disk in $disk_paths; do
        if [ ! -f "$disk" ]; then
            echo -e "${RED}Error: Disk image not found: $disk${NC}"
            return 1
        fi
    done
    
    echo -e "${BLUE}Restoring VM from backup as: $new_name${NC}"
    
    # Create temporary XML file with new name
    local temp_xml="/tmp/${new_name}_restore.xml"
    cp "$backup_xml" "$temp_xml"
    sed -i "s/<name>.*<\/name>/<name>$new_name<\/name>/g" "$temp_xml"
    
    # Define VM from XML
    echo -e "${YELLOW}Defining VM from backup XML...${NC}"
    virsh define "$temp_xml"
    
    echo -e "${GREEN}VM $new_name has been restored from backup${NC}"
}

# Show help
show_help() {
    echo -e "${GREEN}QEMU/Libvirt Management Script${NC}"
    echo -e "${YELLOW}Usage: $0 <command> [arguments]${NC}"
    echo
    echo -e "${BLUE}VM Management:${NC}"
    echo "  list                           - List all VMs"
    echo "  running                        - List running VMs"
    echo "  start <vm_name>                - Start a VM"
    echo "  stop <vm_name>                 - Stop a VM gracefully"
    echo "  force-stop <vm_name>           - Force stop a VM"
    echo "  delete <vm_name>               - Delete a VM"
    echo "  info <vm_name>                 - Show VM information"
    echo "  console <vm_name>              - Connect to VM console"
    echo "  network <vm_name>              - Show VM network information"
    echo "  view <vm_name>                 - Open VM display with virt-viewer"
    echo "  vnc <vm_name>                  - Get VNC connection info for VM"
    echo "  spice <vm_name>                - Get SPICE connection info for VM"
    echo "  resources                      - Show host resource usage"
    echo "  autostart <vm_name> [on|off]   - Enable/disable VM autostart"
    echo
    echo -e "${BLUE}VM Creation:${NC}"
    echo "  create-iso <name> <ram_mb> <vcpus> <iso_path> [disk_size_gb]"
    echo "                                 - Create a VM from ISO"
    echo "  create-image <name> <ram_mb> <vcpus> <disk_image_path>"
    echo "                                 - Create a VM from existing disk image"
    echo "  clone <source_vm> <new_vm_name> - Clone an existing VM"
    echo
    echo -e "${BLUE}Snapshot Management:${NC}"
    echo "  snapshots <vm_name>            - List snapshots for a VM"
    echo "  snapshot-create <vm_name> <snapshot_name>"
    echo "                                 - Create a snapshot"
    echo "  snapshot-restore <vm_name> <snapshot_name>"
    echo "                                 - Restore a VM from snapshot"
    echo "  snapshot-delete <vm_name> <snapshot_name>"
    echo "                                 - Delete a snapshot"
    echo
    echo -e "${BLUE}Storage Management:${NC}"
    echo "  pools                          - List storage pools"
    echo "  pool-create <name> <path>      - Create a storage pool"
    echo "  pool-delete <name>             - Delete a storage pool"
    echo "  volumes <pool_name>            - List volumes in a storage pool"
    echo "  disk-create <path> <size_gb> <format>"
    echo "                                 - Create a disk image"
    echo "  disk-info <path>               - Show disk image info"
    echo "  disk-convert <input> <output> <format>"
    echo "                                 - Convert disk image format"
    echo "  disk-resize <path> <new_size_gb>"
    echo "                                 - Resize a disk image"
    echo
    echo -e "${BLUE}Network Management:${NC}"
    echo "  net-list                       - List virtual networks"
    echo "  net-info <network_name>        - Show virtual network information"
    echo "  net-start <network_name>       - Start a virtual network"
    echo "  net-stop <network_name>        - Stop a virtual network"
    echo
    echo -e "${BLUE}Backup and Restore:${NC}"
    echo "  backup <vm_name> <backup_dir>  - Backup a VM"
    echo "  restore <backup_xml> <disk_paths> <new_vm_name>"
    echo "                                 - Restore a VM from backup"
    echo
    echo -e "${BLUE}System:${NC}"
    echo "  status                         - Show libvirt service status"
    echo "  check                          - Check dependencies"
    echo "  host-info                      - Show host information"
    echo "  help                           - Show this help message"
}

# Main function to handle command-line arguments
main() {
    # Check if no arguments provided
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi
    
    # Parse command
    case "$1" in
        list)
            list_vms
            ;;
        running)
            list_running_vms
            ;;
        start)
            start_vm "$2"
            ;;
        stop)
            stop_vm "$2"
            ;;
        force-stop)
            force_stop_vm "$2"
            ;;
        delete)
            delete_vm "$2"
            ;;
        info)
            vm_info "$2"
            ;;
        console)
            vm_console "$2"
            ;;
        network)
            vm_network_info "$2"
            ;;
        view)
            vm_view "$2"
            ;;
        vnc)
            vm_vnc_info "$2"
            ;;
        spice)
            vm_spice_info "$2"
            ;;
        resources)
            show_resources
            ;;
        autostart)
            vm_autostart "$2" "$3"
            ;;
        create-iso)
            create_vm_from_iso "$2" "$3" "$4" "$5" "$6"
            ;;
        create-image)
            create_vm_from_image "$2" "$3" "$4" "$5"
            ;;
        clone)
            clone_vm "$2" "$3"
            ;;
        snapshots)
            list_snapshots "$2"
            ;;
        snapshot-create)
            create_snapshot "$2" "$3"
            ;;
        snapshot-restore)
            restore_snapshot "$2" "$3"
            ;;
        snapshot-delete)
            delete_snapshot "$2" "$3"
            ;;
        pools)
            list_storage_pools
            ;;
        pool-create)
            create_storage_pool "$2" "$3"
            ;;
        pool-delete)
            delete_storage_pool "$2"
            ;;
        volumes)
            list_volumes "$2"
            ;;
        disk-create)
            create_disk_image "$2" "$3" "$4"
            ;;
        disk-info)
            disk_image_info "$2"
            ;;
        disk-convert)
            convert_disk_image "$2" "$3" "$4"
            ;;
        disk-resize)
            resize_disk_image "$2" "$3"
            ;;
        net-list)
            list_networks
            ;;
        net-info)
            network_info "$2"
            ;;
        net-start)
            start_network "$2"
            ;;
        net-stop)
            stop_network "$2"
            ;;
        backup)
            backup_vm "$2" "$3"
            ;;
        restore)
            restore_vm "$2" "$3" "$4"
            ;;
        host-info)
            host_info
            ;;
        status)
            check_service_status
            ;;
        check)
            check_dependencies
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown command: $1${NC}"
            show_help
            exit 1
            ;;
    esac
}

# Run the main function with all arguments
main "$@"