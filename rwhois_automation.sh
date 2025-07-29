#!/bin/bash

# RWHOIS Automation Script
# Automates installation, configuration, and management of RWHOIS server
# Author: ENGINYRING
# Version: 1.0
# GitHub: https://github.com/ENGINYRING/rwhois-automation

set -e  # Exit on any error

# Configuration variables
RWHOIS_USER="rwhois"
RWHOIS_GROUP="rwhois"
RWHOIS_HOME="/usr/local/rwhois"
RWHOIS_DATA="$RWHOIS_HOME/data"
RWHOIS_CONFIG="$RWHOIS_HOME/etc"
RWHOIS_BIN="$RWHOIS_HOME/bin"
RWHOIS_LOG="/var/log/rwhois"
RWHOIS_PORT="4321"
RWHOIS_VERSION="1.5.9.6"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
}

# Cleanup existing installation
cleanup_existing() {
    log "Cleaning up any existing RWHOIS installation..."
    
    # Stop any running services
    if [ -d /run/systemd/system ] && pidof systemd &> /dev/null && systemctl --version &> /dev/null 2>&1; then
        if systemctl is-active --quiet rwhois 2>/dev/null; then
            log "Stopping existing systemd service..."
            systemctl stop rwhois 2>/dev/null || true
            systemctl disable rwhois 2>/dev/null || true
        fi
        # Remove systemd service file
        if [ -f /etc/systemd/system/rwhois.service ]; then
            rm -f /etc/systemd/system/rwhois.service
            systemctl daemon-reload 2>/dev/null || true
            log "Removed existing systemd service"
        fi
    fi
    
    # Stop and remove init script
    if [ -f /etc/init.d/rwhois ]; then
        log "Stopping and removing existing init script..."
        /etc/init.d/rwhois stop 2>/dev/null || true
        
        # Remove from startup
        if command -v update-rc.d &> /dev/null; then
            update-rc.d rwhois remove 2>/dev/null || true
        elif command -v chkconfig &> /dev/null; then
            chkconfig rwhois off 2>/dev/null || true
            chkconfig --del rwhois 2>/dev/null || true
        fi
        
        rm -f /etc/init.d/rwhois
        log "Removed existing init script"
    fi
    
    # Kill any running rwhoisd processes
    if pgrep -f rwhoisd > /dev/null; then
        log "Stopping running RWHOIS processes..."
        pkill -f rwhoisd 2>/dev/null || true
        sleep 2
        if pgrep -f rwhoisd > /dev/null; then
            pkill -9 -f rwhoisd 2>/dev/null || true
        fi
        log "Stopped running RWHOIS processes"
    fi
    
    # Remove existing installation directory (but preserve data)
    if [ -d "$RWHOIS_HOME" ]; then
        log "Backing up existing data and removing old installation..."
        
        # Backup existing data if it exists
        if [ -d "$RWHOIS_DATA" ] && [ "$(ls -A $RWHOIS_DATA 2>/dev/null)" ]; then
            backup_dir="/tmp/rwhois_backup_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$backup_dir"
            cp -r "$RWHOIS_DATA"/* "$backup_dir/" 2>/dev/null || true
            log "Backed up existing data to $backup_dir"
        fi
        
        # Remove old installation but preserve the rwhois user
        rm -rf "$RWHOIS_HOME"
        log "Removed old installation directory"
    fi
    
    # Clean up lock files
    rm -f /var/lock/subsys/rwhois /var/lock/rwhois 2>/dev/null || true
    
    # Clean up any temp files
    rm -rf /tmp/rwhois* /tmp/rwhoisd* 2>/dev/null || true
    
    log "Cleanup completed"
}

# Install dependencies
install_dependencies() {
    log "Installing dependencies..."
    
    # Detect OS
    if [[ -f /etc/redhat-release ]]; then
        # RHEL/CentOS/Fedora
        yum update -y
        yum groupinstall -y "Development Tools"
        yum install -y gcc gcc-c++ make autoconf automake libtool \
                      flex bison openssl-devel zlib-devel wget curl netcat
    elif [[ -f /etc/debian_version ]]; then
        # Debian/Ubuntu
        apt-get update
        apt-get install -y build-essential gcc g++ make autoconf automake libtool \
                          flex bison libssl-dev zlib1g-dev wget curl netcat-openbsd
    else
        error "Unsupported operating system"
        exit 1
    fi
    
    log "Dependencies installed successfully"
}

# Create RWHOIS user and directories
setup_user_dirs() {
    log "Setting up RWHOIS user and directories..."
    
    # Create user with proper home directory and shell
    if ! id "$RWHOIS_USER" &>/dev/null; then
        useradd -r -d "$RWHOIS_HOME" -s /bin/bash "$RWHOIS_USER"
        log "Created user: $RWHOIS_USER"
    else
        # Fix existing user if needed
        usermod -d "$RWHOIS_HOME" -s /bin/bash "$RWHOIS_USER" 2>/dev/null || true
        log "Updated existing user: $RWHOIS_USER"
    fi
    
    # Create directories
    mkdir -p "$RWHOIS_HOME"/{bin,etc,data,log}
    mkdir -p "$RWHOIS_DATA"/{org,contact,network}
    mkdir -p "$RWHOIS_LOG"
    
    # Restore backed up data if it exists
    backup_dir=$(ls -1d /tmp/rwhois_backup_* 2>/dev/null | tail -n1)
    if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
        log "Restoring backed up data from $backup_dir"
        cp -r "$backup_dir"/* "$RWHOIS_DATA/" 2>/dev/null || true
        rm -rf "$backup_dir"
        log "Data restored successfully"
    fi
    
    # Set permissions
    chown -R "$RWHOIS_USER:$RWHOIS_GROUP" "$RWHOIS_HOME"
    chown -R "$RWHOIS_USER:$RWHOIS_GROUP" "$RWHOIS_LOG"
    chmod 755 "$RWHOIS_HOME"
    chmod 755 "$RWHOIS_DATA"
    
    # Ensure rwhois user can access its home directory
    sudo -u "$RWHOIS_USER" test -r "$RWHOIS_HOME" || {
        error "RWHOIS user cannot access home directory"
        exit 1
    }
    
    log "User and directories setup completed"
}

# Download and install RWHOIS
install_rwhois() {
    log "Downloading and installing RWHOIS..."
    
    cd /tmp
    wget -O rwhois-${RWHOIS_VERSION}.tar.gz \
        "https://github.com/arineng/rwhoisd/archive/refs/tags/${RWHOIS_VERSION}.tar.gz" || \
    wget -O rwhois-${RWHOIS_VERSION}.tar.gz \
        "https://ftp.arin.net/rwhoisd/rwhoisd-${RWHOIS_VERSION}.tar.gz"
    
    tar -xzf rwhois-${RWHOIS_VERSION}.tar.gz
    
    # GitHub archives create directory named repo-tag, try both possibilities
    if [[ -d "rwhoisd-${RWHOIS_VERSION}" ]]; then
        cd "rwhoisd-${RWHOIS_VERSION}"
    elif [[ -d "rwhois-${RWHOIS_VERSION}" ]]; then
        cd "rwhois-${RWHOIS_VERSION}"
    else
        # List directories to see what was actually created
        echo "Available directories:"
        ls -la
        error "Could not find extracted directory"
        exit 1
    fi
    
    log "Current directory contents:"
    ls -la
    
    # Check if there's a nested rwhoisd directory (common in GitHub archives)
    if [[ -d "rwhoisd" ]]; then
        log "Found nested rwhoisd directory, entering..."
        cd rwhoisd
        log "Now in rwhoisd subdirectory:"
        ls -la
    fi
    
    # Check what build system is available
    if [[ -f "configure" ]]; then
        log "Found existing configure script"
        log "Running configure and make..."
        ./configure --prefix="$RWHOIS_HOME"
        make
        make install
        
        # Find and copy the main rwhoisd binary
        if [[ -f "server/rwhoisd" ]]; then
            cp server/rwhoisd "$RWHOIS_BIN/"
            log "Copied rwhoisd binary from server/ directory"
        elif [[ -f "rwhoisd" ]]; then
            cp rwhoisd "$RWHOIS_BIN/"
            log "Copied rwhoisd binary from current directory"
        fi
        
        # Copy additional tools
        if [[ -f "tools/rwhois_indexer/rwhois_indexer" ]]; then
            cp tools/rwhois_indexer/rwhois_indexer "$RWHOIS_BIN/"
        elif [[ -f "tools/rwhois_indexer" ]]; then
            cp tools/rwhois_indexer "$RWHOIS_BIN/"
        fi
        chmod +x "$RWHOIS_BIN"/*
        
    elif [[ -f "configure.ac" ]] || [[ -f "configure.in" ]]; then
        log "Generating configure script with autoreconf..."
        autoreconf -fiv
        log "Running configure and make..."
        ./configure --prefix="$RWHOIS_HOME"
        make
        make install
        
        # Find and copy the main rwhoisd binary
        if [[ -f "server/rwhoisd" ]]; then
            cp server/rwhoisd "$RWHOIS_BIN/"
            log "Copied rwhoisd binary from server/ directory"
        elif [[ -f "rwhoisd" ]]; then
            cp rwhoisd "$RWHOIS_BIN/"
            log "Copied rwhoisd binary from current directory"  
        fi
        
        # Copy additional tools
        if [[ -f "tools/rwhois_indexer/rwhois_indexer" ]]; then
            cp tools/rwhois_indexer/rwhois_indexer "$RWHOIS_BIN/"
        elif [[ -f "tools/rwhois_indexer" ]]; then
            cp tools/rwhois_indexer "$RWHOIS_BIN/"
        fi
        chmod +x "$RWHOIS_BIN"/*
        
    elif [[ -f "Makefile" ]]; then
        log "Found Makefile, attempting direct make..."
        make PREFIX="$RWHOIS_HOME"
        make install PREFIX="$RWHOIS_HOME"
        
        # Find and copy binaries
        if [[ -f "server/rwhoisd" ]]; then
            cp server/rwhoisd "$RWHOIS_BIN/"
        elif [[ -f "rwhoisd" ]]; then
            cp rwhoisd "$RWHOIS_BIN/"
        fi
        if [[ -f "tools/rwhois_indexer/rwhois_indexer" ]]; then
            cp tools/rwhois_indexer/rwhois_indexer "$RWHOIS_BIN/"
        elif [[ -f "rwhois_indexer" ]]; then
            cp rwhois_indexer "$RWHOIS_BIN/"
        fi
        
        chmod +x "$RWHOIS_BIN"/*
        
    else
        log "Available files:"
        find . -name "*.ac" -o -name "*.in" -o -name "Makefile*" -o -name "configure*" | head -20
        error "No recognized build system found"
        exit 1
    fi
    
    # Verify that rwhoisd binary exists
    if [[ ! -f "$RWHOIS_BIN/rwhoisd" ]]; then
        log "rwhoisd binary not found in $RWHOIS_BIN, searching for it..."
        
        # Search for rwhoisd binary in build directory
        rwhoisd_locations=$(find . -name "rwhoisd" -type f -executable 2>/dev/null)
        if [[ -n "$rwhoisd_locations" ]]; then
            rwhoisd_binary=$(echo "$rwhoisd_locations" | head -n1)
            log "Found rwhoisd at: $rwhoisd_binary"
            cp "$rwhoisd_binary" "$RWHOIS_BIN/"
            chmod +x "$RWHOIS_BIN/rwhoisd"
            log "Copied rwhoisd binary to $RWHOIS_BIN/"
        else
            error "Could not find rwhoisd binary anywhere in build directory"
            exit 1
        fi
    fi
    
    log "Binary verification:"
    ls -la "$RWHOIS_BIN/"
    
    # Clean up
    cd /
    rm -rf /tmp/rwhois*
    
    log "RWHOIS installed successfully"
}

# Configure RWHOIS
configure_rwhois() {
    log "Configuring RWHOIS..."
    
    # Use the sample configuration files as they are designed to work
    if [ -d "$RWHOIS_HOME/etc/rwhoisd/samples" ]; then
        log "Using sample configuration as primary data directory..."
        
        # The samples directory IS the data directory in this setup
        SAMPLES_DIR="$RWHOIS_HOME/etc/rwhoisd/samples"
        
        # Copy the sample config to the main config location
        cp "$SAMPLES_DIR/rwhoisd.conf" "$RWHOIS_CONFIG/rwhoisd.conf"
        
        # Update only the userid in the main config
        sed -i "s|userid:.*|userid: $RWHOIS_USER|g" "$RWHOIS_CONFIG/rwhoisd.conf"
        sed -i "s|server-contact:.*|server-contact: admin@example.com|g" "$RWHOIS_CONFIG/rwhoisd.conf"
        
        # Add PID file setting if not present
        if ! grep -q "pid-file:" "$RWHOIS_CONFIG/rwhoisd.conf"; then
            echo "pid-file: $RWHOIS_HOME/rwhoisd.pid" >> "$RWHOIS_CONFIG/rwhoisd.conf"
        fi
        
        # Create our schema files in the samples directory (which is the active data directory)
        create_schema_files_in_samples "$SAMPLES_DIR"
        
        # Update the global RWHOIS_DATA variable to point to samples directory
        RWHOIS_DATA="$SAMPLES_DIR"
        
    else
        log "Sample files not found, creating minimal configuration..."
        
        # Fallback to basic configuration
        mkdir -p "$RWHOIS_DATA"
        cat > "$RWHOIS_CONFIG/rwhoisd.conf" << EOF
# Minimal RWHOIS Server Configuration
userid: $RWHOIS_USER
server-contact: admin@example.com
pid-file: $RWHOIS_HOME/rwhoisd.pid
root-dir: $RWHOIS_DATA
EOF
        create_schema_files
    fi
    
    # Set permissions
    chown -R "$RWHOIS_USER:$RWHOIS_GROUP" "$RWHOIS_CONFIG"
    chown -R "$RWHOIS_USER:$RWHOIS_GROUP" "$RWHOIS_HOME/etc/rwhoisd"
    
    log "RWHOIS configuration completed"
}

# Create schema files in samples directory
create_schema_files_in_samples() {
    local samples_dir="$1"
    
    log "Creating directories in $samples_dir"
    
    # Create directories first with explicit logging
    mkdir -p "$samples_dir/org" && log "Created $samples_dir/org"
    mkdir -p "$samples_dir/contact" && log "Created $samples_dir/contact" 
    mkdir -p "$samples_dir/network" && log "Created $samples_dir/network"
    mkdir -p "$samples_dir/network/ipv4" && log "Created $samples_dir/network/ipv4"
    mkdir -p "$samples_dir/network/ipv6" && log "Created $samples_dir/network/ipv6"
    mkdir -p "$samples_dir/network/asn" && log "Created $samples_dir/network/asn"
    
    # Verify directories exist before creating schema files
    if [ ! -d "$samples_dir/org" ]; then
        error "Failed to create $samples_dir/org directory"
        return 1
    fi
    
    log "Creating schema files..."
    
    # Create organization schema
    cat > "$samples_dir/org/schema" << EOF
name:           Organization Name:      TEXT:20:M:
org-name:       Organization Name:      TEXT:80:M:
street-address: Street Address:        TEXT:255:O:
city:           City:                   TEXT:80:O:
state:          State/Province:         TEXT:80:O:
postal-code:    Postal Code:            TEXT:20:O:
country-code:   Country Code:           TEXT:2:O:
phone:          Phone Number:           TEXT:40:O:
fax:            Fax Number:             TEXT:40:O:
e-mail:         Email Address:          TEXT:80:O:
EOF

    log "Created organization schema"

    # Create contact schema  
    cat > "$samples_dir/contact/schema" << EOF
name:           Contact Name:           TEXT:20:M:
first-name:     First Name:             TEXT:40:O:
middle-name:    Middle Name:            TEXT:40:O:
last-name:      Last Name:              TEXT:40:M:
organization:   Organization:           TEXT:80:O:
street-address: Street Address:         TEXT:255:O:
city:           City:                   TEXT:80:O:
state:          State/Province:         TEXT:80:O:
postal-code:    Postal Code:            TEXT:20:O:
country-code:   Country Code:           TEXT:2:O:
phone:          Phone Number:           TEXT:40:O:
fax:            Fax Number:             TEXT:40:O:
e-mail:         Email Address:          TEXT:80:M:
EOF

    log "Created contact schema"

    # Create network schema
    cat > "$samples_dir/network/schema" << EOF
name:           Network Name:           TEXT:20:M:
network:        Network Address:        TEXT:80:M:
net-name:       Network Name:           TEXT:80:O:
org-name:       Organization:           TEXT:80:O:
tech-contact:   Technical Contact:      TEXT:80:O:
admin-contact:  Administrative Contact: TEXT:80:O:
created:        Created Date:           TEXT:10:O:
updated:        Updated Date:           TEXT:10:O:
EOF

    log "Created network schema"

    # Set proper ownership
    chown -R "$RWHOIS_USER:$RWHOIS_GROUP" "$samples_dir"/{org,contact,network}
    log "Set ownership for schema directories"
}

# Create schema files
create_schema_files() {
    # Organization schema
    cat > "$RWHOIS_DATA/org/schema" << EOF
name:           Organization Name:      TEXT:20:M:
org-name:       Organization Name:      TEXT:80:M:
street-address: Street Address:        TEXT:255:O:
city:           City:                   TEXT:80:O:
state:          State/Province:         TEXT:80:O:
postal-code:    Postal Code:            TEXT:20:O:
country-code:   Country Code:           TEXT:2:O:
phone:          Phone Number:           TEXT:40:O:
fax:            Fax Number:             TEXT:40:O:
e-mail:         Email Address:          TEXT:80:O:
EOF

    # Contact schema  
    cat > "$RWHOIS_DATA/contact/schema" << EOF
name:           Contact Name:           TEXT:20:M:
first-name:     First Name:             TEXT:40:O:
middle-name:    Middle Name:            TEXT:40:O:
last-name:      Last Name:              TEXT:40:M:
organization:   Organization:           TEXT:80:O:
street-address: Street Address:         TEXT:255:O:
city:           City:                   TEXT:80:O:
state:          State/Province:         TEXT:80:O:
postal-code:    Postal Code:            TEXT:20:O:
country-code:   Country Code:           TEXT:2:O:
phone:          Phone Number:           TEXT:40:O:
fax:            Fax Number:             TEXT:40:O:
e-mail:         Email Address:          TEXT:80:M:
EOF

    # Network schema
    cat > "$RWHOIS_DATA/network/schema" << EOF
name:           Network Name:           TEXT:20:M:
network:        Network Address:        TEXT:80:M:
net-name:       Network Name:           TEXT:80:O:
org-name:       Organization:           TEXT:80:O:
tech-contact:   Technical Contact:      TEXT:80:O:
admin-contact:  Administrative Contact: TEXT:80:O:
created:        Created Date:           TEXT:10:O:
updated:        Updated Date:           TEXT:10:O:
EOF
}

# Get the active data directory
get_data_directory() {
    if [ -d "$RWHOIS_HOME/etc/rwhoisd/samples" ]; then
        echo "$RWHOIS_HOME/etc/rwhoisd/samples"
    else
        echo "$RWHOIS_DATA"
    fi
}

# Organization management functions
add_organization() {
    local org_name="$1"
    local org_display_name="$2"
    local street="$3"
    local city="$4"
    local state="$5"
    local postal="$6"
    local country="$7"
    local phone="$8"
    local email="$9"
    
    log "Adding organization: $org_name"
    
    local active_data_dir=$(get_data_directory)
    local org_file="$active_data_dir/org/$org_name.txt"
    
    # Ensure directory exists
    mkdir -p "$active_data_dir/org"
    
    cat > "$org_file" << EOF
name: $org_name
org-name: $org_display_name
street-address: $street
city: $city
state: $state
postal-code: $postal
country-code: $country
phone: $phone
e-mail: $email
EOF
    
    chown "$RWHOIS_USER:$RWHOIS_GROUP" "$org_file"
    log "Organization $org_name added successfully"
}

update_organization() {
    local org_name="$1"
    local field="$2"
    local value="$3"
    
    local active_data_dir=$(get_data_directory)
    local org_file="$active_data_dir/org/$org_name.txt"
    
    if [[ ! -f "$org_file" ]]; then
        error "Organization $org_name not found"
        return 1
    fi
    
    log "Updating organization $org_name: $field = $value"
    
    # Update the field
    sed -i "s/^$field:.*/$field: $value/" "$org_file"
    
    log "Organization $org_name updated successfully"
}

