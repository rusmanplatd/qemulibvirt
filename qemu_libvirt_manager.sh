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
readonly CLUSTER_CONFIG_DIR="${HOME}/.config/qemu-manager/clusters"
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
        echo -e "${CYAN}VM Management:${NC}"
        echo "1) List all VMs"
        echo "2) List running VMs"
        echo "3) Start a VM"
        echo "4) Stop a VM"
        echo "5) Create VM from ISO"
        echo "6) Open VM viewer"
        echo "7) VM information"
        echo "8) Create desktop shortcut"
        echo
        echo -e "${CYAN}Cluster Management:${NC}"
        echo "11) List clusters"
        echo "12) Create cluster"
        echo "13) Start cluster"
        echo "14) Stop cluster"
        echo "15) Cluster information"
        echo "16) Add VM to cluster"
        echo "17) Remove VM from cluster"
        echo "18) Delete cluster"
        echo
        echo -e "${CYAN}Advanced Cluster:${NC}"
        echo "21) Cluster dashboard"
        echo "22) Create template"
        echo "23) List templates"
        echo "24) Create from template"
        echo "25) Health check"
        echo "26) Scale cluster"
        echo "27) Backup cluster"
        echo "28) List backups"
        echo
        echo -e "${CYAN}System:${NC}"
        echo "9) System resources"
        echo "0) Exit"
        echo
        read -p "Choose an option [0-28]: " choice
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
            
            # Cluster Management
            11) list_clusters ;;
            12)
                echo "Create new cluster:"
                read -p "Cluster name: " cluster_name
                read -p "Description: " description
                read -p "VM names (space-separated): " vm_names
                if [[ -n "$cluster_name" && -n "$vm_names" ]]; then
                    IFS=' ' read -ra vm_array <<< "$vm_names"
                    create_cluster "$cluster_name" "$description" "${vm_array[@]}"
                fi
                ;;
            13)
                read -p "Enter cluster name to start: " cluster_name
                if [[ -n "$cluster_name" ]]; then
                    read -p "Start in parallel? [y/N]: " parallel
                    [[ $parallel =~ ^[Yy]$ ]] && parallel="true" || parallel="false"
                    start_cluster "$cluster_name" "$parallel"
                fi
                ;;
            14)
                read -p "Enter cluster name to stop: " cluster_name
                if [[ -n "$cluster_name" ]]; then
                    read -p "Timeout (seconds) [60]: " timeout
                    timeout=${timeout:-60}
                    read -p "Stop in parallel? [y/N]: " parallel
                    [[ $parallel =~ ^[Yy]$ ]] && parallel="true" || parallel="false"
                    stop_cluster "$cluster_name" "$timeout" "$parallel"
                fi
                ;;
            15)
                read -p "Enter cluster name for info: " cluster_name
                [[ -n "$cluster_name" ]] && cluster_info "$cluster_name"
                ;;
            16)
                read -p "Cluster name: " cluster_name
                read -p "VM name to add: " vm_name
                if [[ -n "$cluster_name" && -n "$vm_name" ]]; then
                    add_vm_to_cluster "$cluster_name" "$vm_name"
                fi
                ;;
            17)
                read -p "Cluster name: " cluster_name
                read -p "VM name to remove: " vm_name
                if [[ -n "$cluster_name" && -n "$vm_name" ]]; then
                    remove_vm_from_cluster "$cluster_name" "$vm_name"
                fi
                ;;
            18)
                read -p "Enter cluster name to delete: " cluster_name
                if [[ -n "$cluster_name" ]]; then
                    read -p "Also delete all VMs in cluster? [y/N]: " delete_vms
                    [[ $delete_vms =~ ^[Yy]$ ]] && delete_vms="true" || delete_vms="false"
                    delete_cluster "$cluster_name" "$delete_vms"
                fi
                ;;
            
            # Advanced Cluster Management
            21) cluster_dashboard ;;
            22)
                echo "Create cluster template:"
                read -p "Template name: " template_name
                read -p "Description: " description
                read -p "RAM (MB): " ram
                read -p "vCPUs: " vcpus
                read -p "Disk size (GB): " disk_size
                read -p "VM count [3]: " vm_count
                vm_count=${vm_count:-3}
                if [[ -n "$template_name" && -n "$description" && -n "$ram" && -n "$vcpus" && -n "$disk_size" ]]; then
                    create_cluster_template "$template_name" "$description" "$ram" "$vcpus" "$disk_size" "$vm_count"
                fi
                ;;
            23) list_cluster_templates ;;
            24)
                read -p "New cluster name: " cluster_name
                read -p "Template name: " template_name
                if [[ -n "$cluster_name" && -n "$template_name" ]]; then
                    read -p "Create VMs automatically? [y/N]: " create_vms
                    [[ $create_vms =~ ^[Yy]$ ]] && create_vms="true" || create_vms="false"
                    create_cluster_from_template "$cluster_name" "$template_name" "$create_vms"
                fi
                ;;
            25)
                read -p "Cluster name for health check: " cluster_name
                if [[ -n "$cluster_name" ]]; then
                    read -p "Detailed check? [y/N]: " detailed
                    [[ $detailed =~ ^[Yy]$ ]] && detailed="true" || detailed="false"
                    cluster_health_check "$cluster_name" "$detailed"
                fi
                ;;
            26)
                read -p "Cluster name to scale: " cluster_name
                read -p "Action (add/remove): " action
                read -p "Number of VMs: " count
                if [[ -n "$cluster_name" && -n "$action" && -n "$count" ]]; then
                    if [[ "$action" == "add" ]]; then
                        read -p "Create VMs automatically? [y/N]: " create_vms
                        [[ $create_vms =~ ^[Yy]$ ]] && create_vms="true" || create_vms="false"
                    else
                        create_vms="false"
                    fi
                    scale_cluster "$cluster_name" "$action" "$count" "$create_vms"
                fi
                ;;
            27)
                read -p "Cluster name to backup: " cluster_name
                read -p "Backup name (optional): " backup_name
                if [[ -n "$cluster_name" ]]; then
                    backup_cluster "$cluster_name" "$backup_name"
                fi
                ;;
            28)
                read -p "Cluster name (optional, for specific cluster backups): " cluster_name
                list_cluster_backups "$cluster_name"
                ;;
            
            9) show_system_resources ;;
            0) 
                print_info "Goodbye!"
                exit 0
                ;;
            *)
                print_warning "Invalid option. Please choose 0-28."
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
    mkdir -p "${HOME}/.config/qemu-manager" "$CLUSTER_CONFIG_DIR"
    
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

# CLUSTER MANAGEMENT FUNCTIONS

# Initialize cluster configuration directory
init_cluster_config() {
    mkdir -p "$CLUSTER_CONFIG_DIR"
    mkdir -p "${CLUSTER_CONFIG_DIR}/templates"
    mkdir -p "${CLUSTER_CONFIG_DIR}/backups"
}

# Cluster templates directory
readonly CLUSTER_TEMPLATES_DIR="${CLUSTER_CONFIG_DIR}/templates"
readonly CLUSTER_BACKUPS_DIR="${CLUSTER_CONFIG_DIR}/backups"

