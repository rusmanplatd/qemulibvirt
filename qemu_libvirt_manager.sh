#!/bin/bash
# Enhanced QEMU/Libvirt Management Script with Desktop Features
# This script provides comprehensive functions to manage QEMU/Libvirt virtual machines
set -euo pipefail
IFS=$'\n\t'

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="2.1.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for better output
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Desktop integration paths
readonly DESKTOP_DIR="${HOME}/.local/share/applications"
readonly ICONS_DIR="${HOME}/.local/share/icons"
readonly AUTOSTART_DIR="${HOME}/.config/autostart"

# Logging setup
readonly LOG_DIR="${HOME}/.local/share/qemu-manager"
readonly LOG_FILE="${LOG_DIR}/qemu-manager.log"
readonly MAX_LOG_SIZE=10485760  # 10MB

# Configuration
readonly CONFIG_FILE="${HOME}/.config/qemu-manager/config"
readonly DESKTOP_CONFIG_FILE="${HOME}/.config/qemu-manager/desktop-config"
readonly DEFAULT_STORAGE_POOL="default"
readonly DEFAULT_NETWORK="default"

# Desktop notification function
notify_desktop() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"  # low, normal, critical
    local icon="${4:-computer}"
    
    if command -v notify-send &>/dev/null; then
        notify-send -u "$urgency" -i "$icon" "$title" "$message"
    fi
    
    # Also log the notification
    log_info "NOTIFICATION: $title - $message"
}

# Enhanced GUI VM viewer with better detection
vm_viewer() {
    local vm_name="$1"
    local viewer_type="${2:-auto}"  # auto, vnc, spice, virt-viewer
    
    [[ -z "$vm_name" ]] && error_exit "VM name required"
    
    validate_vm_name "$vm_name"
    
    if ! vm_exists "$vm_name"; then
        error_exit "VM '$vm_name' does not exist"
    fi
    
    if ! vm_is_running "$vm_name"; then
        print_warning "VM '$vm_name' is not running. Starting VM..."
        start_vm "$vm_name"
        sleep 3  # Give VM time to start
    fi
    
    print_info "Opening GUI viewer for VM: $vm_name"
    
    case "$viewer_type" in
        auto)
            # Try different viewers in order of preference
            if command -v virt-viewer &>/dev/null; then
                print_info "Using virt-viewer..."
                virt-viewer "$vm_name" &
            elif command -v virt-manager &>/dev/null; then
                print_info "Using virt-manager..."
                virt-manager --connect qemu:///system --show-domain-console "$vm_name" &
            elif command -v vinagre &>/dev/null; then
                # Get VNC port
                local vnc_port=$(virsh vncdisplay "$vm_name" 2>/dev/null | cut -d: -f2)
                if [[ -n "$vnc_port" ]]; then
                    print_info "Using vinagre with VNC..."
                    vinagre "localhost:$((5900 + vnc_port))" &
                fi
            else
                print_error "No GUI viewer found. Install virt-viewer, virt-manager, or vinagre"
                return 1
            fi
            ;;
        virt-viewer)
            command -v virt-viewer &>/dev/null || error_exit "virt-viewer not installed"
            virt-viewer "$vm_name" &
            ;;
        vnc)
            local vnc_port=$(virsh vncdisplay "$vm_name" 2>/dev/null | cut -d: -f2)
            [[ -z "$vnc_port" ]] && error_exit "VM does not have VNC enabled"
            
            if command -v vinagre &>/dev/null; then
                vinagre "localhost:$((5900 + vnc_port))" &
            elif command -v vncviewer &>/dev/null; then
                vncviewer "localhost:$((5900 + vnc_port))" &
            else
                print_error "No VNC viewer found. Install vinagre or vncviewer"
                print_info "VNC available at: localhost:$((5900 + vnc_port))"
            fi
            ;;
        spice)
            if command -v spicy &>/dev/null; then
                local spice_port=$(virsh domdisplay "$vm_name" 2>/dev/null | grep spice | cut -d: -f3)
                [[ -n "$spice_port" ]] && spicy -h localhost -p "$spice_port" &
            else
                print_error "spicy (SPICE client) not installed"
            fi
            ;;
        virt-manager)
            command -v virt-manager &>/dev/null || error_exit "virt-manager not installed"
            virt-manager --connect qemu:///system --show-domain-console "$vm_name" &
            ;;
    esac
    
    notify_desktop "VM Viewer" "Opening viewer for VM: $vm_name" "normal" "computer"
}

