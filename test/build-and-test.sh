#!/bin/bash
# Build vCluster from source and test the connector implementation

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "Building vCluster with Connector Changes"
echo "=========================================="

cd /home/linux/vcluster

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo -e "${RED}Error: Go is not installed${NC}"
    echo "Please install Go 1.21+ from https://go.dev/dl/"
    exit 1
fi

echo -e "${YELLOW}Step 1: Checking Go version...${NC}"
go version

echo -e "${YELLOW}Step 2: Downloading dependencies...${NC}"
go mod download
go mod vendor

echo -e "${YELLOW}Step 3: Building vCluster binary...${NC}"
CGO_ENABLED=0 go build -mod vendor -o bin/vcluster cmd/vcluster/main.go

if [ -f bin/vcluster ]; then
    echo -e "${GREEN}✓ vCluster binary built successfully${NC}"
    ls -lh bin/vcluster
else
    echo -e "${RED}✗ Failed to build vCluster binary${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 4: Building vcluster CLI (optional)...${NC}"
CGO_ENABLED=0 go build -mod vendor -o bin/vclusterctl cmd/vclusterctl/main.go

if [ -f bin/vclusterctl ]; then
    echo -e "${GREEN}✓ vclusterctl binary built successfully${NC}"
    ls -lh bin/vclusterctl
else
    echo -e "${YELLOW}⚠ vclusterctl build failed (optional)${NC}"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Build Complete!${NC}"
echo "=========================================="
echo ""
echo "Binaries created:"
echo "  vCluster syncer: bin/vcluster"
echo "  vCluster CLI:    bin/vclusterctl (if built)"
echo ""
echo "Next steps:"
echo "  1. Build Docker image with the new binary"
echo "  2. Deploy to Kubernetes with the custom image"
echo "  3. Test the connector functionality"
echo ""
echo "Quick test command:"
echo "  ./build-docker-and-test.sh"
echo ""