delete_organization() {
    local org_name="$1"
    local active_data_dir=$(get_data_directory)
    local org_file="$active_data_dir/org/$org_name.txt"
    
    if [[ ! -f "$org_file" ]]; then
        error "Organization $org_name not found"
        return 1
    fi
    
    log "Deleting organization: $org_name"
    rm -f "$org_file"
    log "Organization $org_name deleted successfully"
}

# Contact management functions
add_contact() {
    local contact_name="$1"
    local first_name="$2"
    local last_name="$3"
    local organization="$4"
    local street="$5"
    local city="$6"
    local state="$7"
    local postal="$8"
    local country="$9"
    local phone="${10}"
    local email="${11}"
    
    log "Adding contact: $contact_name"
    
    local contact_file="$RWHOIS_DATA/contact/$contact_name.txt"
    
    cat > "$contact_file" << EOF
name: $contact_name
first-name: $first_name
last-name: $last_name
organization: $organization
street-address: $street
city: $city
state: $state
postal-code: $postal
country-code: $country
phone: $phone
e-mail: $email
EOF
    
    chown "$RWHOIS_USER:$RWHOIS_GROUP" "$contact_file"
    log "Contact $contact_name added successfully"
}

update_contact() {
    local contact_name="$1"
    local field="$2"
    local value="$3"
    
    local contact_file="$RWHOIS_DATA/contact/$contact_name.txt"
    
    if [[ ! -f "$contact_file" ]]; then
        error "Contact $contact_name not found"
        return 1
    fi
    
    log "Updating contact $contact_name: $field = $value"
    
    # Update the field
    sed -i "s/^$field:.*/$field: $value/" "$contact_file"
    
    log "Contact $contact_name updated successfully"
}

