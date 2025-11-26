#!/bin/bash
# PostgreSQL Setup Script for Podman
# This script deploys PostgreSQL using Podman and sets it up for vCluster testing

set -e

echo "=========================================="
echo "PostgreSQL Setup for vCluster Testing"
echo "=========================================="

# Configuration
POSTGRES_PASSWORD="vcluster-test-password"
POSTGRES_PORT="5432"
CONTAINER_NAME="vcluster-postgres"
POSTGRES_VERSION="15"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Step 1: Checking if PostgreSQL container already exists...${NC}"
if podman ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "Container ${CONTAINER_NAME} already exists. Removing it..."
    podman rm -f ${CONTAINER_NAME}
fi

echo -e "${YELLOW}Step 2: Starting PostgreSQL container...${NC}"
podman run -d \
    --name ${CONTAINER_NAME} \
    -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
    -p ${POSTGRES_PORT}:5432 \
    -v vcluster-postgres-data:/var/lib/postgresql/data \
    docker.io/library/postgres:${POSTGRES_VERSION}

echo -e "${GREEN}✓ PostgreSQL container started${NC}"

echo -e "${YELLOW}Step 3: Waiting for PostgreSQL to be ready...${NC}"
sleep 5

# Wait for PostgreSQL to be ready
for i in {1..30}; do
    if podman exec ${CONTAINER_NAME} pg_isready -U postgres > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PostgreSQL is ready!${NC}"
        break
    fi
    echo "Waiting for PostgreSQL... ($i/30)"
    sleep 2
done

echo -e "${YELLOW}Step 4: Testing PostgreSQL connection...${NC}"
podman exec ${CONTAINER_NAME} psql -U postgres -c "SELECT version();"

echo ""
echo "=========================================="
echo -e "${GREEN}PostgreSQL Setup Complete!${NC}"
echo "=========================================="
echo ""
echo "Connection Details:"
echo "  Host: localhost (or 127.0.0.1)"
echo "  Port: ${POSTGRES_PORT}"
echo "  Username: postgres"
echo "  Password: ${POSTGRES_PASSWORD}"
echo ""
echo "Container Commands:"
echo "  View logs:    podman logs ${CONTAINER_NAME}"
echo "  Stop:         podman stop ${CONTAINER_NAME}"
echo "  Start:        podman start ${CONTAINER_NAME}"
echo "  Remove:       podman rm -f ${CONTAINER_NAME}"
echo "  Shell:        podman exec -it ${CONTAINER_NAME} bash"
echo "  psql:         podman exec -it ${CONTAINER_NAME} psql -U postgres"
echo ""
echo "Next Steps:"
echo "  1. Run: ./test-connector-postgres.sh"
echo "  2. Or manually test with the connector secret"
echo ""

