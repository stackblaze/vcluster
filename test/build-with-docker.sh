#!/bin/bash
# Build vCluster using Docker (no local Go installation needed)

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "Building vCluster with Docker"
echo "=========================================="

cd /home/linux/vcluster

IMAGE_NAME="vcluster-custom"
IMAGE_TAG="connector-test"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

echo -e "${YELLOW}Step 1: Building Docker image...${NC}"
echo "This will compile vCluster with your connector changes inside the container"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    TARGETARCH="amd64"
    TARGETOS="linux"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    TARGETARCH="arm64"
    TARGETOS="linux"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

echo "Building for: ${TARGETOS}/${TARGETARCH}"

# Use sudo docker if user is not in docker group yet
DOCKER_CMD="docker"
if ! docker ps >/dev/null 2>&1; then
    echo -e "${YELLOW}Note: Using sudo for docker (you may need to log out and back in for group changes to take effect)${NC}"
    DOCKER_CMD="sudo docker"
fi

$DOCKER_CMD build \
    --build-arg TARGETOS=${TARGETOS} \
    --build-arg TARGETARCH=${TARGETARCH} \
    -t ${FULL_IMAGE} \
    -f Dockerfile .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ vCluster image built successfully!${NC}"
    $DOCKER_CMD images | grep ${IMAGE_NAME}
else
    echo -e "${RED}✗ Failed to build image${NC}"
    exit 1
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Build Complete!${NC}"
echo "=========================================="
echo ""
echo "Image created: ${FULL_IMAGE}"
echo ""
echo "Next steps:"
echo "  1. Set up a Kubernetes cluster (if you don't have one)"
echo "  2. Load the image to your cluster"
echo "  3. Deploy vCluster with the custom image"
echo ""
echo "Quick commands:"
echo ""
echo "# If using kind:"
echo "  kind create cluster --name vcluster-test"
echo "  $DOCKER_CMD save ${FULL_IMAGE} | kind load image-archive /dev/stdin --name vcluster-test"
echo ""
echo "# If using minikube:"
echo "  minikube start"
echo "  $DOCKER_CMD save ${FULL_IMAGE} -o /tmp/vcluster.tar"
echo "  minikube image load /tmp/vcluster.tar"
echo ""
echo "# Then deploy:"
echo "  ./deploy-to-k8s.sh"
echo ""