delete_contact() {
    local contact_name="$1"
    local contact_file="$RWHOIS_DATA/contact/$contact_name.txt"
    
    if [[ ! -f "$contact_file" ]]; then
        error "Contact $contact_name not found"
        return 1
    fi
    
    log "Deleting contact: $contact_name"
    rm -f "$contact_file"
    log "Contact $contact_name deleted successfully"
}

# Network resource management functions
add_network() {
    local net_name="$1"
    local network="$2"
    local net_display_name="$3"
    local org_name="$4"
    local tech_contact="$5"
    local admin_contact="$6"
    local resource_type="$7"  # ipv4, ipv6, or asn
    
    log "Adding network resource: $net_name ($resource_type)"
    
    local active_data_dir=$(get_data_directory)
    local net_dir="$active_data_dir/network"
    local net_file="$net_dir/$net_name.txt"
    
    # Create subdirectory for resource type if needed
    case "$resource_type" in
        "ipv4")
            mkdir -p "$net_dir/ipv4"
            net_file="$net_dir/ipv4/$net_name.txt"
            ;;
        "ipv6")
            mkdir -p "$net_dir/ipv6"
            net_file="$net_dir/ipv6/$net_name.txt"
            ;;
        "asn")
            mkdir -p "$net_dir/asn"
            net_file="$net_dir/asn/$net_name.txt"
            ;;
    esac
    
    cat > "$net_file" << EOF
