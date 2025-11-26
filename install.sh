#!/bin/bash
# vCluster with External Database Connector - One-line Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/stackblaze/vcluster/main/install.sh | bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=========================================="
echo "vCluster Installer (with DB Connector)"
echo -e "==========================================${NC}"
echo ""

# Detect OS and Architecture
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

case $OS in
    linux)
        PLATFORM="linux"
        ;;
    darwin)
        PLATFORM="darwin"
        ;;
    *)
        echo -e "${RED}Unsupported OS: $OS${NC}"
        exit 1
        ;;
esac

BINARY_NAME="vcluster-${PLATFORM}-${ARCH}"
GITHUB_REPO="stackblaze/vcluster"
INSTALL_DIR="/usr/local/bin"
BINARY_PATH="${INSTALL_DIR}/vcluster"

echo -e "${YELLOW}Detected platform: ${PLATFORM}-${ARCH}${NC}"
echo ""

# Get latest release
echo "Fetching latest release..."
LATEST_RELEASE=$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_RELEASE" ]; then
    echo -e "${YELLOW}No release found, using main branch${NC}"
    DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/raw/main/release/${BINARY_NAME}"
else
    echo -e "${GREEN}Latest release: ${LATEST_RELEASE}${NC}"
    DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${LATEST_RELEASE}/${BINARY_NAME}"
fi

echo ""
echo "Downloading vCluster CLI..."
echo "URL: ${DOWNLOAD_URL}"

# Download to temp file
TMP_FILE=$(mktemp)
if ! curl -fsSL "${DOWNLOAD_URL}" -o "${TMP_FILE}"; then
    echo -e "${RED}Failed to download binary${NC}"
    rm -f "${TMP_FILE}"
    exit 1
fi

# Make executable
chmod +x "${TMP_FILE}"

# Check if we need sudo
if [ -w "${INSTALL_DIR}" ]; then
    mv "${TMP_FILE}" "${BINARY_PATH}"
else
    echo -e "${YELLOW}Installing to ${INSTALL_DIR} requires sudo${NC}"
    sudo mv "${TMP_FILE}" "${BINARY_PATH}"
fi

echo ""
echo -e "${GREEN}✓ vCluster CLI installed successfully!${NC}"
echo ""

# Verify installation
if command -v vcluster &> /dev/null; then
    VERSION=$(vcluster --version 2>&1 || echo "unknown")
    echo -e "${GREEN}Installed version: ${VERSION}${NC}"
else
    echo -e "${YELLOW}Warning: vcluster command not found in PATH${NC}"
    echo "You may need to add ${INSTALL_DIR} to your PATH"
fi

echo ""
echo -e "${GREEN}=========================================="
echo "Installation Complete!"
echo -e "==========================================${NC}"
echo ""
echo "Features included:"
echo "  ✓ External database connector (PostgreSQL/MySQL)"
echo "  ✓ Automatic database provisioning"
echo "  ✓ Embedded chart with connector support"
echo ""
echo "Quick start:"
echo ""
echo "  # Create a vCluster with external database"
echo "  vcluster create my-vcluster \\"
echo "    --namespace vcluster \\"
echo "    --values connector-values.yaml"
echo ""
echo "Documentation:"
echo "  https://github.com/${GITHUB_REPO}"
echo ""

