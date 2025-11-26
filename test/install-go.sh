#!/bin/bash
# Install Go for building vCluster

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

GO_VERSION="1.23.3"  # Use a recent stable version
GO_ARCH="amd64"      # Change to arm64 if on ARM

echo "=========================================="
echo "Installing Go ${GO_VERSION}"
echo "=========================================="

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    GO_ARCH="amd64"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    GO_ARCH="arm64"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

echo -e "${YELLOW}Architecture detected: ${GO_ARCH}${NC}"

# Download Go
echo -e "${YELLOW}Downloading Go ${GO_VERSION}...${NC}"
cd /tmp
wget -q --show-progress https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz

# Remove old Go installation if exists
if [ -d "/usr/local/go" ]; then
    echo -e "${YELLOW}Removing old Go installation...${NC}"
    sudo rm -rf /usr/local/go
fi

# Extract Go
echo -e "${YELLOW}Installing Go...${NC}"
sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-${GO_ARCH}.tar.gz

# Add to PATH
if ! grep -q "/usr/local/go/bin" ~/.bashrc; then
    echo -e "${YELLOW}Adding Go to PATH...${NC}"
    echo "" >> ~/.bashrc
    echo "# Go language" >> ~/.bashrc
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> ~/.bashrc
fi

# Export for current session
export PATH=$PATH:/usr/local/go/bin

# Verify installation
echo -e "${YELLOW}Verifying installation...${NC}"
/usr/local/go/bin/go version

# Clean up
rm /tmp/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz

echo ""
echo "=========================================="
echo -e "${GREEN}Go installed successfully!${NC}"
echo "=========================================="
echo ""
echo "Go version: $(/usr/local/go/bin/go version)"
echo "Go path: /usr/local/go/bin/go"
echo ""
echo "IMPORTANT: Run this command to update your current shell:"
echo "  export PATH=\$PATH:/usr/local/go/bin"
echo ""
echo "Or start a new shell session."
echo ""
echo "Then you can run:"
echo "  ./build-docker-and-test.sh"
echo ""