name: $net_name
network: $network
net-name: $net_display_name
org-name: $org_name
tech-contact: $tech_contact
admin-contact: $admin_contact
created: $(date +%Y-%m-%d)
updated: $(date +%Y-%m-%d)
EOF
    
    chown "$RWHOIS_USER:$RWHOIS_GROUP" "$net_file"
    log "Network resource $net_name added successfully"
}

update_network() {
    local net_name="$1"
    local field="$2"
    local value="$3"
    local resource_type="$4"
    
    local active_data_dir=$(get_data_directory)
    local net_file
    case "$resource_type" in
        "ipv4") net_file="$active_data_dir/network/ipv4/$net_name.txt" ;;
        "ipv6") net_file="$active_data_dir/network/ipv6/$net_name.txt" ;;
        "asn") net_file="$active_data_dir/network/asn/$net_name.txt" ;;
        *) net_file="$active_data_dir/network/$net_name.txt" ;;
    esac
    
    if [[ ! -f "$net_file" ]]; then
        error "Network resource $net_name not found"
        return 1
    fi
    
    log "Updating network resource $net_name: $field = $value"
    
    # Update the field
    sed -i "s/^$field:.*/$field: $value/" "$net_file"
    sed -i "s/^updated:.*/updated: $(date +%Y-%m-%d)/" "$net_file"
    
    log "Network resource $net_name updated successfully"
}

