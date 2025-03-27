#!/bin/bash
# install.sh - Installer for msync.sh (Multi-Host Synchronization Tool)
# Version: 1.0.0

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
msync.sh_VERSION="1.5.0"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/msync"
REPO_URL="https://raw.githubusercontent.com/Harsh-2002/msync/main"

# Print banner
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  msync.sh Installer (v${msync.sh_VERSION})${NC}"
echo -e "${BLUE}  Multi-Host Synchronization Tool${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo

# Check if running with sudo or as root
check_root() {
    if [[ $EUID -ne 0 && ! -w "$INSTALL_DIR" ]]; then
        echo -e "${YELLOW}This script needs to install msync.sh to $INSTALL_DIR, which requires sudo access.${NC}"
        echo -e "You can either:"
        echo -e "  1. Run this script with sudo"
        echo -e "  2. Run this script again as root"
        echo -e "  3. Specify a different installation directory using INSTALL_DIR=path ./install.sh"
        exit 1
    fi
}

# Check system requirements
check_system_requirements() {
    echo -e "${BLUE}Checking system requirements...${NC}"
    
    # Check for curl or wget
    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl"
        echo -e "✓ curl found"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget"
        echo -e "✓ wget found"
    else
        echo -e "${RED}✗ Neither curl nor wget found. Please install one of them.${NC}"
        exit 1
    fi
    
    # Check for bash
    if command -v bash >/dev/null 2>&1; then
        echo -e "✓ bash found"
    else
        echo -e "${RED}✗ bash not found. msync.sh requires bash to be installed.${NC}"
        exit 1
    fi
    
    echo
}

# Detect package manager
detect_package_manager() {
    echo -e "${BLUE}Detecting package manager...${NC}"
    
    if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt-get"
        INSTALL_CMD="apt-get install -y"
        echo -e "✓ apt package manager detected"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
        INSTALL_CMD="dnf install -y"
        echo -e "✓ dnf package manager detected"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
        INSTALL_CMD="yum install -y"
        echo -e "✓ yum package manager detected"
    elif command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
        INSTALL_CMD="apk add"
        echo -e "✓ apk package manager detected"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
        INSTALL_CMD="pacman -S --noconfirm"
        echo -e "✓ pacman package manager detected"
    elif command -v brew >/dev/null 2>&1; then
        PKG_MANAGER="brew"
        INSTALL_CMD="brew install"
        echo -e "✓ brew package manager detected"
    elif command -v zypper >/dev/null 2>&1; then
        PKG_MANAGER="zypper"
        INSTALL_CMD="zypper install -y"
        echo -e "✓ zypper package manager detected"
    else
        PKG_MANAGER="unknown"
        INSTALL_CMD=""
        echo -e "${YELLOW}! No supported package manager found. Dependencies will not be installed automatically.${NC}"
    fi
    
    echo
}

# Function to install dependencies if needed
install_dependencies() {
    echo -e "${BLUE}Checking for required dependencies...${NC}"
    
    local need_rsync=0
    local need_ssh=0
    local ssh_pkg="openssh-client"
    
    # Check for rsync
    if ! command -v rsync >/dev/null 2>&1; then
        echo -e "${YELLOW}! rsync not found${NC}"
        need_rsync=1
    else
        echo -e "✓ rsync found"
    fi
    
    # Check for ssh
    if ! command -v ssh >/dev/null 2>&1; then
        echo -e "${YELLOW}! ssh not found${NC}"
        need_ssh=1
        
        # Set the right SSH package name based on package manager
        if [ "$PKG_MANAGER" = "dnf" ] || [ "$PKG_MANAGER" = "yum" ]; then
            ssh_pkg="openssh-clients"
        elif [ "$PKG_MANAGER" = "pacman" ] || [ "$PKG_MANAGER" = "apk" ] || [ "$PKG_MANAGER" = "brew" ]; then
            ssh_pkg="openssh"
        fi
    else
        echo -e "✓ ssh found"
    fi
    
    # Skip if everything is already installed
    if [ $need_rsync -eq 0 ] && [ $need_ssh -eq 0 ]; then
        echo -e "✓ All dependencies are installed"
        return 0
    fi
    
    # Skip if package manager is unknown
    if [ "$PKG_MANAGER" = "unknown" ]; then
        echo -e "${YELLOW}! Cannot install dependencies automatically. Please install them manually:${NC}"
        [ $need_rsync -eq 1 ] && echo -e "  - rsync"
        [ $need_ssh -eq 1 ] && echo -e "  - ssh"
        echo
        read -r -p "Continue installation without these dependencies? (y/n): " choice
        if [ "$choice" != "y" ] && [ "$choice" != "Y" ]; then
            echo -e "${RED}Installation aborted.${NC}"
            exit 1
        fi
        return 0
    fi
    
    # Install missing packages
    echo -e "${BLUE}Installing missing dependencies...${NC}"
    
    # Use sudo only if not running as root
    local sudo_cmd=""
    if [ "$EUID" -ne 0 ]; then
        sudo_cmd="sudo"
    fi
    
    if [ $need_rsync -eq 1 ]; then
        echo -e "Installing rsync..."
        if ! $sudo_cmd "$INSTALL_CMD" rsync; then
            echo -e "${RED}Failed to install rsync.${NC}"
            echo -e "Please install it manually and run this script again."
            exit 1
        fi
    fi
    
    if [ $need_ssh -eq 1 ]; then
        echo -e "Installing SSH ($ssh_pkg)..."
        if ! $sudo_cmd "$INSTALL_CMD" "$ssh_pkg"; then
            echo -e "${RED}Failed to install SSH.${NC}"
            echo -e "Please install it manually and run this script again."
            exit 1
        fi
    fi
    
    echo -e "${GREEN}✓ Dependencies installed successfully${NC}"
    echo
}