# Create desktop shortcut for VM
create_vm_desktop_shortcut() {
    local vm_name="$1"
    local icon_name="${2:-computer}"
    
    [[ -z "$vm_name" ]] && error_exit "VM name required"
    
    validate_vm_name "$vm_name"
    
    if ! vm_exists "$vm_name"; then
        error_exit "VM '$vm_name' does not exist"
    fi
    
    mkdir -p "$DESKTOP_DIR"
    
    local desktop_file="${DESKTOP_DIR}/vm-${vm_name}.desktop"
    local script_path="$(readlink -f "$0")"
    
    cat > "$desktop_file" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=VM: $vm_name
Comment=Start and connect to virtual machine $vm_name
Exec=$script_path quick-start $vm_name
Icon=$icon_name
Terminal=false
Categories=System;Virtualization;
StartupNotify=true
Keywords=VM;Virtual;Machine;QEMU;KVM;
Actions=Start;Stop;View;Info;

[Desktop Action Start]
Name=Start VM
Exec=$script_path start $vm_name

[Desktop Action Stop]
Name=Stop VM
Exec=$script_path stop $vm_name

[Desktop Action View]
Name=Open Viewer
Exec=$script_path viewer $vm_name

[Desktop Action Info]
Name=VM Information
Exec=$script_path gui-info $vm_name
EOF
    
    chmod +x "$desktop_file"
    
    print_success "Desktop shortcut created: $desktop_file"
    notify_desktop "Desktop Shortcut" "Created shortcut for VM: $vm_name" "normal" "$icon_name"
}

# Quick start VM with viewer
quick_start_vm() {
    local vm_name="$1"
    
    [[ -z "$vm_name" ]] && error_exit "VM name required"
    
    if ! vm_is_running "$vm_name"; then
        print_info "Starting VM: $vm_name"
        start_vm "$vm_name"
        
        # Wait a bit for VM to fully start
        sleep 5
        
        notify_desktop "VM Started" "Virtual machine $vm_name is now running" "normal" "computer"
    else
        print_info "VM '$vm_name' is already running"
    fi
    
    # Open viewer
    print_info "Opening viewer..."
    vm_viewer "$vm_name"
}

# GUI VM information dialog
gui_vm_info() {
    local vm_name="$1"
    
    [[ -z "$vm_name" ]] && error_exit "VM name required"
    
    if ! vm_exists "$vm_name"; then
        error_exit "VM '$vm_name' does not exist"
    fi
    
    # Create temporary info file
    local temp_file=$(mktemp)
    
    {
        echo "Virtual Machine Information: $vm_name"
        echo "=" | tr ' ' '='
        echo
        virsh dominfo "$vm_name"
        echo
        echo "Network Interfaces:"
        echo "-" | tr ' ' '-'
        virsh domiflist "$vm_name"
        echo
        echo "Storage Devices:"
        echo "-" | tr ' ' '-'
        virsh domblklist "$vm_name"
        
        if vm_is_running "$vm_name"; then
            echo
            echo "Runtime Information:"
            echo "-" | tr ' ' '-'
            virsh domifaddr "$vm_name" 2>/dev/null || echo "Network addresses not available"
        fi
    } > "$temp_file"
    
    # Try different GUI text viewers
    if command -v zenity &>/dev/null; then
        zenity --text-info --title="VM Info: $vm_name" --filename="$temp_file" --width=600 --height=400
    elif command -v kdialog &>/dev/null; then
        kdialog --textbox "$temp_file" 600 400 --title "VM Info: $vm_name"
    elif command -v yad &>/dev/null; then
        yad --text-info --title="VM Info: $vm_name" --filename="$temp_file" --width=600 --height=400
    elif [[ -n "$DISPLAY" ]] && command -v xterm &>/dev/null; then
        xterm -title "VM Info: $vm_name" -e "cat $temp_file; read -p 'Press Enter to close...'"
    else
        # Fallback to terminal
        cat "$temp_file"
    fi
    
    rm -f "$temp_file"
}