delete_network() {
    local net_name="$1"
    local resource_type="$2"
    
    local active_data_dir=$(get_data_directory)
    local net_file
    case "$resource_type" in
        "ipv4") net_file="$active_data_dir/network/ipv4/$net_name.txt" ;;
        "ipv6") net_file="$active_data_dir/network/ipv6/$net_name.txt" ;;
        "asn") net_file="$active_data_dir/network/asn/$net_name.txt" ;;
        *) net_file="$active_data_dir/network/$net_name.txt" ;;
    esac
    
    if [[ ! -f "$net_file" ]]; then
        error "Network resource $net_name not found"
        return 1
    fi
    
    log "Deleting network resource: $net_name"
    rm -f "$net_file"
    log "Network resource $net_name deleted successfully"
}

# Rebuild RWHOIS indexes
rebuild_indexes() {
    log "Rebuilding RWHOIS indexes..."
    
    # Check if we're using samples directory
    if [ -d "$RWHOIS_HOME/etc/rwhoisd/samples" ]; then
        ACTIVE_DATA_DIR="$RWHOIS_HOME/etc/rwhoisd/samples"
    else
        ACTIVE_DATA_DIR="$RWHOIS_DATA"
    fi
    
    cd "$ACTIVE_DATA_DIR"
    
    # Build indexes for each data type
    for dir in org contact network network/ipv4 network/ipv6 network/asn; do
        if [[ -d "$dir" ]]; then
            log "Building index for $dir"
            cd "$ACTIVE_DATA_DIR/$dir"
            "$RWHOIS_BIN/rwhois_indexer" -c schema *.txt 2>/dev/null || true
            cd "$ACTIVE_DATA_DIR"
        fi
    done
    
    chown -R "$RWHOIS_USER:$RWHOIS_GROUP" "$ACTIVE_DATA_DIR"
    log "Indexes rebuilt successfully"
}

# Start/Stop/Restart RWHOIS service
start_rwhois() {
    log "Starting RWHOIS server..."
    
    # Verify binary exists
    if [[ ! -f "$RWHOIS_BIN/rwhoisd" ]]; then
        error "RWHOIS binary not found at $RWHOIS_BIN/rwhoisd"
        return 1
    fi
    
    # Check if already running (better detection)
    if pgrep -f "rwhoisd.*$RWHOIS_CONFIG/rwhoisd.conf" > /dev/null; then
        warning "RWHOIS server is already running"
        return 0
    fi
    
    # Validate configuration before starting
    if [[ ! -f "$RWHOIS_CONFIG/rwhoisd.conf" ]]; then
        error "Configuration file not found: $RWHOIS_CONFIG/rwhoisd.conf"
        return 1
    fi
    
    # Enhanced systemd detection
    if [ -d /run/systemd/system ] && pidof systemd &> /dev/null && systemctl --version &> /dev/null 2>&1; then
        if systemctl start rwhois 2>/dev/null; then
            sleep 2
            if systemctl is-active --quiet rwhois 2>/dev/null; then
                log "RWHOIS server started successfully (systemd)"
                return 0
            else
                warning "Systemd start failed, trying manual start..."
            fi
        else
            warning "Systemd start failed, trying manual start..."
        fi
    fi
    
    # Try init script
    if [ -f /etc/init.d/rwhois ]; then
        if /etc/init.d/rwhois start; then
            sleep 2
            if pgrep -f "rwhoisd.*$RWHOIS_CONFIG/rwhoisd.conf" > /dev/null; then
                log "RWHOIS server started successfully (init script)"
                return 0
            else
                warning "Init script start failed, trying manual start..."
            fi
        fi
    fi
    
    # Manual start with better error handling
    log "Starting RWHOIS server manually..."
    
    # Change to the proper directory and start
    cd "$RWHOIS_HOME"
    
    # Start the server with verbose output for debugging
    if sudo -u "$RWHOIS_USER" "$RWHOIS_BIN/rwhoisd" -c "$RWHOIS_CONFIG/rwhoisd.conf" -d 2>&1; then
        log "RWHOIS server started command executed"
    else
        error "Failed to execute RWHOIS server start command"
        return 1
    fi
    
    # Wait and verify it's running
    sleep 3
    
    if pgrep -f "rwhoisd.*$RWHOIS_CONFIG/rwhoisd.conf" > /dev/null; then
        log "RWHOIS server started successfully (manual)"
        
        # Verify it's listening on the port
        if netstat -tlnp 2>/dev/null | grep -q ":$RWHOIS_PORT "; then
            log "RWHOIS server is listening on port $RWHOIS_PORT"
        else
            warning "RWHOIS server may not be listening on port $RWHOIS_PORT"
        fi
        
        return 0
    else
        error "Failed to start RWHOIS server - process not found after startup"
        
        # Try to get more debugging info
        log "Attempting to start with verbose output for debugging..."
        sudo -u "$RWHOIS_USER" "$RWHOIS_BIN/rwhoisd" -c "$RWHOIS_CONFIG/rwhoisd.conf" -d -v || true
        
        return 1
    fi
}

