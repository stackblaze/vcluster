#!/bin/bash
# vCluster with External Database Connector - One-liner Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/stackblaze/vcluster/main/install.sh | bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=========================================="
echo "vCluster CLI Installer"
echo "with External Database Connector Support"
echo -e "==========================================${NC}"
echo ""

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case $ARCH in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    *)
        echo -e "${RED}Unsupported architecture: $ARCH${NC}"
        exit 1
        ;;
esac

echo -e "${YELLOW}Detected: $OS/$ARCH${NC}"

# Download URL
GITHUB_REPO="stackblaze/vcluster"
RELEASE_TAG="latest"
BINARY_NAME="vcluster"

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    INSTALL_DIR="/usr/local/bin"
    SUDO=""
else
    INSTALL_DIR="$HOME/.local/bin"
    SUDO="sudo"
    mkdir -p "$INSTALL_DIR"
fi

echo -e "${YELLOW}Installing to: $INSTALL_DIR${NC}"

# Create temporary directory
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

echo -e "${YELLOW}Downloading vCluster CLI...${NC}"

# Download the CLI binary from GitHub releases
# Note: You'll need to create a GitHub release with the binary
if command -v curl &> /dev/null; then
    curl -fsSL -o "$BINARY_NAME" "https://github.com/$GITHUB_REPO/releases/download/$RELEASE_TAG/$BINARY_NAME-$OS-$ARCH"
elif command -v wget &> /dev/null; then
    wget -q -O "$BINARY_NAME" "https://github.com/$GITHUB_REPO/releases/download/$RELEASE_TAG/$BINARY_NAME-$OS-$ARCH"
else
    echo -e "${RED}Error: curl or wget is required${NC}"
    exit 1
fi

# Make it executable
chmod +x "$BINARY_NAME"

# Install
echo -e "${YELLOW}Installing vCluster CLI...${NC}"
if [ "$EUID" -eq 0 ] || [ -w "$INSTALL_DIR" ]; then
    mv "$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
else
    $SUDO mv "$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
fi

# Cleanup
cd -
rm -rf "$TMP_DIR"

# Verify installation
if command -v vcluster &> /dev/null; then
    echo ""
    echo -e "${GREEN}✓ vCluster CLI installed successfully!${NC}"
    echo ""
    vcluster --version
    echo ""
    echo -e "${GREEN}=========================================="
    echo "Quick Start"
    echo -e "==========================================${NC}"
    echo ""
    echo "1. Create a vCluster:"
    echo "   vcluster create my-vcluster --namespace team-x"
    echo ""
    echo "2. With external database (PostgreSQL/MySQL):"
    echo "   vcluster create my-vcluster --namespace team-x \\"
    echo "     --values https://raw.githubusercontent.com/$GITHUB_REPO/main/examples/external-database/connector-postgres-values.yaml"
    echo ""
    echo "3. Connect to your vCluster:"
    echo "   vcluster connect my-vcluster --namespace team-x"
    echo ""
    echo -e "${YELLOW}Documentation: https://github.com/$GITHUB_REPO${NC}"
    echo ""
else
    echo -e "${RED}✗ Installation failed${NC}"
    echo "Please add $INSTALL_DIR to your PATH:"
    echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    exit 1
fi