# System tray integration (basic notification)
tray_notification() {
    local message="$1"
    local urgency="${2:-normal}"
    
    notify_desktop "QEMU Manager" "$message" "$urgency" "computer"
}

# Enhanced VM monitoring with desktop notifications
monitor_vm() {
    local vm_name="$1"
    local interval="${2:-30}"  # Check every 30 seconds
    
    [[ -z "$vm_name" ]] && error_exit "VM name required"
    
    validate_vm_name "$vm_name"
    
    if ! vm_exists "$vm_name"; then
        error_exit "VM '$vm_name' does not exist"
    fi
    
    print_info "Starting monitoring for VM: $vm_name (interval: ${interval}s)"
    print_info "Press Ctrl+C to stop monitoring"
    
    local last_state=""
    local start_time=$(date +%s)
    
    while true; do
        local current_state=$(virsh domstate "$vm_name" 2>/dev/null || echo "unknown")
        local current_time=$(date +%s)
        local uptime=$((current_time - start_time))
        
        if [[ "$current_state" != "$last_state" ]]; then
            case "$current_state" in
                "running")
                    notify_desktop "VM Status" "VM $vm_name is now running" "normal" "computer"
                    print_success "VM $vm_name changed state: $current_state"
                    ;;
                "shut off")
                    notify_desktop "VM Status" "VM $vm_name has stopped" "normal" "computer"
                    print_warning "VM $vm_name changed state: $current_state"
                    ;;
                "paused")
                    notify_desktop "VM Status" "VM $vm_name is paused" "low" "computer"
                    print_info "VM $vm_name changed state: $current_state"
                    ;;
                *)
                    notify_desktop "VM Status" "VM $vm_name state: $current_state" "low" "computer"
                    print_info "VM $vm_name changed state: $current_state"
                    ;;
            esac
            last_state="$current_state"
        fi
        
        # Show periodic status
        if [[ $((uptime % 300)) -eq 0 ]] && [[ $uptime -gt 0 ]]; then  # Every 5 minutes
            print_info "Monitoring $vm_name for $((uptime / 60)) minutes. Current state: $current_state"
        fi
        
        sleep "$interval"
    done
}

# Auto-start VM on login
setup_vm_autostart() {
    local vm_name="$1"
    local action="${2:-enable}"  # enable/disable
    
    [[ -z "$vm_name" ]] && error_exit "VM name required"
    
    validate_vm_name "$vm_name"
    
    if ! vm_exists "$vm_name"; then
        error_exit "VM '$vm_name' does not exist"
    fi
    
    mkdir -p "$AUTOSTART_DIR"
    
    local autostart_file="${AUTOSTART_DIR}/vm-${vm_name}-autostart.desktop"
    local script_path="$(readlink -f "$0")"
    
    case "$action" in
        enable)
            cat > "$autostart_file" << EOF
[Desktop Entry]
Type=Application
Name=VM Autostart: $vm_name
Comment=Automatically start virtual machine $vm_name on login
Exec=$script_path start $vm_name
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
X-KDE-autostart-after=panel
Categories=System;
EOF
            chmod +x "$autostart_file"
            print_success "Autostart enabled for VM: $vm_name"
            notify_desktop "VM Autostart" "Enabled autostart for VM: $vm_name" "normal" "computer"
            ;;
        disable)
            if [[ -f "$autostart_file" ]]; then
                rm -f "$autostart_file"
                print_success "Autostart disabled for VM: $vm_name"
                notify_desktop "VM Autostart" "Disabled autostart for VM: $vm_name" "normal" "computer"
            else
                print_warning "Autostart was not configured for VM: $vm_name"
            fi
            ;;
        *)
            error_exit "Invalid action. Use 'enable' or 'disable'"
            ;;
    esac
}