stop_rwhois() {
    log "Stopping RWHOIS server..."
    
    # Enhanced systemd detection
    if [ -d /run/systemd/system ] && pidof systemd &> /dev/null && systemctl --version &> /dev/null 2>&1; then
        if systemctl is-active --quiet rwhois 2>/dev/null; then
            if systemctl stop rwhois 2>/dev/null; then
                log "RWHOIS server stopped (systemd)"
                return 0
            else
                warning "Systemd stop failed, trying manual stop..."
            fi
        fi
    fi
    
    # Try init script
    if [ -f /etc/init.d/rwhois ]; then
        if /etc/init.d/rwhois stop 2>/dev/null; then
            log "RWHOIS server stopped (init script)"
            return 0
        fi
    fi
    
    # Manual stop with better process detection
    local pids=$(pgrep -f "rwhoisd.*$RWHOIS_CONFIG/rwhoisd.conf" 2>/dev/null || true)
    
    if [ -z "$pids" ]; then
        warning "RWHOIS server is not running"
        return 0
    fi
    
    log "Stopping RWHOIS processes: $pids"
    
    # Try graceful stop first
    echo "$pids" | xargs -r kill 2>/dev/null || true
    sleep 2
    
    # Check if still running
    pids=$(pgrep -f "rwhoisd.*$RWHOIS_CONFIG/rwhoisd.conf" 2>/dev/null || true)
    if [ -n "$pids" ]; then
        warning "Force killing RWHOIS processes: $pids"
        echo "$pids" | xargs -r kill -9 2>/dev/null || true
        sleep 1
    fi
    
    # Final verification
    if pgrep -f "rwhoisd.*$RWHOIS_CONFIG/rwhoisd.conf" > /dev/null; then
        error "Failed to stop RWHOIS server"
        return 1
    else
        log "RWHOIS server stopped successfully"
        return 0
    fi
}

restart_rwhois() {
    log "Restarting RWHOIS server..."
    
    # Enhanced systemd detection
    if [ -d /run/systemd/system ] && pidof systemd &> /dev/null && systemctl --version &> /dev/null 2>&1; then
        if systemctl restart rwhois 2>/dev/null; then
            log "RWHOIS server restarted (systemd)"
            return 0
        else
            warning "Systemd restart failed, trying manual restart..."
        fi
    fi
    
    # Try init script
    if [ -f /etc/init.d/rwhois ]; then
        if /etc/init.d/rwhois restart 2>/dev/null; then
            log "RWHOIS server restarted (init script)"
            return 0
        fi
    fi
    
    # Manual restart
    stop_rwhois
    sleep 2
    start_rwhois
}

# Create systemd service file
create_systemd_service() {
    # Enhanced systemd detection
    if [ ! -d /run/systemd/system ] || ! pidof systemd &> /dev/null; then
        warning "Systemd not running or not available, creating traditional init script instead..."
        create_init_script
        return 0
    fi
    
    # Additional check for systemctl functionality
    if ! systemctl --version &> /dev/null 2>&1; then
        warning "Systemctl not functional, creating traditional init script instead..."
        create_init_script
        return 0
    fi
    
    log "Creating systemd service..."
    
    cat > /etc/systemd/system/rwhois.service << EOF
[Unit]
Description=RWHOIS Server
After=network.target

[Service]
Type=forking
User=$RWHOIS_USER
Group=$RWHOIS_GROUP
ExecStart=$RWHOIS_BIN/rwhoisd -c $RWHOIS_CONFIG/rwhoisd.conf -d
ExecReload=/bin/kill -HUP \$MAINPID
PIDFile=$RWHOIS_HOME/rwhoisd.pid
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    if systemctl daemon-reload &> /dev/null && systemctl enable rwhois &> /dev/null; then
        log "Systemd service created and enabled"
    else
        warning "Systemd service creation failed, falling back to init script..."
        create_init_script
    fi
}

