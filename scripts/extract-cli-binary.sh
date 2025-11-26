#!/bin/bash
# Extract vCluster CLI binary from Docker image for GitHub releases

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Extracting vCluster CLI binaries from Docker image${NC}"

# Create release directory
RELEASE_DIR="$(pwd)/release"
mkdir -p "$RELEASE_DIR"

# Docker image
IMAGE="vcluster-cli:custom"

echo -e "${YELLOW}Extracting Linux AMD64 binary...${NC}"
docker create --name vcluster-cli-extract "$IMAGE"
docker cp vcluster-cli-extract:/usr/local/bin/vcluster "$RELEASE_DIR/vcluster-linux-amd64"
docker rm vcluster-cli-extract

chmod +x "$RELEASE_DIR/vcluster-linux-amd64"

echo -e "${GREEN}✓ Binary extracted to: $RELEASE_DIR/vcluster-linux-amd64${NC}"
echo ""
echo "File info:"
ls -lh "$RELEASE_DIR/vcluster-linux-amd64"
echo ""
echo "To create a GitHub release:"
echo "  gh release create v0.0.1 \\"
echo "    $RELEASE_DIR/vcluster-linux-amd64 \\"
echo "    --title 'vCluster with External Database Connector' \\"
echo "    --notes 'Custom vCluster build with PostgreSQL/MySQL auto-provisioning support'"