# Interactive VM manager (basic TUI)
interactive_manager() {
    print_info "Interactive VM Manager"
    echo
    
    while true; do
        echo -e "${BLUE}=== QEMU/Libvirt Interactive Manager ===${NC}"
        echo
        echo "1) List all VMs"
        echo "2) List running VMs"
        echo "3) Start a VM"
        echo "4) Stop a VM"
        echo "5) Create VM from ISO"
        echo "6) Open VM viewer"
        echo "7) VM information"
        echo "8) Create desktop shortcut"
        echo "9) System resources"
        echo "0) Exit"
        echo
        read -p "Choose an option [0-9]: " choice
        echo
        
        case "$choice" in
            1) list_vms ;;
            2) list_running_vms ;;
            3) 
                read -p "Enter VM name to start: " vm_name
                [[ -n "$vm_name" ]] && start_vm "$vm_name"
                ;;
            4)
                read -p "Enter VM name to stop: " vm_name
                [[ -n "$vm_name" ]] && stop_vm "$vm_name"
                ;;
            5)
                echo "Create VM from ISO:"
                read -p "VM name: " name
                read -p "RAM (MB): " ram
                read -p "vCPUs: " vcpus
                read -p "ISO path: " iso
                read -p "Disk size (GB) [20]: " disk_size
                disk_size=${disk_size:-20}
                read -p "OS variant [generic]: " os_variant
                os_variant=${os_variant:-generic}
                
                if [[ -n "$name" && -n "$ram" && -n "$vcpus" && -n "$iso" ]]; then
                    create_vm_from_iso "$name" "$ram" "$vcpus" "$iso" "$disk_size" "$os_variant"
                fi
                ;;
            6)
                read -p "Enter VM name for viewer: " vm_name
                [[ -n "$vm_name" ]] && vm_viewer "$vm_name"
                ;;
            7)
                read -p "Enter VM name for info: " vm_name
                [[ -n "$vm_name" ]] && vm_info "$vm_name"
                ;;
            8)
                read -p "Enter VM name for desktop shortcut: " vm_name
                [[ -n "$vm_name" ]] && create_vm_desktop_shortcut "$vm_name"
                ;;
            9) show_system_resources ;;
            0) 
                print_info "Goodbye!"
                exit 0
                ;;
            *)
                print_warning "Invalid option. Please choose 0-9."
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
        clear
    done
}

# Install desktop integration files
install_desktop_integration() {
    print_info "Installing desktop integration..."
    
    # Create directories
    mkdir -p "$DESKTOP_DIR" "$ICONS_DIR" "$AUTOSTART_DIR"
    mkdir -p "${HOME}/.config/qemu-manager"
    
    # Create main application desktop file
    local main_desktop_file="${DESKTOP_DIR}/qemu-manager.desktop"
    local script_path="$(readlink -f "$0")"
    
    cat > "$main_desktop_file" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=QEMU Manager
Comment=Manage QEMU/KVM virtual machines
Exec=$script_path interactive
Icon=computer
Terminal=false
Categories=System;Virtualization;
StartupNotify=true
Keywords=VM;Virtual;Machine;QEMU;KVM;Virtualization;
Actions=List;Create;Resources;

[Desktop Action List]
Name=List VMs
Exec=$script_path list

[Desktop Action Create]
Name=Create VM
Exec=$script_path interactive

[Desktop Action Resources]
Name=System Resources
Exec=$script_path resources
EOF
    
    chmod +x "$main_desktop_file"
    
    # Create config file with default settings
    if [[ ! -f "$DESKTOP_CONFIG_FILE" ]]; then
        cat > "$DESKTOP_CONFIG_FILE" << EOF
# QEMU Manager Desktop Configuration
DEFAULT_VIEWER=auto
NOTIFICATION_LEVEL=normal
AUTO_OPEN_VIEWER=true
MONITOR_INTERVAL=30
EOF
    fi
    
    print_success "Desktop integration installed successfully"
    print_info "Main application: Applications → System → QEMU Manager"
    notify_desktop "Installation Complete" "Desktop integration installed for QEMU Manager" "normal" "computer"
}