# Create traditional init script for non-systemd systems
create_init_script() {
    log "Creating traditional init script..."
    
    cat > /etc/init.d/rwhois << 'EOF'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          rwhois
# Required-Start:    $network $local_fs $remote_fs
# Required-Stop:     $network $local_fs $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: RWHOIS Server
# Description:       RWHOIS (Referral Whois) Server Daemon
### END INIT INFO

DAEMON="rwhoisd"
ROOT_DIR="/usr/local/rwhois"
DAEMON_PATH="$ROOT_DIR/bin/$DAEMON"
CONFIG_FILE="$ROOT_DIR/etc/rwhoisd.conf"
PID_FILE="$ROOT_DIR/rwhoisd.pid"
USER="rwhois"

# Create lock directory if it doesn't exist
LOCK_DIR="/var/lock/subsys"
if [ ! -d "$LOCK_DIR" ]; then
    LOCK_DIR="/var/lock"
fi
LOCK_FILE="$LOCK_DIR/rwhois"

start() {
    # Check if binary exists
    if [ ! -f "$DAEMON_PATH" ]; then
        echo "Error: RWHOIS binary not found at $DAEMON_PATH" >&2
        return 1
    fi
    
    if [ -f $PID_FILE ] && kill -0 $(cat $PID_FILE) 2>/dev/null; then
        echo 'RWHOIS server already running' >&2
        return 1
    fi
    echo 'Starting RWHOIS server...'
    su - $USER -s /bin/bash -c "$DAEMON_PATH -c $CONFIG_FILE -d" && echo 'RWHOIS server started'
    [ -d "$LOCK_DIR" ] && touch $LOCK_FILE
}

stop() {
    if [ ! -f "$PID_FILE" ] || ! kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo 'RWHOIS server not running' >&2
        return 1
    fi
    echo 'Stopping RWHOIS server...'
    kill $(cat $PID_FILE) && rm -f $PID_FILE
    rm -f $LOCK_FILE
    echo 'RWHOIS server stopped'
}

status() {
    if [ -f $PID_FILE ] && kill -0 $(cat $PID_FILE) 2>/dev/null; then
        echo "RWHOIS server is running (PID: $(cat $PID_FILE))"
        return 0
    else
        echo "RWHOIS server is not running"
        return 1
    fi
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    status)
        status
        ;;
    restart)
        stop
        start
        ;;
    *)
        echo "Usage: $0 {start|stop|status|restart}"
        exit 1
esac

exit $?
EOF
    
    chmod +x /etc/init.d/rwhois
    
    # Try to enable the service if update-rc.d or chkconfig is available
    if command -v update-rc.d &> /dev/null; then
        update-rc.d rwhois defaults
        log "Init script installed and enabled with update-rc.d"
    elif command -v chkconfig &> /dev/null; then
        chkconfig --add rwhois
        chkconfig rwhois on
        log "Init script installed and enabled with chkconfig"
    else
        log "Init script created at /etc/init.d/rwhois (manual enabling required)"
    fi
}

# Validate and test RWHOIS installation
validate_installation() {
    log "Validating RWHOIS installation..."
    
    # Check if server is running
    if ! pgrep -f "rwhoisd.*$RWHOIS_CONFIG/rwhoisd.conf" > /dev/null; then
        error "RWHOIS server is not running"
        return 1
    fi
    
    # Check if listening on port
    if ! netstat -tlnp 2>/dev/null | grep -q ":$RWHOIS_PORT "; then
        error "RWHOIS server is not listening on port $RWHOIS_PORT"
        return 1
    fi
    
    # Test basic connectivity
    log "Testing RWHOIS connectivity..."
    if timeout 5 bash -c "echo '-status' | nc localhost $RWHOIS_PORT" >/dev/null 2>&1; then
        log "RWHOIS server is responding to queries"
    else
        warning "RWHOIS server may not be responding properly to queries"
    fi
    
    # Check data object count
    local object_count=$(timeout 5 bash -c "echo -e '-status\n-quit' | nc localhost $RWHOIS_PORT 2>/dev/null" | grep "objects:" | cut -d: -f2 | tr -d ' ' || echo "0")
    
    if [[ "$object_count" =~ ^[0-9]+$ ]] && [[ "$object_count" -gt 0 ]]; then
        log "RWHOIS server has $object_count data objects loaded"
    else
        warning "RWHOIS server has no data objects loaded (objects: $object_count)"
        warning "You may need to add data and rebuild indexes"
    fi
    
    log "RWHOIS validation completed"
}

# Create sample data for testing
create_sample_data() {
    log "Creating sample data for testing..."
    
    local active_data_dir=$(get_data_directory)
    
    # Create sample organization
    mkdir -p "$active_data_dir/org"
    cat > "$active_data_dir/org/SAMPLE-ORG.txt" << EOF
name: SAMPLE-ORG
org-name: Sample Organization
street-address: 123 Sample Street
city: Sample City
state: ST
postal-code: 12345
country-code: US
phone: +1-555-SAMPLE
e-mail: admin@sample.org
EOF
    
    # Create sample contact
    mkdir -p "$active_data_dir/contact"
    cat > "$active_data_dir/contact/SAMPLE-CONTACT.txt" << EOF
name: SAMPLE-CONTACT
first-name: John
last-name: Sample
organization: Sample Organization
street-address: 123 Sample Street
city: Sample City
state: ST
postal-code: 12345
country-code: US
phone: +1-555-SAMPLE
e-mail: john@sample.org
EOF
    
    # Create sample network
    mkdir -p "$active_data_dir/network"
    cat > "$active_data_dir/network/SAMPLE-NET.txt" << EOF
name: SAMPLE-NET
network: 203.0.113.0/24
net-name: Sample Network
org-name: Sample Organization
tech-contact: SAMPLE-CONTACT
admin-contact: SAMPLE-CONTACT
created: $(date +%Y-%m-%d)
updated: $(date +%Y-%m-%d)
EOF
    
    # Set proper ownership
    chown -R "$RWHOIS_USER:$RWHOIS_GROUP" "$active_data_dir"
    
    log "Sample data created successfully"
}

