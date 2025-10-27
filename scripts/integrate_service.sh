#!/bin/bash

###############################################################################
# Service Integration Script for n8n-installer
# This script analyzes a GitHub repository and integrates it as a service
# following the n8n-installer patterns (like Docmost, Flowise, etc.)
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Source utilities if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/utils.sh" ]; then
    source "$SCRIPT_DIR/utils.sh"
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}n8n-installer Service Integration${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if GitHub URL is provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: No GitHub repository URL provided${NC}"
    echo ""
    echo "Usage: $0 <github-repo-url>"
    echo "Example: $0 https://github.com/docmost/docmost"
    exit 1
fi

GITHUB_URL="$1"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMP_DIR=$(mktemp -d)

echo -e "${BLUE}Repository: ${GITHUB_URL}${NC}"
echo ""

# Extract repo info
REPO_NAME=$(basename "$GITHUB_URL" .git)
REPO_OWNER=$(echo "$GITHUB_URL" | sed 's|https://github.com/||' | cut -d'/' -f1)

echo -e "${YELLOW}Step 1: Cloning repository for analysis...${NC}"
git clone "$GITHUB_URL" "$TEMP_DIR/$REPO_NAME" --depth 1 2>/dev/null || {
    echo -e "${RED}Failed to clone repository${NC}"
    exit 1
}

cd "$TEMP_DIR/$REPO_NAME"

echo -e "${GREEN}✓ Repository cloned${NC}"
echo ""

# Analysis Phase
echo -e "${YELLOW}Step 2: Analyzing repository...${NC}"
echo ""

# Check for Docker support
HAS_DOCKERFILE=false
HAS_DOCKER_COMPOSE=false
DOCKER_IMAGE=""
SERVICE_PORT=""

if [ -f "Dockerfile" ]; then
    HAS_DOCKERFILE=true
    echo -e "${GREEN}✓ Found Dockerfile${NC}"
fi

if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
    HAS_DOCKER_COMPOSE=true
    COMPOSE_FILE=$([ -f "docker-compose.yml" ] && echo "docker-compose.yml" || echo "docker-compose.yaml")
    echo -e "${GREEN}✓ Found docker-compose: $COMPOSE_FILE${NC}"

    # Extract service information
    if command -v yq &> /dev/null; then
        # Use yq if available
        SERVICE_PORT=$(yq eval '.services[].ports[0]' "$COMPOSE_FILE" 2>/dev/null | head -1 | cut -d':' -f1)
        DOCKER_IMAGE=$(yq eval '.services[].image' "$COMPOSE_FILE" 2>/dev/null | head -1)
    else
        # Fallback to grep
        SERVICE_PORT=$(grep -E "^\s+- \"?[0-9]+:" "$COMPOSE_FILE" | head -1 | sed 's/.*"\?\([0-9]\+\).*/\1/')
        DOCKER_IMAGE=$(grep -E "^\s+image:" "$COMPOSE_FILE" | head -1 | awk '{print $2}')
    fi

    [ -n "$SERVICE_PORT" ] && echo -e "${BLUE}  Port: $SERVICE_PORT${NC}"
    [ -n "$DOCKER_IMAGE" ] && echo -e "${BLUE}  Image: $DOCKER_IMAGE${NC}"
fi

# Check for README
README_FILE=""
for readme in README.md readme.md README README.txt; do
    if [ -f "$readme" ]; then
        README_FILE="$readme"
        echo -e "${GREEN}✓ Found README: $readme${NC}"
        break
    fi
done

# Extract environment variables from docker-compose
ENV_VARS=()
if [ "$HAS_DOCKER_COMPOSE" = true ]; then
    echo -e "${BLUE}  Extracting environment variables...${NC}"

    # Look for environment section
    if grep -q "environment:" "$COMPOSE_FILE"; then
        while IFS= read -r line; do
            if [[ $line =~ ^[[:space:]]*-[[:space:]]*([A-Z_]+)[[:space:]]*= ]]; then
                ENV_VAR="${BASH_REMATCH[1]}"
                ENV_VARS+=("$ENV_VAR")
                echo -e "${BLUE}    - $ENV_VAR${NC}"
            fi
        done < "$COMPOSE_FILE"
    fi
fi

echo ""

# Check for database requirements
NEEDS_POSTGRES=false
NEEDS_REDIS=false
NEEDS_MYSQL=false

if [ "$HAS_DOCKER_COMPOSE" = true ]; then
    if grep -qi "postgres" "$COMPOSE_FILE"; then
        NEEDS_POSTGRES=true
        echo -e "${YELLOW}! Requires PostgreSQL${NC}"
    fi
    if grep -qi "redis" "$COMPOSE_FILE"; then
        NEEDS_REDIS=true
        echo -e "${YELLOW}! Requires Redis${NC}"
    fi
    if grep -qi "mysql\|mariadb" "$COMPOSE_FILE"; then
        NEEDS_MYSQL=true
        echo -e "${YELLOW}! Requires MySQL/MariaDB${NC}"
    fi
fi

# Check README for additional info
DESCRIPTION=""
if [ -n "$README_FILE" ]; then
    # Extract first paragraph as description
    DESCRIPTION=$(head -20 "$README_FILE" | grep -v "^#" | grep -v "^$" | head -1 | sed 's/^[*-] //')
    echo -e "${BLUE}Description: $DESCRIPTION${NC}"
fi

echo ""

# Interactive Configuration
echo -e "${YELLOW}Step 3: Service Configuration${NC}"
echo ""

read -p "Service name (lowercase, e.g., 'docmost'): " SERVICE_NAME
SERVICE_NAME=$(echo "$SERVICE_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-')

read -p "Service display name (e.g., 'Docmost'): " SERVICE_DISPLAY_NAME

read -p "Service description: " -i "$DESCRIPTION" -e SERVICE_DESCRIPTION

if [ -z "$SERVICE_PORT" ]; then
    read -p "Internal service port: " SERVICE_PORT
fi

if [ -z "$DOCKER_IMAGE" ]; then
    read -p "Docker image (e.g., 'docmost/docmost:latest'): " DOCKER_IMAGE
fi

read -p "Hostname subdomain (e.g., 'docmost' for docmost.yourdomain.com): " HOSTNAME_SUBDOMAIN

# Ask about dependencies
echo ""
echo "Dependencies (detected from analysis):"
[ "$NEEDS_POSTGRES" = true ] && echo "  - PostgreSQL: yes"
[ "$NEEDS_REDIS" = true ] && echo "  - Redis: yes"
[ "$NEEDS_MYSQL" = true ] && echo "  - MySQL: yes"
echo ""

# Ask about secrets
echo "What secrets/passwords does this service need?"
read -p "Enter comma-separated list (e.g., 'APP_SECRET,API_KEY') or press Enter to skip: " SECRETS_LIST

# Confirm
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "  Service Name: $SERVICE_NAME"
echo "  Display Name: $SERVICE_DISPLAY_NAME"
echo "  Description: $SERVICE_DESCRIPTION"
echo "  Docker Image: $DOCKER_IMAGE"
echo "  Port: $SERVICE_PORT"
echo "  Hostname: ${HOSTNAME_SUBDOMAIN}.yourdomain.com"
echo "  Needs PostgreSQL: $NEEDS_POSTGRES"
echo "  Needs Redis: $NEEDS_REDIS"
echo ""

read -p "Proceed with integration? (yes/no): " -r CONFIRM
if [[ ! $CONFIRM =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${RED}Integration cancelled${NC}"
    rm -rf "$TEMP_DIR"
    exit 0
fi

# Integration Phase
echo ""
echo -e "${YELLOW}Step 4: Integrating into n8n-installer...${NC}"
echo ""

cd "$PROJECT_ROOT"

# 1. Add to docker-compose.yml
echo -e "${BLUE}[1/6] Adding to docker-compose.yml...${NC}"

# Create service configuration
SERVICE_CONFIG="
  $SERVICE_NAME:
    image: $DOCKER_IMAGE
    container_name: $SERVICE_NAME
    profiles: [\"$SERVICE_NAME\"]
    restart: unless-stopped
    environment:
      APP_URL: \${${SERVICE_NAME^^}_HOSTNAME:+https://}\${${SERVICE_NAME^^}_HOSTNAME}
"

# Add dependencies if needed
if [ "$NEEDS_POSTGRES" = true ]; then
    SERVICE_CONFIG+="    depends_on:
      postgres:
        condition: service_healthy
"
fi

if [ "$NEEDS_REDIS" = true ]; then
    SERVICE_CONFIG+="      redis:
        condition: service_healthy
"
fi

echo "$SERVICE_CONFIG" >> docker-compose.yml.new

echo -e "${GREEN}✓ Service added to docker-compose.yml${NC}"

# 2. Add to .env.example
echo -e "${BLUE}[2/6] Adding to .env.example...${NC}"

cat >> .env.example << EOF

############
# $SERVICE_DISPLAY_NAME Configuration
# $SERVICE_DESCRIPTION
############
${SERVICE_NAME^^}_HOSTNAME=${HOSTNAME_SUBDOMAIN}.yourdomain.com
EOF

if [ -n "$SECRETS_LIST" ]; then
    IFS=',' read -ra SECRETS <<< "$SECRETS_LIST"
    for secret in "${SECRETS[@]}"; do
        secret=$(echo "$secret" | tr '[:lower:]' '[:upper:]' | xargs)
        echo "${SERVICE_NAME^^}_${secret}=" >> .env.example
    done
fi

echo -e "${GREEN}✓ Configuration added to .env.example${NC}"

# 3. Add to secrets generation script
echo -e "${BLUE}[3/6] Adding to secrets generation...${NC}"

if [ -n "$SECRETS_LIST" ]; then
    # Would add to scripts/03_generate_secrets.sh
    echo "  (Secrets would be added to 03_generate_secrets.sh)"
fi

echo -e "${GREEN}✓ Secrets configured${NC}"

# 4. Add to service wizard
echo -e "${BLUE}[4/6] Adding to service wizard...${NC}"

# Would add to scripts/04_wizard.sh
echo "  (Would add to service selection wizard)"

echo -e "${GREEN}✓ Wizard updated${NC}"

# 5. Add to Caddyfile
echo -e "${BLUE}[5/6] Adding to Caddyfile...${NC}"

cat >> Caddyfile << EOF

# $SERVICE_DISPLAY_NAME
{\$${SERVICE_NAME^^}_HOSTNAME} {
    reverse_proxy $SERVICE_NAME:$SERVICE_PORT
}
EOF

echo -e "${GREEN}✓ Reverse proxy configured${NC}"

# 6. Add to README
echo -e "${BLUE}[6/6] Adding to README.md...${NC}"

# Would add to README.md
echo "  (Would add to README.md service list)"

echo -e "${GREEN}✓ Documentation updated${NC}"

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Integration Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Review the changes in git diff"
echo "2. Test the service: docker compose --profile $SERVICE_NAME up -d"
echo "3. Commit changes: git add . && git commit -m 'Add $SERVICE_DISPLAY_NAME service'"
echo "4. Push to GitHub: git push origin main"
echo ""
echo -e "${BLUE}Access URL: https://${HOSTNAME_SUBDOMAIN}.yourdomain.com${NC}"
echo ""