# Remove desktop integration
uninstall_desktop_integration() {
    print_warning "Removing desktop integration..."
    
    # Remove main desktop file
    rm -f "${DESKTOP_DIR}/qemu-manager.desktop"
    
    # Remove VM-specific desktop files
    rm -f "${DESKTOP_DIR}/vm-"*.desktop
    
    # Remove autostart files
    rm -f "${AUTOSTART_DIR}/vm-"*-autostart.desktop
    
    print_success "Desktop integration removed"
    notify_desktop "Uninstallation Complete" "Desktop integration removed for QEMU Manager" "normal" "computer"
}

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
    notify_desktop "Error" "$*" "critical" "dialog-error"
    exit 1
}

# [Keep all original functions: validate_vm_name, vm_exists, vm_is_running, etc.]
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
    # Optional dependencies (including desktop tools)
    local optional_cmds=(virt-viewer virt-clone virt-manager notify-send zenity vinagre)
    
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
        print_info "Ubuntu/Debian: sudo apt-get install bridge-utils virtinst virt-manager virt-viewer libnotify-bin zenity vinagre"
    fi
    
    check_permissions
    print_success "All required dependencies are installed"
}

# [Keep all other original functions like check_service_status, list_vms, start_vm, etc.]
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

# Enhanced VM start with validation and notifications
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
        notify_desktop "VM Started" "Virtual machine $vm_name is starting up" "normal" "computer"
        
        # Wait for VM to be fully started
        local timeout=30
        while [[ $timeout -gt 0 ]] && ! vm_is_running "$vm_name"; do
            sleep 1
            ((timeout--))
        done
        
        if vm_is_running "$vm_name"; then
            print_success "VM '$vm_name' is now running"
            notify_desktop "VM Ready" "Virtual machine $vm_name is now running" "normal" "computer"
        else
            print_warning "VM '$vm_name' may still be starting up"
        fi
    else
        error_exit "Failed to start VM '$vm_name'"
    fi
}

# Enhanced VM stop with graceful shutdown and notifications
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
    notify_desktop "VM Stopping" "Shutting down virtual machine $vm_name" "normal" "computer"
    
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
            notify_desktop "VM Shutdown" "Shutdown timeout for $vm_name" "critical" "computer"
            return 1
        else
            print_success "VM '$vm_name' shut down successfully"
            notify_desktop "VM Stopped" "Virtual machine $vm_name has shut down" "normal" "computer"
        fi
    else
        error_exit "Failed to initiate shutdown for VM '$vm_name'"
    fi
}

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
    
    notify_desktop "VM Creation" "Creating virtual machine $name" "normal" "computer"
    
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
        notify_desktop "VM Created" "Virtual machine $name created successfully" "normal" "computer"
        
        # Ask if user wants to create desktop shortcut
        if [[ -n "$DISPLAY" ]]; then
            read -p "Create desktop shortcut for this VM? [y/N]: " -r
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                create_vm_desktop_shortcut "$name"
            fi
        fi
    else
        error_exit "Failed to create VM '$name'"
    fi
}

# Force stop VM with confirmation
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
        notify_desktop "VM Force Stopped" "Virtual machine $vm_name was force stopped" "critical" "computer"
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
    
    # Remove desktop shortcut and autostart if they exist
    local desktop_file="${DESKTOP_DIR}/vm-${vm_name}.desktop"
    local autostart_file="${AUTOSTART_DIR}/vm-${vm_name}-autostart.desktop"
    
    [[ -f "$desktop_file" ]] && rm -f "$desktop_file" && print_info "Removed desktop shortcut"
    [[ -f "$autostart_file" ]] && rm -f "$autostart_file" && print_info "Removed autostart entry"
    
    # Delete the VM
    if virsh undefine "$vm_name" --remove-all-storage 2>/dev/null; then
        print_success "VM '$vm_name' deleted successfully"
        notify_desktop "VM Deleted" "Virtual machine $vm_name has been deleted" "normal" "computer"
    else
        # Fallback: try without removing storage
        if virsh undefine "$vm_name"; then
            print_success "VM '$vm_name' undefined. Manual storage cleanup may be required."
            notify_desktop "VM Deleted" "Virtual machine $vm_name undefined (manual cleanup needed)" "normal" "computer"
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