# Display help information
show_help() {
    cat << EOF
RWHOIS Automation Script

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    install                     - Full installation of RWHOIS server (includes cleanup)
    reinstall                   - Clean reinstallation (cleanup + install)
    cleanup                     - Remove existing RWHOIS installation
    validate                    - Validate RWHOIS installation and connectivity
    start                      - Start RWHOIS server
    stop                       - Stop RWHOIS server  
    restart                    - Restart RWHOIS server
    rebuild-indexes            - Rebuild all RWHOIS indexes
    
    add-org NAME DISPLAY_NAME STREET CITY STATE POSTAL COUNTRY PHONE EMAIL
                              - Add a new organization
    update-org NAME FIELD VALUE - Update organization field
    delete-org NAME           - Delete organization
    
    add-contact NAME FIRST LAST ORG STREET CITY STATE POSTAL COUNTRY PHONE EMAIL
                              - Add a new contact
    update-contact NAME FIELD VALUE - Update contact field  
    delete-contact NAME       - Delete contact
    
    add-network NAME NETWORK DISPLAY_NAME ORG_NAME TECH_CONTACT ADMIN_CONTACT TYPE
                              - Add network resource (TYPE: ipv4|ipv6|asn)
    update-network NAME FIELD VALUE TYPE - Update network resource
    delete-network NAME TYPE  - Delete network resource
    
    help                      - Show this help message

Examples:
    $0 install
    $0 reinstall
    $0 cleanup
    $0 validate
    $0 add-org "ORG-001" "Example Corp" "123 Main St" "City" "ST" "12345" "US" "+1-555-0123" "admin@example.com"
    $0 add-contact "TECH-001" "John" "Doe" "Example Corp" "123 Main St" "City" "ST" "12345" "US" "+1-555-0124" "john@example.com"
    $0 add-network "NET-001" "192.168.1.0/24" "Example Network" "Example Corp" "TECH-001" "ADMIN-001" "ipv4"
    $0 restart

EOF
}

# Main function
main() {
    case "$1" in
        "install")
            check_root
            log "Starting RWHOIS installation..."
            cleanup_existing
            install_dependencies
            setup_user_dirs
            install_rwhois
            configure_rwhois
            create_systemd_service
            create_sample_data
            rebuild_indexes
            start_rwhois
            sleep 3
            validate_installation
            log "RWHOIS installation completed successfully!"
            
            # Show service management information
            info "Service Management:"
            if [ -d /run/systemd/system ] && pidof systemd &> /dev/null && systemctl --version &> /dev/null 2>&1; then
                info "  - Start: systemctl start rwhois OR ./rwhois_automation.sh start"
                info "  - Stop:  systemctl stop rwhois OR ./rwhois_automation.sh stop"
                info "  - Status: systemctl status rwhois"
            elif [ -f /etc/init.d/rwhois ]; then
                info "  - Start: /etc/init.d/rwhois start OR ./rwhois_automation.sh start"
                info "  - Stop:  /etc/init.d/rwhois stop OR ./rwhois_automation.sh stop"
                info "  - Status: /etc/init.d/rwhois status"
            else
                info "  - Start: ./rwhois_automation.sh start"
                info "  - Stop:  ./rwhois_automation.sh stop"
                info "  - Restart: ./rwhois_automation.sh restart"
            fi
            info "  - Test: telnet localhost 4321"
            info "  - Query examples:"
            info "    -status                    (check server status)"
            info "    -search org-name Sample    (search organizations)"
            info "    -search contact john       (search contacts)"
            info "    -search network 203.0.113.0  (search networks)"
            ;;
        "cleanup")
            check_root
            cleanup_existing
            ;;
        "reinstall")
            check_root
            log "Performing clean reinstallation..."
            cleanup_existing
            log "Starting fresh RWHOIS installation..."
            install_dependencies
            setup_user_dirs
            install_rwhois
            configure_rwhois
            create_systemd_service
            create_sample_data
            rebuild_indexes
            start_rwhois
            sleep 3
            validate_installation
            log "Clean reinstallation completed successfully!"
            ;;
        "validate")
            validate_installation
            ;;
        "start")
            check_root
            start_rwhois
            ;;
        "stop")
            check_root
            stop_rwhois
            ;;
        "restart")
            check_root
            restart_rwhois
            ;;
        "rebuild-indexes")
            rebuild_indexes
            ;;
        "add-org")
            if [[ $# -ne 10 ]]; then
                error "Invalid arguments for add-org"
                show_help
                exit 1
            fi
            add_organization "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}"
            rebuild_indexes
            ;;
        "update-org")
            if [[ $# -ne 4 ]]; then
                error "Invalid arguments for update-org"
                show_help
                exit 1
            fi
            update_organization "$2" "$3" "$4"
            rebuild_indexes
            ;;
        "delete-org")
            if [[ $# -ne 2 ]]; then
                error "Invalid arguments for delete-org"
                show_help
                exit 1
            fi
            delete_organization "$2"
            rebuild_indexes
            ;;
        "add-contact")
            if [[ $# -ne 12 ]]; then
                error "Invalid arguments for add-contact"
                show_help
                exit 1
            fi
            add_contact "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}"
            rebuild_indexes
            ;;
        "update-contact")
            if [[ $# -ne 4 ]]; then
                error "Invalid arguments for update-contact"
                show_help
                exit 1
            fi
            update_contact "$2" "$3" "$4"
            rebuild_indexes
            ;;
        "delete-contact")
            if [[ $# -ne 2 ]]; then
                error "Invalid arguments for delete-contact"
                show_help
                exit 1
            fi
            delete_contact "$2"
            rebuild_indexes
            ;;
        "add-network")
            if [[ $# -ne 8 ]]; then
                error "Invalid arguments for add-network"
                show_help
                exit 1
            fi
            add_network "$2" "$3" "$4" "$5" "$6" "$7" "$8"
            rebuild_indexes
            ;;
        "update-network")
            if [[ $# -ne 5 ]]; then
                error "Invalid arguments for update-network"
                show_help
                exit 1
            fi
            update_network "$2" "$3" "$4" "$5"
            rebuild_indexes
            ;;
        "delete-network")
            if [[ $# -ne 3 ]]; then
                error "Invalid arguments for delete-network"
                show_help
                exit 1
            fi
            delete_network "$2" "$3"
            rebuild_indexes
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        "")
            error "No command specified"
            show_help
            exit 1
            ;;
        *)
            error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
