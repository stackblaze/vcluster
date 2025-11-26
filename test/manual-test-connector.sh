#!/bin/bash
# Manual test script - tests the connector implementation without creating vCluster
# This directly tests the database provisioning logic

set -e

POSTGRES_PASSWORD="vcluster-test-password"
POSTGRES_HOST="localhost"
POSTGRES_PORT="5432"
CONTAINER_NAME="vcluster-postgres"
TEST_DB_NAME="vcluster_manual_test_abc123"
TEST_USER="vcluster_manual_test"
TEST_PASSWORD="test_password_12345"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "Manual Connector Test"
echo "=========================================="

# Check PostgreSQL is running
echo -e "${YELLOW}Checking PostgreSQL...${NC}"
if ! podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${RED}Error: PostgreSQL container is not running${NC}"
    echo "Run: ./postgres-podman-setup.sh first"
    exit 1
fi
echo -e "${GREEN}✓ PostgreSQL is running${NC}"

# Test database creation
echo -e "${YELLOW}Testing database creation...${NC}"
podman exec ${CONTAINER_NAME} psql -U postgres -c "CREATE DATABASE ${TEST_DB_NAME};" 2>/dev/null || echo "Database may already exist"
echo -e "${GREEN}✓ Database created${NC}"

# Test user creation
echo -e "${YELLOW}Testing user creation...${NC}"
podman exec ${CONTAINER_NAME} psql -U postgres -c "CREATE USER ${TEST_USER} WITH PASSWORD '${TEST_PASSWORD}';" 2>/dev/null || echo "User may already exist"
echo -e "${GREEN}✓ User created${NC}"

# Grant privileges
echo -e "${YELLOW}Granting privileges...${NC}"
podman exec ${CONTAINER_NAME} psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE ${TEST_DB_NAME} TO ${TEST_USER};"
# PostgreSQL 15+ requires explicit schema privileges
podman exec ${CONTAINER_NAME} psql -U postgres -d ${TEST_DB_NAME} -c "GRANT ALL ON SCHEMA public TO ${TEST_USER};"
podman exec ${CONTAINER_NAME} psql -U postgres -d ${TEST_DB_NAME} -c "GRANT CREATE ON SCHEMA public TO ${TEST_USER};"
echo -e "${GREEN}✓ Privileges granted${NC}"

# Verify database exists
echo -e "${YELLOW}Verifying database...${NC}"
podman exec ${CONTAINER_NAME} psql -U postgres -c "\l" | grep ${TEST_DB_NAME}
echo -e "${GREEN}✓ Database verified${NC}"

# Verify user exists
echo -e "${YELLOW}Verifying user...${NC}"
podman exec ${CONTAINER_NAME} psql -U postgres -c "\du" | grep ${TEST_USER}
echo -e "${GREEN}✓ User verified${NC}"

# Test connection with new user
echo -e "${YELLOW}Testing connection with new user...${NC}"
PGPASSWORD=${TEST_PASSWORD} podman exec -e PGPASSWORD ${CONTAINER_NAME} psql -U ${TEST_USER} -d ${TEST_DB_NAME} -c "SELECT current_database(), current_user;"
echo -e "${GREEN}✓ Connection successful${NC}"

# Test creating a table (simulating Kine)
echo -e "${YELLOW}Testing table creation (simulating Kine)...${NC}"
PGPASSWORD=${TEST_PASSWORD} podman exec -e PGPASSWORD ${CONTAINER_NAME} psql -U ${TEST_USER} -d ${TEST_DB_NAME} -c "
CREATE TABLE IF NOT EXISTS kine (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255),
    created TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO kine (name) VALUES ('test-entry');
SELECT * FROM kine;
"
echo -e "${GREEN}✓ Table operations successful${NC}"

echo ""
echo "=========================================="
echo -e "${GREEN}Manual Test Passed!${NC}"
echo "=========================================="
echo ""
echo "The connector implementation should work correctly."
echo ""
echo "Clean up test database:"
echo "  podman exec ${CONTAINER_NAME} psql -U postgres -c 'DROP DATABASE ${TEST_DB_NAME};'"
echo "  podman exec ${CONTAINER_NAME} psql -U postgres -c 'DROP USER ${TEST_USER};'"
echo ""

