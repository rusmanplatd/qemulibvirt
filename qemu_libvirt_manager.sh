#!/bin/bash
# Enhanced QEMU/Libvirt Management Script
# This script provides comprehensive functions to manage QEMU/Libvirt virtual machines
set -euo pipefail
IFS=$'\n\t'

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for better output
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Logging setup
readonly LOG_DIR="${HOME}/.local/share/qemu-manager"
readonly LOG_FILE="${LOG_DIR}/qemu-manager.log"
readonly MAX_LOG_SIZE=10485760  # 10MB

# Configuration
readonly CONFIG_FILE="${HOME}/.config/qemu-manager/config"
readonly DEFAULT_STORAGE_POOL="default"
readonly DEFAULT_NETWORK="default"

# Initialize logging
init_logging() {
    mkdir -p "$LOG_DIR"
    
    # Rotate log if too large
    if [[ -f "$LOG_FILE" && $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt $MAX_LOG_SIZE ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
    fi
    
    # Create log file if it doesn't exist
    touch "$LOG_FILE"
}

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { log "DEBUG" "$@"; }

# Output functions with logging
print_info() {
    echo -e "${BLUE}$*${NC}"
    log_info "$*"
}

print_success() {
    echo -e "${GREEN}$*${NC}"
    log_info "SUCCESS: $*"
}

print_warning() {
    echo -e "${YELLOW}$*${NC}"
    log_warn "$*"
}

print_error() {
    echo -e "${RED}$*${NC}" >&2
    log_error "$*"
}

# Enhanced error handling
error_exit() {
    print_error "Error: $*"
    exit 1
}

# Validate VM name format
validate_vm_name() {
    local vm_name="$1"
    if [[ ! "$vm_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error_exit "Invalid VM name. Use only alphanumeric characters, hyphens, and underscores."
    fi
    if [[ ${#vm_name} -gt 64 ]]; then
        error_exit "VM name too long. Maximum 64 characters allowed."
    fi
}

# Check if VM exists
vm_exists() {
    local vm_name="$1"
    virsh dominfo "$vm_name" &>/dev/null
}

# Check if VM is running
vm_is_running() {
    local vm_name="$1"
    [[ "$(virsh domstate "$vm_name" 2>/dev/null)" == "running" ]]
}

# Validate numeric input
validate_number() {
    local value="$1"
    local name="$2"
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        error_exit "$name must be a positive integer"
    fi
}

# Validate file exists
validate_file_exists() {
    local file="$1"
    local description="$2"
    if [[ ! -f "$file" ]]; then
        error_exit "$description not found: $file"
    fi
}

# Check if user has necessary permissions
check_permissions() {
    if ! groups | grep -q libvirt; then
        print_warning "User is not in libvirt group. You may need to run commands with sudo."
        print_info "To add yourself to libvirt group: sudo usermod -a -G libvirt \$USER"
    fi
}

# Enhanced dependency checking
check_dependencies() {
    local missing_deps=()
    local optional_deps=()
    
    # Required dependencies
    local required_cmds=(virsh virt-install qemu-img)
    # Optional dependencies
    local optional_cmds=(virt-viewer virt-clone virt-manager)
    
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    for cmd in "${optional_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            optional_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -ne 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_info "Install required packages:"
        print_info "Ubuntu/Debian: sudo apt-get install qemu-kvm libvirt-daemon-system libvirt-clients"
        print_info "RHEL/CentOS: sudo yum install qemu-kvm libvirt"
        print_info "Arch: sudo pacman -S qemu libvirt"
        exit 1
    fi
    
    if [[ ${#optional_deps[@]} -ne 0 ]]; then
        print_warning "Optional dependencies not found: ${optional_deps[*]}"
        print_info "Install for full functionality:"
        print_info "Ubuntu/Debian: sudo apt-get install bridge-utils virtinst virt-manager virt-viewer"
    fi
    
    check_permissions
    print_success "All required dependencies are installed"
}

# Enhanced service status check
check_service_status() {
    print_info "Checking libvirt service status..."
    
    if systemctl is-active --quiet libvirtd; then
        print_success "libvirtd service is running"
    else
        print_warning "libvirtd service is not running"
        print_info "Start with: sudo systemctl start libvirtd"
    fi
    
    if systemctl is-enabled --quiet libvirtd; then
        print_success "libvirtd service is enabled"
    else
        print_warning "libvirtd service is not enabled"
        print_info "Enable with: sudo systemctl enable libvirtd"
    fi
    
    # Show detailed status
    systemctl status libvirtd --no-pager 2>/dev/null || true
}

# Enhanced VM listing with additional info
list_vms() {
    print_info "Listing all virtual machines:"
    echo
    virsh list --all
    echo
    
    # Additional summary
    local total_vms=$(virsh list --all --name | grep -c . || echo "0")
    local running_vms=$(virsh list --name | grep -c . || echo "0")
    local stopped_vms=$((total_vms - running_vms))
    
    print_info "Summary: $total_vms total VMs ($running_vms running, $stopped_vms stopped)"
}

# List running VMs with resource usage
list_running_vms() {
    print_info "Listing running virtual machines:"
    echo
    virsh list
    echo
    
    # Show resource usage for running VMs
    local running_vms=($(virsh list --name))
    if [[ ${#running_vms[@]} -gt 0 ]]; then
        print_info "Resource usage:"
        printf "%-20s %-10s %-10s %-15s\n" "VM Name" "CPU%" "Memory" "State"
        echo "------------------------------------------------------------"
        for vm in "${running_vms[@]}"; do
            if [[ -n "$vm" ]]; then
                local cpu_time=$(virsh cpu-stats "$vm" --total 2>/dev/null | grep "cpu_time" | awk '{print $3}' || echo "N/A")
                local memory=$(virsh dominfo "$vm" | grep "Used memory" | awk '{print $3 " " $4}' || echo "N/A")
                local state=$(virsh domstate "$vm")
                printf "%-20s %-10s %-10s %-15s\n" "$vm" "$cpu_time" "$memory" "$state"
            fi
        done
    fi
}

# Enhanced VM start with validation
start_vm() {
    local vm_name="$1"
    [[ -z "$vm_name" ]] && error_exit "VM name required"
    
    validate_vm_name "$vm_name"
    
    if ! vm_exists "$vm_name"; then
        error_exit "VM '$vm_name' does not exist"
    fi
    
    if vm_is_running "$vm_name"; then
        print_warning "VM '$vm_name' is already running"
        return 0
    fi
    
    print_info "Starting VM: $vm_name"
    if virsh start "$vm_name"; then
        print_success "VM '$vm_name' started successfully"
        
        # Wait for VM to be fully started
        local timeout=30
        while [[ $timeout -gt 0 ]] && ! vm_is_running "$vm_name"; do
            sleep 1
            ((timeout--))
        done
        
        if vm_is_running "$vm_name"; then
            print_success "VM '$vm_name' is now running"
        else
            print_warning "VM '$vm_name' may still be starting up"
        fi
    else
        error_exit "Failed to start VM '$vm_name'"
    fi
}

# Enhanced VM stop with graceful shutdown
stop_vm() {
    local vm_name="$1"
    local timeout="${2:-60}"  # Default 60 seconds timeout
    
    [[ -z "$vm_name" ]] && error_exit "VM name required"
    
    validate_vm_name "$vm_name"
    
    if ! vm_exists "$vm_name"; then
        error_exit "VM '$vm_name' does not exist"
    fi
    
    if ! vm_is_running "$vm_name"; then
        print_warning "VM '$vm_name' is not running"
        return 0
    fi
    
    print_info "Gracefully shutting down VM: $vm_name (timeout: ${timeout}s)"
    
    if virsh shutdown "$vm_name"; then
        # Wait for graceful shutdown
        local elapsed=0
        while [[ $elapsed -lt $timeout ]] && vm_is_running "$vm_name"; do
            sleep 2
            ((elapsed += 2))
            if [[ $((elapsed % 10)) -eq 0 ]]; then
                print_info "Waiting for shutdown... ${elapsed}s elapsed"
            fi
        done
        
        if vm_is_running "$vm_name"; then
            print_warning "Graceful shutdown timed out. Use 'force-stop' to force shutdown."
            return 1
        else
            print_success "VM '$vm_name' shut down successfully"
        fi
    else
        error_exit "Failed to initiate shutdown for VM '$vm_name'"
    fi
}

# Enhanced force stop
force_stop_vm() {
    local vm_name="$1"
    [[ -z "$vm_name" ]] && error_exit "VM name required"
    
    validate_vm_name "$vm_name"
    
    if ! vm_exists "$vm_name"; then
        error_exit "VM '$vm_name' does not exist"
    fi
    
    if ! vm_is_running "$vm_name"; then
        print_warning "VM '$vm_name' is not running"
        return 0
    fi
    
    print_warning "Force stopping VM: $vm_name"
    read -p "Are you sure? This may cause data loss. [y/N]: " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Operation cancelled"
        return 0
    fi
    
    if virsh destroy "$vm_name"; then
        print_success "VM '$vm_name' force stopped"
    else
        error_exit "Failed to force stop VM '$vm_name'"
    fi
}

# Enhanced VM deletion with backup option
delete_vm() {
    local vm_name="$1"
    local backup="${2:-false}"
    
    [[ -z "$vm_name" ]] && error_exit "VM name required"
    
    validate_vm_name "$vm_name"
    
    if ! vm_exists "$vm_name"; then
        error_exit "VM '$vm_name' does not exist"
    fi
    
    print_warning "This will permanently delete VM: $vm_name"
    
    # Show what will be deleted
    print_info "VM configuration and the following storage will be removed:"
    local storage_files=($(virsh domblklist "$vm_name" 2>/dev/null | grep -v "^$\|Target\|Source\|^-" | awk '{print $2}' | grep -v "^$"))
    for file in "${storage_files[@]}"; do
        if [[ -n "$file" && "$file" != "-" ]]; then
            echo "  - $file"
        fi
    done
    
    read -p "Continue with deletion? [y/N]: " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Deletion cancelled"
        return 0
    fi
    
    # Stop VM if running
    if vm_is_running "$vm_name"; then
        print_info "Stopping VM before deletion..."
        virsh destroy "$vm_name" || print_warning "Failed to stop VM, continuing with deletion"
    fi
    
    # Create backup if requested
    if [[ "$backup" == "true" ]]; then
        local backup_dir="${HOME}/vm-backups/$(date +%Y%m%d_%H%M%S)_${vm_name}"
        mkdir -p "$backup_dir"
        print_info "Creating backup in: $backup_dir"
        
        # Backup VM configuration
        virsh dumpxml "$vm_name" > "$backup_dir/${vm_name}.xml"
        
        # Note: Actual disk backup would require significant time and space
        print_info "VM configuration backed up. Disk images not backed up due to size."
    fi
    
    # Delete the VM
    if virsh undefine "$vm_name" --remove-all-storage 2>/dev/null; then
        print_success "VM '$vm_name' deleted successfully"
    else
        # Fallback: try without removing storage
        if virsh undefine "$vm_name"; then
            print_success "VM '$vm_name' undefined. Manual storage cleanup may be required."
        else
            error_exit "Failed to delete VM '$vm_name'"
        fi
    fi
}

# Enhanced VM info with more details
vm_info() {
    local vm_name="$1"
    [[ -z "$vm_name" ]] && error_exit "VM name required"
    
    validate_vm_name "$vm_name"
    
    if ! vm_exists "$vm_name"; then
        error_exit "VM '$vm_name' does not exist"
    fi
    
    print_info "Detailed information for VM: $vm_name"
    echo
    
    # Basic info
    virsh dominfo "$vm_name"
    echo
    
    # Network interfaces
    print_info "Network interfaces:"
    virsh domiflist "$vm_name"
    echo
    
    # Storage devices
    print_info "Storage devices:"
    virsh domblklist "$vm_name"
    echo
    
    # If VM is running, show additional runtime info
    if vm_is_running "$vm_name"; then
        print_info "Runtime information:"
        echo
        
        # Network addresses
        print_info "Network addresses:"
        virsh domifaddr "$vm_name" 2>/dev/null || echo "  Unable to retrieve network addresses"
        echo
        
        # CPU stats
        print_info "CPU statistics:"
        virsh cpu-stats "$vm_name" --total 2>/dev/null || echo "  Unable to retrieve CPU stats"
        echo
    fi
}

# Enhanced console connection
vm_console() {
    local vm_name="$1"
    [[ -z "$vm_name" ]] && error_exit "VM name required"
    
    validate_vm_name "$vm_name"
    
    if ! vm_exists "$vm_name"; then
        error_exit "VM '$vm_name' does not exist"
    fi
    
    if ! vm_is_running "$vm_name"; then
        error_exit "VM '$vm_name' is not running"
    fi
    
    print_info "Connecting to console of VM: $vm_name"
    print_warning "To exit the console, press Ctrl+] or Ctrl+5"
    print_info "Starting console session..."
    
    virsh console "$vm_name"
}

# Enhanced VM creation from ISO with better validation
create_vm_from_iso() {
    local name="$1"
    local ram="$2"
    local vcpus="$3"
    local iso="$4"
    local disk_size="${5:-20}"
    local os_variant="${6:-generic}"
    
    # Validate parameters
    [[ -z "$name" || -z "$ram" || -z "$vcpus" || -z "$iso" ]] && {
        error_exit "Missing required parameters. Usage: create_vm_from_iso <name> <ram_mb> <vcpus> <iso_path> [disk_size_gb] [os_variant]"
    }
    
    validate_vm_name "$name"
    validate_number "$ram" "RAM"
    validate_number "$vcpus" "vCPUs"
    validate_number "$disk_size" "Disk size"
    validate_file_exists "$iso" "ISO file"
    
    # Check if VM already exists
    if vm_exists "$name"; then
        error_exit "VM '$name' already exists"
    fi
    
    # Validate minimum requirements
    [[ $ram -lt 512 ]] && print_warning "RAM less than 512MB may cause issues"
    [[ $vcpus -lt 1 ]] && error_exit "At least 1 vCPU required"
    [[ $disk_size -lt 5 ]] && print_warning "Disk size less than 5GB may be insufficient"
    
    print_info "Creating VM: $name"
    print_info "Specifications:"
    print_info "  RAM: ${ram}MB"
    print_info "  vCPUs: $vcpus"
    print_info "  Disk: ${disk_size}GB"
    print_info "  ISO: $iso"
    print_info "  OS Variant: $os_variant"
    
    if virt-install \
        --name "$name" \
        --ram "$ram" \
        --vcpus "$vcpus" \
        --disk size="$disk_size",format=qcow2 \
        --cdrom "$iso" \
        --os-variant "$os_variant" \
        --network network="$DEFAULT_NETWORK" \
        --graphics vnc,listen=0.0.0.0 \
        --noautoconsole; then
        print_success "VM '$name' created and installation started"
        print_info "Connect with VNC viewer or use: $SCRIPT_NAME console $name"
    else
        error_exit "Failed to create VM '$name'"
    fi
}

# Show system resource usage
show_system_resources() {
    print_info "System resource usage:"
    echo
    
    # CPU info
    print_info "CPU Information:"
    lscpu | grep -E "CPU\(s\)|Thread|Core|Socket" || echo "CPU info not available"
    echo
    
    # Memory info
    print_info "Memory Usage:"
    free -h
    echo
    
    # Storage info for libvirt
    print_info "Libvirt Storage Usage:"
    virsh pool-list --all
    echo
    
    # Running VMs resource usage
    local running_vms=($(virsh list --name 2>/dev/null))
    if [[ ${#running_vms[@]} -gt 0 ]] && [[ -n "${running_vms[0]}" ]]; then
        print_info "VM Resource Allocation:"
        for vm in "${running_vms[@]}"; do
            if [[ -n "$vm" ]]; then
                local vm_ram=$(virsh dominfo "$vm" | grep "Max memory" | awk '{print $3 " " $4}')
                local vm_vcpus=$(virsh dominfo "$vm" | grep "CPU(s)" | awk '{print $2}')
                echo "  $vm: ${vm_vcpus} vCPUs, ${vm_ram}"
            fi
        done
    fi
}

# List OS variants
list_os_variants() {
    print_info "Available OS variants for virt-install:"
    if command -v osinfo-query &>/dev/null; then
        osinfo-query os | head -20
        echo
        print_info "Use 'osinfo-query os' for complete list"
    else
        print_warning "osinfo-db-tools not installed. Using generic variants:"
        echo "  generic, linux2020, win10, win2k19, ubuntu20.04, centos8, debian10"
        print_info "Install osinfo-db-tools for complete OS variant list"
    fi
}

# Enhanced help with examples
show_help() {
    echo -e "${GREEN}Enhanced QEMU/Libvirt Management Script v${SCRIPT_VERSION}${NC}"
    echo -e "${YELLOW}Usage: $SCRIPT_NAME <command> [arguments]${NC}"
    echo
    echo -e "${BLUE}VM Management:${NC}"
    echo "  list                           - List all VMs with summary"
    echo "  running                        - List running VMs with resource usage"
    echo "  start <vm_name>                - Start a VM"
    echo "  stop <vm_name> [timeout]       - Stop a VM gracefully (default 60s timeout)"
    echo "  force-stop <vm_name>           - Force stop a VM"
    echo "  delete <vm_name> [backup]      - Delete a VM (backup=true to save config)"
    echo "  info <vm_name>                 - Show detailed VM information"
    echo "  console <vm_name>              - Connect to VM console"
    echo "  network <vm_name>              - Show VM network information"
    echo
    echo -e "${BLUE}VM Creation:${NC}"
    echo "  create-iso <name> <ram_mb> <vcpus> <iso_path> [disk_size_gb] [os_variant]"
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
    echo "  disk-create <path> <size_gb> <format>"
    echo "                                 - Create a disk image"
    echo "  disk-info <path>               - Show disk image info"
    echo "  disk-convert <input> <output> <format>"
    echo "                                 - Convert disk image format"
    echo "  disk-resize <path> <new_size_gb>"
    echo "                                 - Resize a disk image"
    echo
    echo -e "${BLUE}System Information:${NC}"
    echo "  status                         - Show libvirt service status"
    echo "  resources                      - Show system resource usage"
    echo "  os-variants                    - List available OS variants"
    echo "  check                          - Check dependencies and permissions"
    echo "  version                        - Show script version"
    echo "  help                           - Show this help message"
    echo
    echo -e "${BLUE}Examples:${NC}"
    echo "  $SCRIPT_NAME create-iso myvm 2048 2 /path/to/ubuntu.iso 25 ubuntu20.04"
    echo "  $SCRIPT_NAME stop myvm 120    # Stop with 120s timeout"
    echo "  $SCRIPT_NAME delete myvm true # Delete with config backup"
    echo
    echo -e "${BLUE}Logs:${NC} $LOG_FILE"
}

# Show version
show_version() {
    echo -e "${GREEN}QEMU/Libvirt Management Script${NC}"
    echo -e "${BLUE}Version: ${SCRIPT_VERSION}${NC}"
    echo -e "${BLUE}Author: Enhanced by Claude${NC}"
    echo -e "${BLUE}Log file: ${LOG_FILE}${NC}"
}

# Main function with enhanced argument parsing
main() {
    # Initialize logging
    init_logging
    
    # Log script start
    log_info "Script started: $SCRIPT_NAME $*"
    
    # Check if no arguments provided
    if [[ $# -eq 0 ]]; then
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
            stop_vm "$2" "$3"
            ;;
        force-stop)
            force_stop_vm "$2"
            ;;
        delete)
            delete_vm "$2" "$3"
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
        create-iso)
            create_vm_from_iso "$2" "$3" "$4" "$5" "$6" "$7"
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
        status)
            check_service_status
            ;;
        resources)
            show_system_resources
            ;;
        os-variants)
            list_os_variants
            ;;
        check)
            check_dependencies
            ;;
        version|--version|-v)
            show_version
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown command: $1"
            echo
            show_help
            exit 1
            ;;
    esac
    
    # Log script completionw
    log_info "Script completed successfully"
}

# Trap for cleanup on exit
cleanup() {
    log_info "Script execution finished"
}
trap cleanup EXIT

# Run the main function with all arguments
main "$@"