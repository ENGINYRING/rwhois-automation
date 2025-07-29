[![ENGINYRING](https://cdn.enginyring.com/img/logo_dark.png)](https://www.enginyring.com)

# RWHOIS Automation Script

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Version](https://img.shields.io/badge/Version-1.0-blue.svg)](https://github.com/ENGINYRING/rwhois-automation)

A comprehensive bash script that fully automates the installation, configuration, and management of RWHOIS (Referral Whois) servers. This script streamlines the entire process from initial setup to ongoing database management.

## 🚀 Features

### **Complete Automation**
- **Dependency Installation** - Automatically installs all required packages and build tools
- **RWHOIS Installation** - Downloads, compiles, and installs RWHOIS server from source  
- **System Configuration** - Sets up users, directories, permissions, and systemd services
- **Database Management** - Full CRUD operations for all RWHOIS data types

### **Organization Management**
- ✅ Add new organizations with complete contact information
- ✅ Update existing organization details  
- ✅ Delete organizations from the database
- ✅ Automatic validation and error handling

### **Contact Management** 
- ✅ Add contacts with full personal and organizational details
- ✅ Modify existing contact information
- ✅ Remove contacts from the system
- ✅ Link contacts to organizations

### **Network Resource Management**
- 🌐 **IPv4 Networks** - Manage IPv4 address allocations and subnets
- 🌐 **IPv6 Networks** - Handle IPv6 address blocks and prefixes
- 🌐 **ASN Resources** - Manage Autonomous System Numbers
- 🔄 **Full CRUD Operations** - Add, update, delete for all resource types

### **Service Management**
- 🔧 Start/stop/restart RWHOIS server
- 🔍 Automatic index rebuilding after data changes
- 📊 Systemd integration with monitoring and auto-restart
- 📝 Comprehensive logging with colored output

## 📋 Requirements

### **Supported Operating Systems**
- Red Hat Enterprise Linux (RHEL) 7+
- CentOS 7+
- Fedora 25+
- Ubuntu 16.04+
- Debian 9+

### **System Requirements**
- Root access for installation
- Minimum 512MB RAM
- 100MB available disk space
- Internet connection for downloading RWHOIS source

### **Dependencies** 
The script automatically installs these dependencies:
- GCC compiler and build tools
- Make, autoconf, automake, libtool
- Flex and Bison parsers
- OpenSSL development libraries
- Zlib compression library

## 🛠️ Installation

### **Quick Start**
```bash
# Clone the repository
git clone https://github.com/ENGINYRING/rwhois-automation.git
cd rwhois-automation

# Make the script executable
chmod +x rwhois_automation.sh

# Run full installation (requires root)
sudo ./rwhois_automation.sh install
```

### **Manual Installation Steps**
If you prefer to run individual steps:

```bash
# Install dependencies only
sudo ./rwhois_automation.sh install-deps

# Setup user and directories
sudo ./rwhois_automation.sh setup-dirs

# Install RWHOIS server
sudo ./rwhois_automation.sh install-rwhois

# Configure server
sudo ./rwhois_automation.sh configure

# Start server
sudo ./rwhois_automation.sh start
```

## 📖 Usage

### **Command Syntax**
```bash
./rwhois_automation.sh [COMMAND] [OPTIONS]
```

### **Organization Management**

#### Add Organization
```bash
./rwhois_automation.sh add-org \
    "ORG-001" \
    "Example Corporation" \
    "123 Business Ave" \
    "San Francisco" \
    "CA" \
    "94105" \
    "US" \
    "+1-555-123-4567" \
    "admin@example.com"
```

#### Update Organization
```bash
# Update organization phone number
./rwhois_automation.sh update-org "ORG-001" "phone" "+1-555-987-6543"

# Update organization email
./rwhois_automation.sh update-org "ORG-001" "e-mail" "newadmin@example.com"
```

#### Delete Organization
```bash
./rwhois_automation.sh delete-org "ORG-001"
```

### **Contact Management**

#### Add Contact
```bash
./rwhois_automation.sh add-contact \
    "TECH-001" \
    "John" \
    "Doe" \
    "Example Corporation" \
    "456 Tech Street" \
    "San Francisco" \
    "CA" \
    "94107" \
    "US" \
    "+1-555-234-5678" \
    "john.doe@example.com"
```

#### Update Contact
```bash
# Update contact email
./rwhois_automation.sh update-contact "TECH-001" "e-mail" "j.doe@example.com"

# Update contact phone
./rwhois_automation.sh update-contact "TECH-001" "phone" "+1-555-345-6789"
```

#### Delete Contact
```bash
./rwhois_automation.sh delete-contact "TECH-001"
```

### **Network Resource Management**

#### Add IPv4 Network
```bash
./rwhois_automation.sh add-network \
    "NET-IPV4-001" \
    "192.168.1.0/24" \
    "Corporate LAN" \
    "Example Corporation" \
    "TECH-001" \
    "ADMIN-001" \
    "ipv4"
```

#### Add IPv6 Network
```bash
./rwhois_automation.sh add-network \
    "NET-IPV6-001" \
    "2001:db8::/32" \
    "IPv6 Corporate Network" \
    "Example Corporation" \
    "TECH-001" \
    "ADMIN-001" \
    "ipv6"
```

#### Add ASN Resource
```bash
./rwhois_automation.sh add-network \
    "ASN-001" \
    "AS65001" \
    "Example Corporation ASN" \
    "Example Corporation" \
    "TECH-001" \
    "ADMIN-001" \
    "asn"
```

#### Update Network Resource
```bash
# Update network description
./rwhois_automation.sh update-network "NET-IPV4-001" "net-name" "Updated LAN Description" "ipv4"

# Update technical contact
./rwhois_automation.sh update-network "NET-IPV4-001" "tech-contact" "TECH-002" "ipv4"
```

#### Delete Network Resource
```bash
./rwhois_automation.sh delete-network "NET-IPV4-001" "ipv4"
./rwhois_automation.sh delete-network "NET-IPV6-001" "ipv6"
./rwhois_automation.sh delete-network "ASN-001" "asn"
```

### **Service Management**

#### Start/Stop/Restart Service
```bash
# Start RWHOIS server
./rwhois_automation.sh start

# Stop RWHOIS server
./rwhois_automation.sh stop

# Restart RWHOIS server
./rwhois_automation.sh restart

# Check service status
systemctl status rwhois
```

#### Rebuild Indexes
```bash
# Rebuild all database indexes
./rwhois_automation.sh rebuild-indexes
```

### **Help and Documentation**
```bash
# Display help information
./rwhois_automation.sh help
```

## ⚙️ Configuration

### **Default Configuration**
The script uses the following default settings:

| Setting | Value | Description |
|---------|-------|-------------|
| RWHOIS User | `rwhois` | System user for running the service |
| Installation Path | `/usr/local/rwhois` | Base installation directory |
| Data Directory | `/usr/local/rwhois/data` | Database storage location |
| Config Directory | `/usr/local/rwhois/etc` | Configuration files |
| Log Directory | `/var/log/rwhois` | Log file location |
| Service Port | `4321` | Default RWHOIS protocol port |
| RWHOIS Version | `1.5.9.6` | Version to download and install |

### **Customization**
You can modify these settings by editing the variables at the top of the script:

```bash
# Configuration variables
RWHOIS_USER="rwhois"
RWHOIS_GROUP="rwhois"  
RWHOIS_HOME="/usr/local/rwhois"
RWHOIS_PORT="4321"
RWHOIS_VERSION="1.5.9.6"
```

### **Directory Structure**
After installation, the following directory structure is created:

```
/usr/local/rwhois/
├── bin/                    # Executable binaries
├── etc/                    # Configuration files
├── data/                   # Database files
│   ├── org/               # Organization data
│   ├── contact/           # Contact data
│   └── network/           # Network resources
│       ├── ipv4/          # IPv4 networks
│       ├── ipv6/          # IPv6 networks
│       └── asn/           # ASN resources
└── log/                   # Log files
```

## 🔍 Testing

### **Verify Installation**
```bash
# Check if RWHOIS service is running
systemctl status rwhois

# Test RWHOIS queries
telnet localhost 4321
```

### **Query Examples**
Once connected via telnet:
```
# Search for organization
-search org-name Example

# Search for network
-search network 192.168.1.0

# Search for contact  
-search contact john

# Display server information
-info

# Quit session
-quit
```

## 🐛 Troubleshooting

### **Common Issues**

#### Installation Fails
```bash
# Check if running as root
whoami

# Verify internet connectivity
ping -c 3 github.com

# Check available disk space
df -h /usr/local
```

#### Service Won't Start
```bash
# Check configuration syntax
./rwhois_automation.sh stop
./rwhois_automation.sh start

# View service logs
journalctl -u rwhois -f

# Check port availability
netstat -tlnp | grep 4321
```

#### Database Issues
```bash
# Rebuild all indexes
./rwhois_automation.sh rebuild-indexes

# Verify file permissions
ls -la /usr/local/rwhois/data/

# Check data file format
head /usr/local/rwhois/data/org/*.txt
```

### **Log Locations**
- Service logs: `journalctl -u rwhois`
- Application logs: `/var/log/rwhois/`
- Installation logs: Script outputs to console

## 🤝 Contributing

We welcome contributions! Please follow these guidelines:

### **How to Contribute**
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests if applicable
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### **Code Style**
- Follow existing bash scripting conventions
- Add comments for complex logic
- Use meaningful variable names
- Include error handling for new functions

### **Testing**
Please test your changes on:
- At least one RHEL-based system (CentOS/RHEL/Fedora)
- At least one Debian-based system (Ubuntu/Debian)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👤 Author

**ENGINYRING**

- GitHub: [@ENGINYRING](https://github.com/ENGINYRING)
- Email: contact@enginyring.com

## 🙏 Acknowledgments

- [ARIN](https://www.arin.net/) for the original RWHOIS implementation
- The open-source community for continuous improvements
- Contributors who help maintain and improve this project

## 📈 Version History

- **v1.0.0** - Initial release with full automation capabilities
  - Complete installation automation
  - CRUD operations for all data types
  - Systemd service integration
  - Comprehensive error handling and logging

## 🔗 Related Resources

- [RWHOIS Protocol Specification](https://tools.ietf.org/html/rfc2167)
- [ARIN RWHOIS Documentation](https://www.arin.net/resources/whoisrws/rwhois/)
- [Bash Scripting Guide](https://www.gnu.org/software/bash/manual/)

---

**⭐ If this project helped you, please consider giving it a star on GitHub!**
