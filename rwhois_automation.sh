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

# Install dependencies
install_dependencies() {
    log "Installing dependencies..."
    
    # Detect OS
    if [[ -f /etc/redhat-release ]]; then
        # RHEL/CentOS/Fedora
        yum update -y
        yum groupinstall -y "Development Tools"
        yum install -y gcc gcc-c++ make autoconf automake libtool \
                      flex bison openssl-devel zlib-devel wget curl
    elif [[ -f /etc/debian_version ]]; then
        # Debian/Ubuntu
        apt-get update
        apt-get install -y build-essential gcc g++ make autoconf automake libtool \
                          flex bison libssl-dev zlib1g-dev wget curl
    else
        error "Unsupported operating system"
        exit 1
    fi
    
    log "Dependencies installed successfully"
}

# Create RWHOIS user and directories
setup_user_dirs() {
    log "Setting up RWHOIS user and directories..."
    
    # Create user if it doesn't exist
    if ! id "$RWHOIS_USER" &>/dev/null; then
        useradd -r -d "$RWHOIS_HOME" -s /bin/false "$RWHOIS_USER"
        log "Created user: $RWHOIS_USER"
    fi
    
    # Create directories
    mkdir -p "$RWHOIS_HOME"/{bin,etc,data,log}
    mkdir -p "$RWHOIS_DATA"/{org,contact,network}
    mkdir -p "$RWHOIS_LOG"
    
    # Set permissions
    chown -R "$RWHOIS_USER:$RWHOIS_GROUP" "$RWHOIS_HOME"
    chown -R "$RWHOIS_USER:$RWHOIS_GROUP" "$RWHOIS_LOG"
    chmod 755 "$RWHOIS_HOME"
    chmod 755 "$RWHOIS_DATA"
    
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
    
    # Generate configure script if it doesn't exist
    if [[ ! -f "configure" ]]; then
        log "Generating configure script..."
        if [[ -f "configure.ac" ]] || [[ -f "configure.in" ]]; then
            autoreconf -fiv
        else
            error "No configure script or autotools files found"
            exit 1
        fi
    fi
    
    # Configure and compile
    ./configure --prefix="$RWHOIS_HOME"
    make
    make install
    
    # Copy binaries
    cp tools/rwhois_indexer "$RWHOIS_BIN/"
    chmod +x "$RWHOIS_BIN"/*
    
    # Clean up
    cd /
    rm -rf /tmp/rwhois*
    
    log "RWHOIS installed successfully"
}

# Configure RWHOIS
configure_rwhois() {
    log "Configuring RWHOIS..."
    
    # Create main configuration file
    cat > "$RWHOIS_CONFIG/rwhoisd.conf" << EOF
# RWHOIS Server Configuration
userid: $RWHOIS_USER
server-contact: admin@example.com
default-ttl: 86400
max-hits: 256
listen: 0.0.0.0:$RWHOIS_PORT
pid-file: $RWHOIS_HOME/rwhoisd.pid
register-soa: ON
root-dir: $RWHOIS_DATA
schema-version: 1.5
security-allow: 127.0.0.1/32
security-allow: 0.0.0.0/0
default-auth-area: .
authority-area: example.com
EOF

    # Create schema files
    create_schema_files
    
    # Create index configuration
    cat > "$RWHOIS_CONFIG/rwhoisd.allow" << EOF
# RWHOIS Access Control
127.0.0.1/32
0.0.0.0/0
EOF

    cat > "$RWHOIS_CONFIG/rwhoisd.deny" << EOF
# RWHOIS Deny List
# Add IP addresses or networks to deny access
EOF

    # Set permissions
    chown -R "$RWHOIS_USER:$RWHOIS_GROUP" "$RWHOIS_CONFIG"
    
    log "RWHOIS configuration completed"
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
    
    local org_file="$RWHOIS_DATA/org/$org_name.txt"
    
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
    
    local org_file="$RWHOIS_DATA/org/$org_name.txt"
    
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
    local org_file="$RWHOIS_DATA/org/$org_name.txt"
    
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
    
    local net_dir="$RWHOIS_DATA/network"
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
    
    local net_file
    case "$resource_type" in
        "ipv4") net_file="$RWHOIS_DATA/network/ipv4/$net_name.txt" ;;
        "ipv6") net_file="$RWHOIS_DATA/network/ipv6/$net_name.txt" ;;
        "asn") net_file="$RWHOIS_DATA/network/asn/$net_name.txt" ;;
        *) net_file="$RWHOIS_DATA/network/$net_name.txt" ;;
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
    
    local net_file
    case "$resource_type" in
        "ipv4") net_file="$RWHOIS_DATA/network/ipv4/$net_name.txt" ;;
        "ipv6") net_file="$RWHOIS_DATA/network/ipv6/$net_name.txt" ;;
        "asn") net_file="$RWHOIS_DATA/network/asn/$net_name.txt" ;;
        *) net_file="$RWHOIS_DATA/network/$net_name.txt" ;;
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
    
    cd "$RWHOIS_DATA"
    
    # Build indexes for each data type
    for dir in org contact network network/ipv4 network/ipv6 network/asn; do
        if [[ -d "$dir" ]]; then
            log "Building index for $dir"
            cd "$RWHOIS_DATA/$dir"
            "$RWHOIS_BIN/rwhois_indexer" -c schema *.txt 2>/dev/null || true
            cd "$RWHOIS_DATA"
        fi
    done
    
    chown -R "$RWHOIS_USER:$RWHOIS_GROUP" "$RWHOIS_DATA"
    log "Indexes rebuilt successfully"
}

# Start/Stop/Restart RWHOIS service
start_rwhois() {
    log "Starting RWHOIS server..."
    
    if pgrep -f rwhoisd > /dev/null; then
        warning "RWHOIS server is already running"
        return 0
    fi
    
    su - "$RWHOIS_USER" -s /bin/bash -c \
        "$RWHOIS_BIN/rwhoisd -c $RWHOIS_CONFIG/rwhoisd.conf -f $RWHOIS_DATA" &
    
    sleep 2
    
    if pgrep -f rwhoisd > /dev/null; then
        log "RWHOIS server started successfully"
    else
        error "Failed to start RWHOIS server"
        return 1
    fi
}

stop_rwhois() {
    log "Stopping RWHOIS server..."
    
    if ! pgrep -f rwhoisd > /dev/null; then
        warning "RWHOIS server is not running"
        return 0
    fi
    
    pkill -f rwhoisd
    sleep 2
    
    if pgrep -f rwhoisd > /dev/null; then
        warning "Force killing RWHOIS server..."
        pkill -9 -f rwhoisd
    fi
    
    log "RWHOIS server stopped"
}

restart_rwhois() {
    stop_rwhois
    sleep 1
    start_rwhois
}

# Create systemd service file
create_systemd_service() {
    log "Creating systemd service..."
    
    cat > /etc/systemd/system/rwhois.service << EOF
[Unit]
Description=RWHOIS Server
After=network.target

[Service]
Type=forking
User=$RWHOIS_USER
Group=$RWHOIS_GROUP
ExecStart=$RWHOIS_BIN/rwhoisd -c $RWHOIS_CONFIG/rwhoisd.conf -f $RWHOIS_DATA
ExecReload=/bin/kill -HUP \$MAINPID
PIDFile=$RWHOIS_HOME/rwhoisd.pid
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable rwhois
    
    log "Systemd service created and enabled"
}

# Display help information
show_help() {
    cat << EOF
RWHOIS Automation Script

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    install                     - Full installation of RWHOIS server
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
            install_dependencies
            setup_user_dirs
            install_rwhois
            configure_rwhois
            create_systemd_service
            rebuild_indexes
            start_rwhois
            log "RWHOIS installation completed successfully!"
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