# Validate cluster name
validate_cluster_name() {
    local cluster_name="$1"
    if [[ ! "$cluster_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error_exit "Invalid cluster name. Use only alphanumeric characters, hyphens, and underscores."
    fi
    if [[ ${#cluster_name} -gt 64 ]]; then
        error_exit "Cluster name too long. Maximum 64 characters allowed."
    fi
}

# Check if cluster exists
cluster_exists() {
    local cluster_name="$1"
    [[ -f "${CLUSTER_CONFIG_DIR}/${cluster_name}.conf" ]]
}

# Get cluster VMs
get_cluster_vms() {
    local cluster_name="$1"
    local cluster_file="${CLUSTER_CONFIG_DIR}/${cluster_name}.conf"
    
    if [[ ! -f "$cluster_file" ]]; then
        return 1
    fi
    
    grep "^VM=" "$cluster_file" | cut -d= -f2 | tr ',' '\n' | grep -v '^$'
}

# Create a new cluster
create_cluster() {
    local cluster_name="$1"
    local description="$2"
    shift 2
    local vms=("$@")
    
    [[ -z "$cluster_name" ]] && error_exit "Cluster name required"
    
    validate_cluster_name "$cluster_name"
    init_cluster_config
    
    if cluster_exists "$cluster_name"; then
        error_exit "Cluster '$cluster_name' already exists"
    fi
    
    # Validate all VMs exist
    for vm in "${vms[@]}"; do
        if [[ -n "$vm" ]]; then
            validate_vm_name "$vm"
            if ! vm_exists "$vm"; then
                error_exit "VM '$vm' does not exist"
            fi
        fi
    done
    
    local cluster_file="${CLUSTER_CONFIG_DIR}/${cluster_name}.conf"
    local vm_list=$(IFS=','; echo "${vms[*]}")
    
    cat > "$cluster_file" << EOF
# Cluster Configuration: $cluster_name
CLUSTER_NAME=$cluster_name
DESCRIPTION=${description:-"Cluster $cluster_name"}
CREATED=$(date '+%Y-%m-%d %H:%M:%S')
VM=${vm_list}
STARTUP_ORDER=sequential
STARTUP_DELAY=5
SHUTDOWN_ORDER=reverse
SHUTDOWN_DELAY=10
AUTO_START=false
EOF
    
    print_success "Cluster '$cluster_name' created with ${#vms[@]} VMs"
    notify_desktop "Cluster Created" "Cluster '$cluster_name' created successfully" "normal" "computer"
    
    log_info "Created cluster: $cluster_name with VMs: ${vm_list}"
}

# Add VM to cluster
add_vm_to_cluster() {
    local cluster_name="$1"
    local vm_name="$2"
    
    [[ -z "$cluster_name" || -z "$vm_name" ]] && error_exit "Cluster name and VM name required"
    
    validate_cluster_name "$cluster_name"
    validate_vm_name "$vm_name"
    
    if ! cluster_exists "$cluster_name"; then
        error_exit "Cluster '$cluster_name' does not exist"
    fi
    
    if ! vm_exists "$vm_name"; then
        error_exit "VM '$vm_name' does not exist"
    fi
    
    local cluster_file="${CLUSTER_CONFIG_DIR}/${cluster_name}.conf"
    local current_vms=$(grep "^VM=" "$cluster_file" | cut -d= -f2)
    
    # Check if VM is already in cluster
    if [[ "$current_vms" == *"$vm_name"* ]]; then
        print_warning "VM '$vm_name' is already in cluster '$cluster_name'"
        return 0
    fi
    
    # Add VM to the list
    local new_vms
    if [[ -n "$current_vms" ]]; then
        new_vms="${current_vms},${vm_name}"
    else
        new_vms="$vm_name"
    fi
    
    # Update cluster configuration
    sed -i "s/^VM=.*/VM=${new_vms}/" "$cluster_file"
    
    print_success "VM '$vm_name' added to cluster '$cluster_name'"
    notify_desktop "VM Added to Cluster" "VM '$vm_name' added to cluster '$cluster_name'" "normal" "computer"
    
    log_info "Added VM $vm_name to cluster: $cluster_name"
}

# Remove VM from cluster
remove_vm_from_cluster() {
    local cluster_name="$1"
    local vm_name="$2"
    
    [[ -z "$cluster_name" || -z "$vm_name" ]] && error_exit "Cluster name and VM name required"
    
    validate_cluster_name "$cluster_name"
    validate_vm_name "$vm_name"
    
    if ! cluster_exists "$cluster_name"; then
        error_exit "Cluster '$cluster_name' does not exist"
    fi
    
    local cluster_file="${CLUSTER_CONFIG_DIR}/${cluster_name}.conf"
    local current_vms=$(grep "^VM=" "$cluster_file" | cut -d= -f2)
    
    # Check if VM is in cluster
    if [[ "$current_vms" != *"$vm_name"* ]]; then
        print_warning "VM '$vm_name' is not in cluster '$cluster_name'"
        return 0
    fi
    
    # Remove VM from the list
    local new_vms=$(echo "$current_vms" | sed "s/,$vm_name//g; s/$vm_name,//g; s/^$vm_name$//g")
    
    # Update cluster configuration
    sed -i "s/^VM=.*/VM=${new_vms}/" "$cluster_file"
    
    print_success "VM '$vm_name' removed from cluster '$cluster_name'"
    notify_desktop "VM Removed from Cluster" "VM '$vm_name' removed from cluster '$cluster_name'" "normal" "computer"
    
    log_info "Removed VM $vm_name from cluster: $cluster_name"
}

# List all clusters
list_clusters() {
    print_info "Available clusters:"
    echo
    
    init_cluster_config
    
    local cluster_count=0
    local running_clusters=0
    
    if [[ ! -d "$CLUSTER_CONFIG_DIR" ]] || [[ -z "$(ls -A "$CLUSTER_CONFIG_DIR" 2>/dev/null)" ]]; then
        print_warning "No clusters found"
        return 0
    fi
    
    printf "%-20s %-15s %-10s %-40s\n" "Cluster Name" "Status" "VMs" "Description"
    echo "---------------------------------------------------------------------------------"
    
    for cluster_file in "$CLUSTER_CONFIG_DIR"/*.conf; do
        if [[ -f "$cluster_file" ]]; then
            local cluster_name=$(basename "$cluster_file" .conf)
            local description=$(grep "^DESCRIPTION=" "$cluster_file" | cut -d= -f2- | tr -d '"')
            local vms=($(get_cluster_vms "$cluster_name"))
            local vm_count=${#vms[@]}
            local running_count=0
            
            # Count running VMs
            for vm in "${vms[@]}"; do
                if [[ -n "$vm" ]] && vm_is_running "$vm"; then
                    ((running_count++))
                fi
            done
            
            local status
            if [[ $running_count -eq $vm_count ]] && [[ $vm_count -gt 0 ]]; then
                status="Running"
                ((running_clusters++))
            elif [[ $running_count -gt 0 ]]; then
                status="Partial"
            else
                status="Stopped"
            fi
            
            printf "%-20s %-15s %-10s %-40s\n" "$cluster_name" "$status" "$running_count/$vm_count" "$description"
            ((cluster_count++))
        fi
    done
    
    echo
    print_info "Summary: $cluster_count total clusters ($running_clusters fully running)"
}

# Show cluster information
cluster_info() {
    local cluster_name="$1"
    
    [[ -z "$cluster_name" ]] && error_exit "Cluster name required"
    
    validate_cluster_name "$cluster_name"
    
    if ! cluster_exists "$cluster_name"; then
        error_exit "Cluster '$cluster_name' does not exist"
    fi
    
    local cluster_file="${CLUSTER_CONFIG_DIR}/${cluster_name}.conf"
    
    print_info "Cluster Information: $cluster_name"
    echo "==============================================="
    echo
    
    # Basic cluster info
    grep -E "^(DESCRIPTION|CREATED|STARTUP_ORDER|STARTUP_DELAY|SHUTDOWN_ORDER|SHUTDOWN_DELAY|AUTO_START)=" "$cluster_file" | while IFS= read -r line; do
        local key=$(echo "$line" | cut -d= -f1)
        local value=$(echo "$line" | cut -d= -f2- | tr -d '"')
        printf "%-15s: %s\n" "$key" "$value"
    done
    
    echo
    print_info "Virtual Machines:"
    echo "-----------------"
    
    local vms=($(get_cluster_vms "$cluster_name"))
    if [[ ${#vms[@]} -eq 0 ]]; then
        echo "  No VMs in cluster"
    else
        printf "%-20s %-10s %-15s\n" "VM Name" "Status" "Memory"
        echo "-----------------------------------------------"
        for vm in "${vms[@]}"; do
            if [[ -n "$vm" ]]; then
                if vm_exists "$vm"; then
                    local status=$(virsh domstate "$vm" 2>/dev/null)
                    local memory=$(virsh dominfo "$vm" 2>/dev/null | grep "Used memory" | awk '{print $3 " " $4}' || echo "N/A")
                    printf "%-20s %-10s %-15s\n" "$vm" "$status" "$memory"
                else
                    printf "%-20s %-10s %-15s\n" "$vm" "NOT FOUND" "N/A"
                fi
            fi
        done
    fi
    
    echo
}

# Start cluster
start_cluster() {
    local cluster_name="$1"
    local parallel="${2:-false}"
    
    [[ -z "$cluster_name" ]] && error_exit "Cluster name required"
    
    validate_cluster_name "$cluster_name"
    
    if ! cluster_exists "$cluster_name"; then
        error_exit "Cluster '$cluster_name' does not exist"
    fi
    
    local cluster_file="${CLUSTER_CONFIG_DIR}/${cluster_name}.conf"
    local startup_order=$(grep "^STARTUP_ORDER=" "$cluster_file" | cut -d= -f2)
    local startup_delay=$(grep "^STARTUP_DELAY=" "$cluster_file" | cut -d= -f2)
    local vms=($(get_cluster_vms "$cluster_name"))
    
    if [[ ${#vms[@]} -eq 0 ]]; then
        print_warning "No VMs in cluster '$cluster_name'"
        return 0
    fi
    
    print_info "Starting cluster: $cluster_name"
    print_info "Startup mode: ${parallel:+parallel}${parallel:-sequential}"
    
    notify_desktop "Cluster Starting" "Starting cluster '$cluster_name'" "normal" "computer"
    
    local started_count=0
    local failed_vms=()
    
    if [[ "$parallel" == "true" ]]; then
        # Start all VMs in parallel
        for vm in "${vms[@]}"; do
            if [[ -n "$vm" ]]; then
                if ! vm_is_running "$vm"; then
                    print_info "Starting VM: $vm"
                    virsh start "$vm" &
                else
                    print_info "VM '$vm' is already running"
                    ((started_count++))
                fi
            fi
        done
        
        # Wait for all background jobs to complete
        wait
        
        # Check which VMs started successfully
        for vm in "${vms[@]}"; do
            if [[ -n "$vm" ]]; then
                if vm_is_running "$vm"; then
                    ((started_count++))
                else
                    failed_vms+=("$vm")
                fi
            fi
        done
    else
        # Sequential startup
        if [[ "$startup_order" == "reverse" ]]; then
            # Reverse the array for reverse startup order
            local reversed_vms=()
            for ((i=${#vms[@]}-1; i>=0; i--)); do
                reversed_vms+=("${vms[i]}")
            done
            vms=("${reversed_vms[@]}")
        fi
        
        for vm in "${vms[@]}"; do
            if [[ -n "$vm" ]]; then
                if ! vm_is_running "$vm"; then
                    print_info "Starting VM: $vm"
                    if virsh start "$vm"; then
                        ((started_count++))
                        print_success "VM '$vm' started"
                        
                        # Wait between startups
                        if [[ $startup_delay -gt 0 ]]; then
                            print_info "Waiting ${startup_delay}s before next startup..."
                            sleep "$startup_delay"
                        fi
                    else
                        failed_vms+=("$vm")
                        print_error "Failed to start VM: $vm"
                    fi
                else
                    print_info "VM '$vm' is already running"
                    ((started_count++))
                fi
            fi
        done
    fi
    
    # Report results
    if [[ ${#failed_vms[@]} -eq 0 ]]; then
        print_success "Cluster '$cluster_name' started successfully ($started_count VMs)"
        notify_desktop "Cluster Started" "Cluster '$cluster_name' started successfully" "normal" "computer"
    else
        print_warning "Cluster '$cluster_name' partially started ($started_count VMs, ${#failed_vms[@]} failed)"
        print_error "Failed VMs: ${failed_vms[*]}"
        notify_desktop "Cluster Partial Start" "Cluster '$cluster_name' partially started" "critical" "computer"
    fi
    
    log_info "Started cluster: $cluster_name, success: $started_count, failed: ${#failed_vms[@]}"
}

# Stop cluster
stop_cluster() {
    local cluster_name="$1"
    local timeout="${2:-60}"
    local parallel="${3:-false}"
    
    [[ -z "$cluster_name" ]] && error_exit "Cluster name required"
    
    validate_cluster_name "$cluster_name"
    
    if ! cluster_exists "$cluster_name"; then
        error_exit "Cluster '$cluster_name' does not exist"
    fi
    
    local cluster_file="${CLUSTER_CONFIG_DIR}/${cluster_name}.conf"
    local shutdown_order=$(grep "^SHUTDOWN_ORDER=" "$cluster_file" | cut -d= -f2)
    local shutdown_delay=$(grep "^SHUTDOWN_DELAY=" "$cluster_file" | cut -d= -f2)
    local vms=($(get_cluster_vms "$cluster_name"))
    
    if [[ ${#vms[@]} -eq 0 ]]; then
        print_warning "No VMs in cluster '$cluster_name'"
        return 0
    fi
    
    print_info "Stopping cluster: $cluster_name"
    print_info "Shutdown mode: ${parallel:+parallel}${parallel:-sequential}"
    
    notify_desktop "Cluster Stopping" "Stopping cluster '$cluster_name'" "normal" "computer"
    
    local stopped_count=0
    local failed_vms=()
    
    if [[ "$parallel" == "true" ]]; then
        # Stop all VMs in parallel
        for vm in "${vms[@]}"; do
            if [[ -n "$vm" ]]; then
                if vm_is_running "$vm"; then
                    print_info "Stopping VM: $vm"
                    virsh shutdown "$vm" &
                else
                    print_info "VM '$vm' is already stopped"
                    ((stopped_count++))
                fi
            fi
        done
        
        # Wait for all shutdowns to complete or timeout
        local elapsed=0
        while [[ $elapsed -lt $timeout ]]; do
            local still_running=0
            for vm in "${vms[@]}"; do
                if [[ -n "$vm" ]] && vm_is_running "$vm"; then
                    ((still_running++))
                fi
            done
            
            if [[ $still_running -eq 0 ]]; then
                break
            fi
            
            sleep 5
            ((elapsed += 5))
            if [[ $((elapsed % 15)) -eq 0 ]]; then
                print_info "Waiting for shutdown... ${elapsed}s elapsed, $still_running VMs still running"
            fi
        done
        
        # Check final state
        for vm in "${vms[@]}"; do
            if [[ -n "$vm" ]]; then
                if ! vm_is_running "$vm"; then
                    ((stopped_count++))
                else
                    failed_vms+=("$vm")
                fi
            fi
        done
    else
        # Sequential shutdown
        if [[ "$shutdown_order" == "reverse" ]]; then
            # Reverse the array for reverse shutdown order
            local reversed_vms=()
            for ((i=${#vms[@]}-1; i>=0; i--)); do
                reversed_vms+=("${vms[i]}")
            done
            vms=("${reversed_vms[@]}")
        fi
        
        for vm in "${vms[@]}"; do
            if [[ -n "$vm" ]]; then
                if vm_is_running "$vm"; then
                    print_info "Stopping VM: $vm"
                    if virsh shutdown "$vm"; then
                        # Wait for VM to stop
                        local vm_timeout=$timeout
                        while [[ $vm_timeout -gt 0 ]] && vm_is_running "$vm"; do
                            sleep 2
                            ((vm_timeout -= 2))
                        done
                        
                        if ! vm_is_running "$vm"; then
                            ((stopped_count++))
                            print_success "VM '$vm' stopped"
                        else
                            failed_vms+=("$vm")
                            print_error "VM '$vm' shutdown timed out"
                        fi
                        
                        # Wait between shutdowns
                        if [[ $shutdown_delay -gt 0 ]]; then
                            print_info "Waiting ${shutdown_delay}s before next shutdown..."
                            sleep "$shutdown_delay"
                        fi
                    else
                        failed_vms+=("$vm")
                        print_error "Failed to initiate shutdown for VM: $vm"
                    fi
                else
                    print_info "VM '$vm' is already stopped"
                    ((stopped_count++))
                fi
            fi
        done
    fi
    
    # Report results
    if [[ ${#failed_vms[@]} -eq 0 ]]; then
        print_success "Cluster '$cluster_name' stopped successfully ($stopped_count VMs)"
        notify_desktop "Cluster Stopped" "Cluster '$cluster_name' stopped successfully" "normal" "computer"
    else
        print_warning "Cluster '$cluster_name' partially stopped ($stopped_count VMs, ${#failed_vms[@]} failed)"
        print_error "Failed VMs (may need force-stop): ${failed_vms[*]}"
        notify_desktop "Cluster Partial Stop" "Cluster '$cluster_name' partially stopped" "critical" "computer"
    fi
    
    log_info "Stopped cluster: $cluster_name, success: $stopped_count, failed: ${#failed_vms[@]}"
}

# Delete cluster
delete_cluster() {
    local cluster_name="$1"
    local delete_vms="${2:-false}"
    
    [[ -z "$cluster_name" ]] && error_exit "Cluster name required"
    
    validate_cluster_name "$cluster_name"
    
    if ! cluster_exists "$cluster_name"; then
        error_exit "Cluster '$cluster_name' does not exist"
    fi
    
    local cluster_file="${CLUSTER_CONFIG_DIR}/${cluster_name}.conf"
    local vms=($(get_cluster_vms "$cluster_name"))
    
    print_warning "This will delete cluster configuration: $cluster_name"
    
    if [[ ${#vms[@]} -gt 0 ]]; then
        print_info "VMs in this cluster:"
        for vm in "${vms[@]}"; do
            if [[ -n "$vm" ]]; then
                echo "  - $vm"
            fi
        done
        
        if [[ "$delete_vms" == "true" ]]; then
            print_warning "WARNING: All VMs in this cluster will also be DELETED!"
        else
            print_info "VMs will be kept and can be managed individually"
        fi
    fi
    
    read -p "Continue with cluster deletion? [y/N]: " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Deletion cancelled"
        return 0
    fi
    
    # Delete VMs if requested
    if [[ "$delete_vms" == "true" ]]; then
        print_info "Deleting VMs in cluster..."
        for vm in "${vms[@]}"; do
            if [[ -n "$vm" ]] && vm_exists "$vm"; then
                print_info "Deleting VM: $vm"
                # Force stop if running
                if vm_is_running "$vm"; then
                    virsh destroy "$vm" 2>/dev/null || true
                fi
                # Delete VM
                virsh undefine "$vm" --remove-all-storage 2>/dev/null || \
                virsh undefine "$vm" 2>/dev/null || \
                print_warning "Failed to delete VM: $vm"
            fi
        done
    fi
    
    # Delete cluster configuration
    if rm -f "$cluster_file"; then
        print_success "Cluster '$cluster_name' deleted successfully"
        notify_desktop "Cluster Deleted" "Cluster '$cluster_name' has been deleted" "normal" "computer"
        log_info "Deleted cluster: $cluster_name, delete_vms: $delete_vms"
    else
        error_exit "Failed to delete cluster configuration file"
    fi
}

# ENHANCED CLUSTER FEATURES

# Create cluster template
create_cluster_template() {
    local template_name="$1"
    local description="$2"
    local ram="$3"
    local vcpus="$4"
    local disk_size="$5"
    local vm_count="${6:-3}"
    local startup_order="${7:-sequential}"
    local startup_delay="${8:-5}"
    local shutdown_order="${9:-reverse}"
    local shutdown_delay="${10:-10}"
    
    [[ -z "$template_name" || -z "$description" || -z "$ram" || -z "$vcpus" || -z "$disk_size" ]] && {
        error_exit "Usage: create-template <name> <description> <ram_mb> <vcpus> <disk_gb> [vm_count] [startup_order] [startup_delay] [shutdown_order] [shutdown_delay]"
    }
    
    validate_cluster_name "$template_name"
    validate_number "$ram" "RAM"
    validate_number "$vcpus" "vCPUs"
    validate_number "$disk_size" "Disk size"
    validate_number "$vm_count" "VM count"
    
    init_cluster_config
    
    local template_file="${CLUSTER_TEMPLATES_DIR}/${template_name}.template"
    
    if [[ -f "$template_file" ]]; then
        error_exit "Template '$template_name' already exists"
    fi
    
    cat > "$template_file" << EOF
# Cluster Template: $template_name
TEMPLATE_NAME=$template_name
DESCRIPTION=$description
CREATED=$(date '+%Y-%m-%d %H:%M:%S')
VM_COUNT=$vm_count
VM_RAM=$ram
VM_VCPUS=$vcpus
VM_DISK_SIZE=$disk_size
VM_OS_VARIANT=ubuntu22.04
STARTUP_ORDER=$startup_order
STARTUP_DELAY=$startup_delay
SHUTDOWN_ORDER=$shutdown_order
SHUTDOWN_DELAY=$shutdown_delay
AUTO_START=false
NETWORK=default
STORAGE_POOL=default
VM_PREFIX=${template_name}-vm
EOF
    
    print_success "Cluster template '$template_name' created successfully"
    log_info "Created cluster template: $template_name"
}

# List cluster templates
list_cluster_templates() {
    print_info "Available cluster templates:"
    echo
    
    init_cluster_config
    
    if [[ ! -d "$CLUSTER_TEMPLATES_DIR" ]] || [[ -z "$(ls -A "$CLUSTER_TEMPLATES_DIR" 2>/dev/null)" ]]; then
        print_warning "No templates found"
        return 0
    fi
    
    printf "%-20s %-10s %-8s %-8s %-40s\n" "Template Name" "VM Count" "RAM(MB)" "vCPUs" "Description"
    echo "--------------------------------------------------------------------------------"
    
    for template_file in "$CLUSTER_TEMPLATES_DIR"/*.template; do
        if [[ -f "$template_file" ]]; then
            local template_name=$(basename "$template_file" .template)
            local description=$(grep "^DESCRIPTION=" "$template_file" | cut -d= -f2- | tr -d '"')
            local vm_count=$(grep "^VM_COUNT=" "$template_file" | cut -d= -f2)
            local vm_ram=$(grep "^VM_RAM=" "$template_file" | cut -d= -f2)
            local vm_vcpus=$(grep "^VM_VCPUS=" "$template_file" | cut -d= -f2)
            
            printf "%-20s %-10s %-8s %-8s %-40s\n" "$template_name" "$vm_count" "$vm_ram" "$vm_vcpus" "$description"
        fi
    done
}

# Create cluster from template
create_cluster_from_template() {
    local cluster_name="$1"
    local template_name="$2"
    local create_vms="${3:-false}"
    
    [[ -z "$cluster_name" || -z "$template_name" ]] && {
        error_exit "Usage: cluster-from-template <cluster_name> <template_name> [create_vms:true/false]"
    }
    
    validate_cluster_name "$cluster_name"
    validate_cluster_name "$template_name"
    
    local template_file="${CLUSTER_TEMPLATES_DIR}/${template_name}.template"
    
    if [[ ! -f "$template_file" ]]; then
        error_exit "Template '$template_name' does not exist"
    fi
    
    if cluster_exists "$cluster_name"; then
        error_exit "Cluster '$cluster_name' already exists"
    fi
    
    # Load template configuration
    local description=$(grep "^DESCRIPTION=" "$template_file" | cut -d= -f2- | tr -d '"')
    local vm_count=$(grep "^VM_COUNT=" "$template_file" | cut -d= -f2)
    local vm_ram=$(grep "^VM_RAM=" "$template_file" | cut -d= -f2)
    local vm_vcpus=$(grep "^VM_VCPUS=" "$template_file" | cut -d= -f2)
    local vm_disk_size=$(grep "^VM_DISK_SIZE=" "$template_file" | cut -d= -f2)
    local vm_os_variant=$(grep "^VM_OS_VARIANT=" "$template_file" | cut -d= -f2)
    local startup_order=$(grep "^STARTUP_ORDER=" "$template_file" | cut -d= -f2)
    local startup_delay=$(grep "^STARTUP_DELAY=" "$template_file" | cut -d= -f2)
    local shutdown_order=$(grep "^SHUTDOWN_ORDER=" "$template_file" | cut -d= -f2)
    local shutdown_delay=$(grep "^SHUTDOWN_DELAY=" "$template_file" | cut -d= -f2)
    local vm_prefix=$(grep "^VM_PREFIX=" "$template_file" | cut -d= -f2)
    
    print_info "Creating cluster '$cluster_name' from template '$template_name'"
    print_info "Configuration: $vm_count VMs, ${vm_ram}MB RAM, ${vm_vcpus} vCPUs, ${vm_disk_size}GB disk each"
    
    # Generate VM names
    local vm_names=()
    for ((i=1; i<=vm_count; i++)); do
        vm_names+=("${vm_prefix}${i}")
    done
    
    # Create VMs if requested
    if [[ "$create_vms" == "true" ]]; then
        print_info "Creating VMs..."
        for vm_name in "${vm_names[@]}"; do
            print_info "Creating VM: $vm_name"
            if virt-install \
                --name "$vm_name" \
                --ram "$vm_ram" \
                --vcpus "$vm_vcpus" \
                --disk "size=$vm_disk_size,format=qcow2" \
                --os-variant "$vm_os_variant" \
                --network network=default \
                --graphics vnc \
                --noautoconsole \
                --import; then
                print_success "VM '$vm_name' created successfully"
            else
                print_error "Failed to create VM '$vm_name'"
            fi
        done
    fi
    
    # Create cluster configuration
    local cluster_file="${CLUSTER_CONFIG_DIR}/${cluster_name}.conf"
    local vm_list=$(IFS=','; echo "${vm_names[*]}")
    
    cat > "$cluster_file" << EOF
# Cluster Configuration: $cluster_name (from template: $template_name)
CLUSTER_NAME=$cluster_name
DESCRIPTION=$description
CREATED=$(date '+%Y-%m-%d %H:%M:%S')
TEMPLATE_USED=$template_name
VM=$vm_list
VM_COUNT=$vm_count
VM_RAM=$vm_ram
VM_VCPUS=$vm_vcpus
VM_DISK_SIZE=$vm_disk_size
STARTUP_ORDER=$startup_order
STARTUP_DELAY=$startup_delay
SHUTDOWN_ORDER=$shutdown_order
SHUTDOWN_DELAY=$shutdown_delay
AUTO_START=false
EOF
    
    print_success "Cluster '$cluster_name' created from template '$template_name'"
    if [[ "$create_vms" == "true" ]]; then
        print_success "All VMs created and added to cluster"
    else
        print_info "Cluster created without VMs. Add existing VMs or create them separately."
    fi
    
    notify_desktop "Cluster Created" "Cluster '$cluster_name' created from template" "normal" "computer"
    log_info "Created cluster from template: $cluster_name from $template_name"
}

# Cluster health check
cluster_health_check() {
    local cluster_name="$1"
    local detailed="${2:-false}"
    
    [[ -z "$cluster_name" ]] && error_exit "Cluster name required"
    
    validate_cluster_name "$cluster_name"
    
    if ! cluster_exists "$cluster_name"; then
        error_exit "Cluster '$cluster_name' does not exist"
    fi
    
    local vms=($(get_cluster_vms "$cluster_name"))
    local total_vms=${#vms[@]}
    local running_vms=0
    local stopped_vms=0
    local failed_vms=0
    local health_issues=()
    
    print_info "Cluster Health Check: $cluster_name"
    echo "========================================"
    
    for vm in "${vms[@]}"; do
        if [[ -n "$vm" ]]; then
            if ! vm_exists "$vm"; then
                health_issues+=("VM '$vm' does not exist")
                ((failed_vms++))
            else
                local state=$(virsh domstate "$vm" 2>/dev/null)
                case "$state" in
                    "running")
                        ((running_vms++))
                        if [[ "$detailed" == "true" ]]; then
                            local cpu_time=$(virsh cpu-stats "$vm" --total 2>/dev/null | grep "cpu_time" | awk '{print $3}' || echo "N/A")
                            local memory=$(virsh dominfo "$vm" | grep "Used memory" | awk '{print $3 " " $4}' || echo "N/A")
                            printf "✓ %-20s: Running (CPU: %s, Memory: %s)\n" "$vm" "$cpu_time" "$memory"
                        fi
                        ;;
                    "shut off")
                        ((stopped_vms++))
                        [[ "$detailed" == "true" ]] && printf "○ %-20s: Stopped\n" "$vm"
                        ;;
                    "paused")
                        health_issues+=("VM '$vm' is paused")
                        [[ "$detailed" == "true" ]] && printf "⚠ %-20s: Paused\n" "$vm"
                        ;;
                    *)
                        health_issues+=("VM '$vm' in unknown state: $state")
                        ((failed_vms++))
                        [[ "$detailed" == "true" ]] && printf "✗ %-20s: %s\n" "$vm" "$state"
                        ;;
                esac
            fi
        fi
    done
    
    echo
    print_info "Health Summary:"
    echo "  Total VMs: $total_vms"
    echo "  Running: $running_vms"
    echo "  Stopped: $stopped_vms"
    echo "  Failed/Issues: $failed_vms"
    
    # Calculate health score
    local health_score=0
    if [[ $total_vms -gt 0 ]]; then
        health_score=$(( (running_vms * 100) / total_vms ))
    fi
    
    echo "  Health Score: ${health_score}%"
    
    # Health status
    if [[ $health_score -eq 100 ]]; then
        print_success "Cluster Status: HEALTHY"
    elif [[ $health_score -ge 80 ]]; then
        print_warning "Cluster Status: MOSTLY HEALTHY"
    elif [[ $health_score -ge 50 ]]; then
        print_warning "Cluster Status: DEGRADED"
    else
        print_error "Cluster Status: CRITICAL"
    fi
    
    # Report issues
    if [[ ${#health_issues[@]} -gt 0 ]]; then
        echo
        print_warning "Health Issues:"
        for issue in "${health_issues[@]}"; do
            echo "  - $issue"
        done
    fi
    
    log_info "Health check for cluster $cluster_name: $health_score% (${running_vms}/${total_vms} running)"
}

# Scale cluster (add/remove VMs)
scale_cluster() {
    local cluster_name="$1"
    local action="$2"  # add or remove
    local count="$3"
    local create_vms="${4:-false}"
    
    [[ -z "$cluster_name" || -z "$action" || -z "$count" ]] && {
        error_exit "Usage: cluster-scale <cluster_name> <add|remove> <count> [create_vms:true/false]"
    }
    
    validate_cluster_name "$cluster_name"
    validate_number "$count" "Count"
    
    if ! cluster_exists "$cluster_name"; then
        error_exit "Cluster '$cluster_name' does not exist"
    fi
    
    local cluster_file="${CLUSTER_CONFIG_DIR}/${cluster_name}.conf"
    local current_vms=($(get_cluster_vms "$cluster_name"))
    local current_count=${#current_vms[@]}
    
    case "$action" in
        "add")
            print_info "Scaling up cluster '$cluster_name' by $count VMs"
            
            # Get VM prefix from cluster config or generate one
            local vm_prefix=$(grep "^VM_PREFIX=" "$cluster_file" 2>/dev/null | cut -d= -f2)
            if [[ -z "$vm_prefix" ]]; then
                vm_prefix="${cluster_name}-vm"
            fi
            
            local new_vms=()
            for ((i=1; i<=count; i++)); do
                local next_index=$((current_count + i))
                local new_vm_name="${vm_prefix}${next_index}"
                new_vms+=("$new_vm_name")
                
                # Create VM if requested
                if [[ "$create_vms" == "true" ]]; then
                    local vm_ram=$(grep "^VM_RAM=" "$cluster_file" 2>/dev/null | cut -d= -f2 || echo "2048")
                    local vm_vcpus=$(grep "^VM_VCPUS=" "$cluster_file" 2>/dev/null | cut -d= -f2 || echo "2")
                    local vm_disk_size=$(grep "^VM_DISK_SIZE=" "$cluster_file" 2>/dev/null | cut -d= -f2 || echo "20")
                    
                    print_info "Creating VM: $new_vm_name"
                    if virt-install \
                        --name "$new_vm_name" \
                        --ram "$vm_ram" \
                        --vcpus "$vm_vcpus" \
                        --disk "size=$vm_disk_size,format=qcow2" \
                        --os-variant ubuntu22.04 \
                        --network network=default \
                        --graphics vnc \
                        --noautoconsole \
                        --import; then
                        print_success "VM '$new_vm_name' created successfully"
                    else
                        print_error "Failed to create VM '$new_vm_name'"
                        continue
                    fi
                fi
                
                # Add VM to cluster
                add_vm_to_cluster "$cluster_name" "$new_vm_name"
            done
            
            # Update VM count in cluster config
            local new_count=$((current_count + count))
            sed -i "s/^VM_COUNT=.*/VM_COUNT=${new_count}/" "$cluster_file" 2>/dev/null || true
            
            print_success "Cluster '$cluster_name' scaled up from $current_count to $new_count VMs"
            ;;
            
        "remove")
            if [[ $count -ge $current_count ]]; then
                error_exit "Cannot remove $count VMs from cluster with only $current_count VMs"
            fi
            
            print_warning "Scaling down cluster '$cluster_name' by $count VMs"
            
            # Remove VMs from the end of the list
            local vms_to_remove=()
            for ((i=0; i<count; i++)); do
                local vm_index=$((current_count - 1 - i))
                if [[ $vm_index -ge 0 ]]; then
                    vms_to_remove+=("${current_vms[$vm_index]}")
                fi
            done
            
            for vm in "${vms_to_remove[@]}"; do
                if [[ -n "$vm" ]]; then
                    print_info "Removing VM from cluster: $vm"
                    remove_vm_from_cluster "$cluster_name" "$vm"
                    
                    # Optionally delete the VM entirely
                    read -p "Delete VM '$vm' entirely? [y/N]: " -r
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        if vm_is_running "$vm"; then
                            virsh destroy "$vm" 2>/dev/null || true
                        fi
                        virsh undefine "$vm" --remove-all-storage 2>/dev/null || \
                        virsh undefine "$vm" 2>/dev/null || \
                        print_warning "Failed to delete VM: $vm"
                    fi
                fi
            done
            
            # Update VM count in cluster config
            local new_count=$((current_count - count))
            sed -i "s/^VM_COUNT=.*/VM_COUNT=${new_count}/" "$cluster_file" 2>/dev/null || true
            
            print_success "Cluster '$cluster_name' scaled down from $current_count to $new_count VMs"
            ;;
            
        *)
            error_exit "Invalid action '$action'. Use 'add' or 'remove'"
            ;;
    esac
    
    log_info "Scaled cluster $cluster_name: $action $count VMs"
}

# Backup cluster configuration
backup_cluster() {
    local cluster_name="$1"
    local backup_name="${2:-$(date +%Y%m%d_%H%M%S)}"
    
    [[ -z "$cluster_name" ]] && error_exit "Cluster name required"
    
    validate_cluster_name "$cluster_name"
    
    if ! cluster_exists "$cluster_name"; then
        error_exit "Cluster '$cluster_name' does not exist"
    fi
    
    init_cluster_config
    
    local cluster_file="${CLUSTER_CONFIG_DIR}/${cluster_name}.conf"
    local backup_dir="${CLUSTER_BACKUPS_DIR}/${cluster_name}_${backup_name}"
    
    mkdir -p "$backup_dir"
    
    # Backup cluster configuration
    cp "$cluster_file" "$backup_dir/cluster.conf"
    
    # Backup VM configurations
    local vms=($(get_cluster_vms "$cluster_name"))
    for vm in "${vms[@]}"; do
        if [[ -n "$vm" ]] && vm_exists "$vm"; then
            print_info "Backing up VM configuration: $vm"
            virsh dumpxml "$vm" > "$backup_dir/${vm}.xml"
        fi
    done
    
    # Create backup manifest
    cat > "$backup_dir/manifest.txt" << EOF
Cluster Backup: $cluster_name
Backup Name: $backup_name
Created: $(date '+%Y-%m-%d %H:%M:%S')
VMs: ${#vms[@]}
Files:
- cluster.conf (cluster configuration)
$(for vm in "${vms[@]}"; do [[ -n "$vm" ]] && echo "- ${vm}.xml (VM configuration)"; done)
EOF
    
    print_success "Cluster '$cluster_name' backed up to: $backup_dir"
    log_info "Backed up cluster: $cluster_name to $backup_name"
}

# List cluster backups
list_cluster_backups() {
    local cluster_name="$1"
    
    init_cluster_config
    
    if [[ -n "$cluster_name" ]]; then
        print_info "Backups for cluster: $cluster_name"
        pattern="${cluster_name}_*"
    else
        print_info "All cluster backups:"
        pattern="*"
    fi
    
    echo
    
    if [[ ! -d "$CLUSTER_BACKUPS_DIR" ]] || [[ -z "$(ls -A "$CLUSTER_BACKUPS_DIR" 2>/dev/null)" ]]; then
        print_warning "No backups found"
        return 0
    fi
    
    printf "%-30s %-20s %-20s %-10s\n" "Backup Directory" "Cluster" "Created" "VM Count"
    echo "--------------------------------------------------------------------------------"
    
    for backup_dir in "$CLUSTER_BACKUPS_DIR"/$pattern; do
        if [[ -d "$backup_dir" ]] && [[ -f "$backup_dir/manifest.txt" ]]; then
            local backup_name=$(basename "$backup_dir")
            local cluster=$(grep "^Cluster Backup:" "$backup_dir/manifest.txt" | cut -d: -f2- | xargs)
            local created=$(grep "^Created:" "$backup_dir/manifest.txt" | cut -d: -f2- | xargs)
            local vm_count=$(grep "^VMs:" "$backup_dir/manifest.txt" | cut -d: -f2- | xargs)
            
            printf "%-30s %-20s %-20s %-10s\n" "$backup_name" "$cluster" "$created" "$vm_count"
        fi
    done
}

# Cluster statistics and dashboard
cluster_dashboard() {
    print_info "Cluster Management Dashboard"
    echo "============================"
    echo
    
    init_cluster_config
    
    local total_clusters=0
    local running_clusters=0
    local total_vms=0
    local running_vms=0
    local total_memory=0
    local total_vcpus=0
    
    # Collect statistics
    for cluster_file in "$CLUSTER_CONFIG_DIR"/*.conf; do
        if [[ -f "$cluster_file" ]]; then
            local cluster_name=$(basename "$cluster_file" .conf)
            local vms=($(get_cluster_vms "$cluster_name"))
            local cluster_running_vms=0
            
            ((total_clusters++))
            total_vms=$((total_vms + ${#vms[@]}))
            
            for vm in "${vms[@]}"; do
                if [[ -n "$vm" ]] && vm_exists "$vm" && vm_is_running "$vm"; then
                    ((cluster_running_vms++))
                    ((running_vms++))
                    
                    # Get VM resources
                    local vm_memory=$(virsh dominfo "$vm" 2>/dev/null | grep "Max memory" | awk '{print $3}' || echo "0")
                    local vm_vcpus=$(virsh dominfo "$vm" 2>/dev/null | grep "CPU(s)" | awk '{print $2}' || echo "0")
                    total_memory=$((total_memory + vm_memory))
                    total_vcpus=$((total_vcpus + vm_vcpus))
                fi
            done
            
            if [[ $cluster_running_vms -eq ${#vms[@]} ]] && [[ ${#vms[@]} -gt 0 ]]; then
                ((running_clusters++))
            fi
        fi
    done
    
    # Display statistics
    print_info "Cluster Overview:"
    printf "%-20s: %d\n" "Total Clusters" "$total_clusters"
    printf "%-20s: %d\n" "Running Clusters" "$running_clusters"
    printf "%-20s: %d\n" "Total VMs" "$total_vms"
    printf "%-20s: %d\n" "Running VMs" "$running_vms"
    printf "%-20s: %d MB\n" "Total Memory" "$total_memory"
    printf "%-20s: %d\n" "Total vCPUs" "$total_vcpus"
    
    echo
    
    # Show cluster status
    print_info "Cluster Status:"
    printf "%-20s %-10s %-15s %-10s\n" "Cluster" "Status" "VMs (Run/Total)" "Health"
    echo "---------------------------------------------------------------"
    
    for cluster_file in "$CLUSTER_CONFIG_DIR"/*.conf; do
        if [[ -f "$cluster_file" ]]; then
            local cluster_name=$(basename "$cluster_file" .conf)
            local vms=($(get_cluster_vms "$cluster_name"))
            local cluster_running=0
            
            for vm in "${vms[@]}"; do
                if [[ -n "$vm" ]] && vm_exists "$vm" && vm_is_running "$vm"; then
                    ((cluster_running++))
                fi
            done
            
            local status
            local health
            if [[ $cluster_running -eq ${#vms[@]} ]] && [[ ${#vms[@]} -gt 0 ]]; then
                status="Running"
                health="100%"
            elif [[ $cluster_running -gt 0 ]]; then
                status="Partial"
                health="$((cluster_running * 100 / ${#vms[@]}))%"
            else
                status="Stopped"
                health="0%"
            fi
            
            printf "%-20s %-10s %-15s %-10s\n" "$cluster_name" "$status" "${cluster_running}/${#vms[@]}" "$health"
        fi
    done
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
    local total_vms=$(virsh list --all --name 2>/dev/null | wc -l || echo "0")
    local running_vms=$(virsh list --name 2>/dev/null | wc -l || echo "0")
    local stopped_vms=$((${total_vms:-0} - ${running_vms:-0}))
    
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
    echo -e "${BLUE}Cluster Management:${NC}"
    echo "  cluster-list                   - List all clusters with status"
    echo "  cluster-create <name> [description] <vm1> [vm2] [...] - Create a new cluster"
    echo "  cluster-start <name> [parallel] - Start all VMs in a cluster"
    echo "  cluster-stop <name> [timeout] [parallel] - Stop all VMs in a cluster"
    echo "  cluster-info <name>            - Show detailed cluster information"
    echo "  cluster-add <cluster> <vm>     - Add VM to cluster"
    echo "  cluster-remove <cluster> <vm>  - Remove VM from cluster"
    echo "  cluster-delete <name> [delete-vms] - Delete cluster (optionally with VMs)"
    echo
    echo -e "${BLUE}Advanced Cluster Features:${NC}"
    echo "  cluster-dashboard              - Show cluster management dashboard"
    echo "  cluster-health <name> [detailed] - Check cluster health status"
    echo "  cluster-scale <name> <add|remove> <count> [create-vms] - Scale cluster up/down"
    echo "  cluster-backup <name> [backup-name] - Backup cluster configuration"
    echo "  cluster-backups [cluster-name] - List cluster backups"
    echo
    echo -e "${BLUE}Cluster Templates:${NC}"
    echo "  template-create <name> <description> <ram> <vcpus> <disk> [count] - Create template"
    echo "  template-list                  - List all cluster templates"
    echo "  cluster-from-template <cluster> <template> [create-vms] - Create from template"
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
    echo -e "${BLUE}Cluster Examples:${NC}"
    echo "  $SCRIPT_NAME cluster-create webcluster \"Web servers\" web1 web2 web3"
    echo "  $SCRIPT_NAME cluster-start webcluster true  # Start cluster in parallel"
    echo "  $SCRIPT_NAME cluster-stop webcluster 30 false # Sequential stop with 30s timeout"
    echo "  $SCRIPT_NAME cluster-add webcluster web4    # Add VM to cluster"
    echo "  $SCRIPT_NAME cluster-scale webcluster add 2 true # Scale up by 2 VMs"
    echo "  $SCRIPT_NAME cluster-health webcluster true # Detailed health check"
    echo "  $SCRIPT_NAME cluster-backup webcluster prod-backup # Backup cluster"
    echo "  $SCRIPT_NAME template-create web-template \"Web server template\" 2048 2 20 3"
    echo "  $SCRIPT_NAME cluster-from-template newcluster web-template true"
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
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME list"
                echo "List all VMs with summary information including status, RAM, and CPU count"
                exit 0
            fi
            list_vms
            ;;
        running)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME running"
                echo "List running VMs with resource usage information"
                exit 0
            fi
            list_running_vms
            ;;
        start)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME start <vm_name>"
                echo "Start a VM"
                echo "  vm_name    - Name of the VM to start"
                exit 0
            fi
            start_vm "$2"
            ;;
        stop)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME stop <vm_name> [timeout]"
                echo "Stop a VM gracefully"
                echo "  vm_name    - Name of the VM to stop"
                echo "  timeout    - Timeout in seconds (default: 60)"
                exit 0
            fi
            stop_vm "$2" "$3"
            ;;
        force-stop)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME force-stop <vm_name>"
                echo "Force stop a VM immediately"
                echo "  vm_name    - Name of the VM to force stop"
                exit 0
            fi
            force_stop_vm "$2"
            ;;
        delete)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME delete <vm_name> [backup]"
                echo "Delete a VM"
                echo "  vm_name    - Name of the VM to delete"
                echo "  backup     - true to save config before deletion (default: false)"
                exit 0
            fi
            delete_vm "$2" "$3"
            ;;
        info)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME info <vm_name>"
                echo "Show detailed VM information"
                echo "  vm_name    - Name of the VM to get info for"
                exit 0
            fi
            vm_info "$2"
            ;;
        console)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME console <vm_name>"
                echo "Connect to VM console"
                echo "  vm_name    - Name of the VM to connect to"
                exit 0
            fi
            vm_console "$2"
            ;;
        create-iso)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME create-iso <name> <ram_mb> <vcpus> <iso_path> [disk_size_gb] [os_variant]"
                echo "Create a VM from ISO"
                echo "  name           - Name for the new VM"
                echo "  ram_mb         - RAM in MB"
                echo "  vcpus          - Number of virtual CPUs"
                echo "  iso_path       - Path to ISO file"
                echo "  disk_size_gb   - Disk size in GB (default: 20)"
                echo "  os_variant     - OS variant (use 'os-variants' command to list)"
                exit 0
            fi
            create_vm_from_iso "$2" "$3" "$4" "$5" "$6" "$7"
            ;;
        
        # Cluster management commands
        cluster-list)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME cluster-list"
                echo "List all clusters with status information"
                exit 0
            fi
            list_clusters
            ;;
        cluster-create)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME cluster-create <name> [description] <vm1> [vm2] [...]"
                echo "Create a new cluster"
                echo "  name          - Name for the cluster"
                echo "  description   - Description of the cluster"
                echo "  vm1, vm2...   - VMs to include in the cluster"
                exit 0
            fi
            if [[ $# -lt 4 ]]; then
                error_exit "Usage: cluster-create <name> [description] <vm1> [vm2] [...]"
            fi
            cluster_name="$2"
            description="$3"
            shift 3
            create_cluster "$cluster_name" "$description" "$@"
            ;;
        cluster-start)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME cluster-start <name> [parallel]"
                echo "Start all VMs in a cluster"
                echo "  name       - Name of the cluster"
                echo "  parallel   - Start VMs in parallel (true/false, default: false)"
                exit 0
            fi
            parallel="${3:-false}"
            start_cluster "$2" "$parallel"
            ;;
        cluster-stop)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME cluster-stop <name> [timeout] [parallel]"
                echo "Stop all VMs in a cluster"
                echo "  name       - Name of the cluster"
                echo "  timeout    - Timeout in seconds (default: 60)"
                echo "  parallel   - Stop VMs in parallel (true/false, default: false)"
                exit 0
            fi
            timeout="${3:-60}"
            parallel="${4:-false}"
            stop_cluster "$2" "$timeout" "$parallel"
            ;;
        cluster-info)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME cluster-info <name>"
                echo "Show detailed cluster information"
                echo "  name       - Name of the cluster"
                exit 0
            fi
            cluster_info "$2"
            ;;
        cluster-add)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME cluster-add <cluster> <vm>"
                echo "Add VM to cluster"
                echo "  cluster    - Name of the cluster"
                echo "  vm         - Name of the VM to add"
                exit 0
            fi
            add_vm_to_cluster "$2" "$3"
            ;;
        cluster-remove)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME cluster-remove <cluster> <vm>"
                echo "Remove VM from cluster"
                echo "  cluster    - Name of the cluster"
                echo "  vm         - Name of the VM to remove"
                exit 0
            fi
            remove_vm_from_cluster "$2" "$3"
            ;;
        cluster-delete)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME cluster-delete <name> [delete-vms]"
                echo "Delete cluster"
                echo "  name        - Name of the cluster"
                echo "  delete-vms  - Also delete VMs (true/false, default: false)"
                exit 0
            fi
            delete_vms="${3:-false}"
            delete_cluster "$2" "$delete_vms"
            ;;
        
        # Enhanced cluster management commands
        cluster-dashboard)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME cluster-dashboard"
                echo "Show cluster management dashboard with overview of all clusters"
                exit 0
            fi
            cluster_dashboard
            ;;
        cluster-health)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME cluster-health <name> [detailed]"
                echo "Check cluster health status"
                echo "  name       - Name of the cluster"
                echo "  detailed   - Show detailed health info (true/false, default: false)"
                exit 0
            fi
            detailed="${3:-false}"
            cluster_health_check "$2" "$detailed"
            ;;
        cluster-scale)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME cluster-scale <name> <add|remove> <count> [create-vms]"
                echo "Scale cluster up or down"
                echo "  name        - Name of the cluster"
                echo "  add|remove  - Scale operation (add or remove)"
                echo "  count       - Number of VMs to add/remove"
                echo "  create-vms  - Create new VMs when scaling up (true/false, default: false)"
                exit 0
            fi
            create_vms="${5:-false}"
            scale_cluster "$2" "$3" "$4" "$create_vms"
            ;;
        cluster-backup)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME cluster-backup <name> [backup-name]"
                echo "Backup cluster configuration"
                echo "  name         - Name of the cluster"
                echo "  backup-name  - Name for the backup (optional)"
                exit 0
            fi
            backup_cluster "$2" "$3"
            ;;
        cluster-backups)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME cluster-backups [cluster-name]"
                echo "List cluster backups"
                echo "  cluster-name  - Filter by cluster name (optional)"
                exit 0
            fi
            list_cluster_backups "${2:-}"
            ;;
        
        # Template management commands
        template-create)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME template-create <name> <description> <ram_mb> <vcpus> <disk_gb> [vm_count]"
                echo "Create cluster template"
                echo "  name         - Template name"
                echo "  description  - Template description"
                echo "  ram_mb       - RAM in MB"
                echo "  vcpus        - Number of virtual CPUs"
                echo "  disk_gb      - Disk size in GB"
                echo "  vm_count     - Number of VMs in template (default: 3)"
                exit 0
            fi
            if [[ $# -lt 6 ]]; then
                error_exit "Usage: template-create <name> <description> <ram_mb> <vcpus> <disk_gb> [vm_count]"
            fi
            vm_count="${7:-3}"
            create_cluster_template "$2" "$3" "$4" "$5" "$6" "$vm_count"
            ;;
        template-list)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME template-list"
                echo "List all cluster templates"
                exit 0
            fi
            list_cluster_templates
            ;;
        cluster-from-template)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME cluster-from-template <cluster> <template> [create-vms]"
                echo "Create cluster from template"
                echo "  cluster     - Name for new cluster"
                echo "  template    - Template name to use"
                echo "  create-vms  - Create VMs from template (true/false, default: false)"
                exit 0
            fi
            create_vms="${4:-false}"
            create_cluster_from_template "$2" "$3" "$create_vms"
            ;;
        
        viewer)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME viewer <vm_name> [type]"
                echo "Open GUI viewer for VM"
                echo "  vm_name    - Name of the VM"
                echo "  type       - Viewer type (auto/vnc/spice/virt-viewer, default: auto)"
                exit 0
            fi
            vm_viewer "$2" "$3"
            ;;
        quick-start)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME quick-start <vm_name>"
                echo "Start VM and open viewer"
                echo "  vm_name    - Name of the VM"
                exit 0
            fi
            quick_start_vm "$2"
            ;;
        gui-info)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME gui-info <vm_name>"
                echo "Show VM info in GUI dialog"
                echo "  vm_name    - Name of the VM"
                exit 0
            fi
            gui_vm_info "$2"
            ;;
        desktop-shortcut)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME desktop-shortcut <vm_name> [icon]"
                echo "Create desktop shortcut for VM"
                echo "  vm_name    - Name of the VM"
                echo "  icon       - Icon name (optional, default: computer)"
                exit 0
            fi
            create_vm_desktop_shortcut "$2" "$3"
            ;;
        autostart)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME autostart <vm_name> <enable|disable>"
                echo "Setup VM autostart on login"
                echo "  vm_name    - Name of the VM"
                echo "  action     - enable or disable autostart"
                exit 0
            fi
            setup_vm_autostart "$2" "$3"
            ;;
        monitor)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME monitor <vm_name> [interval]"
                echo "Monitor VM with desktop notifications"
                echo "  vm_name    - Name of the VM"
                echo "  interval   - Check interval in seconds (default: 60)"
                exit 0
            fi
            monitor_vm "$2" "$3"
            ;;
        interactive)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME interactive"
                echo "Launch interactive text-based manager"
                exit 0
            fi
            interactive_manager
            ;;
        install-desktop)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME install-desktop"
                echo "Install desktop integration files"
                exit 0
            fi
            install_desktop_integration
            ;;
        uninstall-desktop)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME uninstall-desktop"
                echo "Remove desktop integration files"
                exit 0
            fi
            uninstall_desktop_integration
            ;;
        
        # System information commands
        status)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME status"
                echo "Show libvirt service status"
                exit 0
            fi
            check_service_status
            ;;
        resources)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME resources"
                echo "Show system resource usage"
                exit 0
            fi
            show_system_resources
            ;;
        os-variants)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME os-variants"
                echo "List available OS variants for VM creation"
                exit 0
            fi
            list_os_variants
            ;;
        check)
            if [[ "$2" == "--help" ]]; then
                echo "Usage: $SCRIPT_NAME check"
                echo "Check dependencies and permissions"
                exit 0
            fi
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