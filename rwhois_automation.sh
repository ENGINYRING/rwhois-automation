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
    
    # Verify binary exists
    if [[ ! -f "$RWHOIS_BIN/rwhoisd" ]]; then
        error "RWHOIS binary not found at $RWHOIS_BIN/rwhoisd"
        return 1
    fi
    
    # Enhanced systemd detection
    if [ -d /run/systemd/system ] && pidof systemd &> /dev/null && systemctl --version &> /dev/null 2>&1; then
        if systemctl is-active --quiet rwhois 2>/dev/null; then
            warning "RWHOIS server is already running"
            return 0
        fi
        if systemctl start rwhois 2>/dev/null; then
            log "RWHOIS server started successfully (systemd)"
            return 0
        else
            warning "Systemd start failed, trying manual start..."
        fi
    fi
    
    # Try init script
    if [ -f /etc/init.d/rwhois ]; then
        /etc/init.d/rwhois start
        return $?
    fi
    
    # Manual start
    if pgrep -f rwhoisd > /dev/null; then
        warning "RWHOIS server is already running"
        return 0
    fi
    
    su - "$RWHOIS_USER" -s /bin/bash -c \
        "$RWHOIS_BIN/rwhoisd -c $RWHOIS_CONFIG/rwhoisd.conf -f $RWHOIS_DATA" &
    
    sleep 2
    
    if pgrep -f rwhoisd > /dev/null; then
        log "RWHOIS server started successfully (manual)"
    else
        error "Failed to start RWHOIS server"
        return 1
    fi
}

stop_rwhois() {
    log "Stopping RWHOIS server..."
    
    # Enhanced systemd detection
    if [ -d /run/systemd/system ] && pidof systemd &> /dev/null && systemctl --version &> /dev/null 2>&1; then
        if ! systemctl is-active --quiet rwhois 2>/dev/null; then
            warning "RWHOIS server is not running (systemd)"
        else
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
        /etc/init.d/rwhois stop
        return $?
    fi
    
    # Manual stop
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
    
    log "RWHOIS server stopped (manual)"
}

restart_rwhois() {
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
        /etc/init.d/rwhois restart
        return $?
    fi
    
    # Manual restart
    stop_rwhois
    sleep 1
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
ExecStart=$RWHOIS_BIN/rwhoisd -c $RWHOIS_CONFIG/rwhoisd.conf -f $RWHOIS_DATA
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
DATA_DIR="$ROOT_DIR/data"
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
    su - $USER -s /bin/bash -c "$DAEMON_PATH -c $CONFIG_FILE -f $DATA_DIR" && echo 'RWHOIS server started'
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