# Download the script
download_script() {
    echo -e "${BLUE}Downloading msync.sh...${NC}"
    
    # Create a temporary directory
    TMP_DIR=$(mktemp -d)
    if [ ! -d "$TMP_DIR" ]; then
        echo -e "${RED}Failed to create temporary directory.${NC}"
        exit 1
    fi
    
    # Download the script
    if [ "$DOWNLOADER" = "curl" ]; then
        if ! curl -sL "$REPO_URL/msync.sh" -o "$TMP_DIR/msync.sh"; then
            echo -e "${RED}Failed to download msync.sh using curl.${NC}"
            rm -rf "$TMP_DIR"
            exit 1
        fi
    else
        if ! wget -q "$REPO_URL/msync.sh" -O "$TMP_DIR/msync.sh"; then
            echo -e "${RED}Failed to download msync.sh using wget.${NC}"
            rm -rf "$TMP_DIR"
            exit 1
        fi
    fi
    
    # Verify download
    if [ ! -s "$TMP_DIR/msync.sh" ]; then
        echo -e "${RED}Downloaded file is empty or does not exist.${NC}"
        rm -rf "$TMP_DIR"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Download complete${NC}"
    echo
    TEMP_SCRIPT="$TMP_DIR/msync.sh"
}

# Install the script
install_script() {
    echo -e "${BLUE}Installing msync.sh to $INSTALL_DIR...${NC}"
    
    # Create installation directory if it doesn't exist
    if [ ! -d "$INSTALL_DIR" ]; then
        local sudo_cmd=""
        [ "$EUID" -ne 0 ] && sudo_cmd="sudo"
        
        if ! $sudo_cmd mkdir -p "$INSTALL_DIR"; then
            echo -e "${RED}Failed to create installation directory $INSTALL_DIR${NC}"
            rm -rf "$TMP_DIR"
            exit 1
        fi
    fi
    
    # Make the script executable
    chmod +x "$TEMP_SCRIPT"
    
    # Copy to installation directory
    local sudo_cmd=""
    if [ "$EUID" -ne 0 ] && [ ! -w "$INSTALL_DIR" ]; then
        sudo_cmd="sudo"
    fi
    
    if ! $sudo_cmd cp "$TEMP_SCRIPT" "$INSTALL_DIR/msync.sh"; then
        echo -e "${RED}Failed to copy msync.sh to $INSTALL_DIR${NC}"
        rm -rf "$TMP_DIR"
        exit 1
    fi
    
    # Clean up
    rm -rf "$TMP_DIR"
    
    echo -e "${GREEN}✓ msync.sh installed successfully to $INSTALL_DIR/msync.sh${NC}"
    echo
}

# Create configuration directory
setup_config() {
    echo -e "${BLUE}Setting up configuration...${NC}"
    
    # Create config directory if it doesn't exist
    if [ ! -d "$CONFIG_DIR" ]; then
        if ! mkdir -p "$CONFIG_DIR"; then
            echo -e "${YELLOW}Warning: Failed to create config directory $CONFIG_DIR${NC}"
            echo -e "You might need to create it manually for host groups to work."
        else
            echo -e "✓ Configuration directory created: $CONFIG_DIR"
        fi
    else
        echo -e "✓ Configuration directory already exists"
    fi
    
    echo
}

# Final instructions
show_final_instructions() {
    echo -e "${GREEN}─────────────────────────────────────────────────${NC}"
    echo -e "${GREEN}  msync.sh has been successfully installed! 🚀${NC}"
    echo -e "${GREEN}─────────────────────────────────────────────────${NC}"
    echo
    echo -e "Version: ${msync_VERSION}"
    echo -e "Location: ${INSTALL_DIR}/msync"
    echo -e "Config: ${CONFIG_DIR}"
    echo
    echo -e "${BLUE}Test your installation:${NC}"
    echo -e "  msync--version"
    echo
    echo -e "${BLUE}Get help:${NC}"
    echo -e "  msync --help"
    echo
    echo -e "${BLUE}Create your first host group:${NC}"
    echo -e "  msync --create-group myservers server1,server2,server3"
    echo
    echo -e "${BLUE}Start in interactive mode:${NC}"
    echo -e "  msync"
    echo
    
    # Check if directory is in PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo -e "${YELLOW}Note: $INSTALL_DIR is not in your PATH.${NC}"
        echo -e "You might need to:"
        echo -e "  1. Add it to your PATH, or"
        echo -e "  2. Use the full path when running msync: $INSTALL_DIR/msync"
        echo
    fi
}

# Main installation process
main() {
    # Parse command-line arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-deps)
                SKIP_DEPS=1
                shift
                ;;
            --dir=*)
                INSTALL_DIR="${1#*=}"
                shift
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                echo "Usage: ./install.sh [--no-deps] [--dir=/path/to/install]"
                exit 1
                ;;
        esac
    done
    
    # Start installation
    check_root
    check_system_requirements
    
    if [ -z "$SKIP_DEPS" ]; then
        detect_package_manager
        install_dependencies
    fi
    
    download_script
    install_script
    setup_config
    show_final_instructions
}

# Start installation
main "$@"