# Enhanced help with desktop features
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
    echo
    echo -e "${BLUE}Desktop Features:${NC}"
    echo "  viewer <vm_name> [type]        - Open GUI viewer (auto/vnc/spice/virt-viewer)"
    echo "  quick-start <vm_name>          - Start VM and open viewer"
    echo "  gui-info <vm_name>             - Show VM info in GUI dialog"
    echo "  desktop-shortcut <vm_name> [icon] - Create desktop shortcut for VM"
    echo "  autostart <vm_name> <enable|disable> - Setup VM autostart on login"
    echo "  monitor <vm_name> [interval]   - Monitor VM with desktop notifications"
    echo "  interactive                    - Launch interactive text-based manager"
    echo
    echo -e "${BLUE}Desktop Integration:${NC}"
    echo "  install-desktop                - Install desktop integration files"
    echo "  uninstall-desktop              - Remove desktop integration files"
    echo
    echo -e "${BLUE}VM Creation:${NC}"
    echo "  create-iso <name> <ram_mb> <vcpus> <iso_path> [disk_size_gb] [os_variant]"
    echo "                                 - Create a VM from ISO"
    echo
    echo -e "${BLUE}System Information:${NC}"
    echo "  status                         - Show libvirt service status"
    echo "  resources                      - Show system resource usage"
    echo "  os-variants                    - List available OS variants"
    echo "  check                          - Check dependencies and permissions"
    echo "  version                        - Show script version"
    echo "  help                           - Show this help message"
    echo
    echo -e "${BLUE}Desktop Examples:${NC}"
    echo "  $SCRIPT_NAME quick-start myvm     # Start VM and open viewer"
    echo "  $SCRIPT_NAME viewer myvm vnc      # Open VNC viewer for VM"
    echo "  $SCRIPT_NAME desktop-shortcut myvm computer # Create desktop shortcut"
    echo "  $SCRIPT_NAME autostart myvm enable # Enable VM autostart"
    echo "  $SCRIPT_NAME monitor myvm 60      # Monitor VM every 60 seconds"
    echo
    echo -e "${BLUE}Installation:${NC}"
    echo "  $SCRIPT_NAME install-desktop      # Install desktop integration"
    echo "  $SCRIPT_NAME interactive          # Launch GUI-like interface"
    echo
    echo -e "${BLUE}Logs:${NC} $LOG_FILE"
    echo -e "${BLUE}Desktop Files:${NC} $DESKTOP_DIR"
}

# Show version
show_version() {
    echo -e "${GREEN}QEMU/Libvirt Management Script${NC}"
    echo -e "${BLUE}Version: ${SCRIPT_VERSION}${NC}"
    echo -e "${BLUE}Author: Enhanced with Desktop Features${NC}"
    echo -e "${BLUE}Log file: ${LOG_FILE}${NC}"
    echo -e "${BLUE}Desktop integration: ${DESKTOP_DIR}${NC}"
}

# Main function with enhanced argument parsing including desktop features
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
        create-iso)
            create_vm_from_iso "$2" "$3" "$4" "$5" "$6" "$7"
            ;;
        
        viewer)
            vm_viewer "$2" "$3"
            ;;
        quick-start)
            quick_start_vm "$2"
            ;;
        gui-info)
            gui_vm_info "$2"
            ;;
        desktop-shortcut)
            create_vm_desktop_shortcut "$2" "$3"
            ;;
        autostart)
            setup_vm_autostart "$2" "$3"
            ;;
        monitor)
            monitor_vm "$2" "$3"
            ;;
        interactive)
            interactive_manager
            ;;
        install-desktop)
            install_desktop_integration
            ;;
        uninstall-desktop)
            uninstall_desktop_integration
            ;;
        
        # System information commands
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
    
    # Log script completion
    log_info "Script completed successfully"
}

# Trap for cleanup on exit
cleanup() {
    log_info "Script execution finished"
}
trap cleanup EXIT

# Run the main function with all arguments
main "$@"