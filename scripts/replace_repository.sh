#!/bin/bash

###############################################################################
# Repository Replacement Script for n8n-installer
# This script safely replaces the original repository with your custom fork
# while preserving important data and configurations
###############################################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Your custom repository URL
NEW_REPO="https://github.com/PatTDS/n8n-installer-PatTDS.git"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}n8n-installer Repository Replacement${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Get current directory
CURRENT_DIR=$(pwd)
PARENT_DIR=$(dirname "$CURRENT_DIR")
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${PARENT_DIR}/n8n-installer-backup-${TIMESTAMP}"

echo -e "${YELLOW}Current directory: ${CURRENT_DIR}${NC}"
echo -e "${YELLOW}Backup will be created at: ${BACKUP_DIR}${NC}"
echo ""

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}Error: docker-compose.yml not found. Are you in the n8n-installer directory?${NC}"
    exit 1
fi

# Warning
echo -e "${YELLOW}⚠️  WARNING: This will replace the repository files.${NC}"
echo -e "${YELLOW}Important data will be preserved:${NC}"
echo "  - Docker volumes (databases, storage)"
echo "  - .env file (your configuration)"
echo "  - shared/ folder (your files)"
echo "  - n8n/backup/ folder (your backups)"
echo ""
read -p "Do you want to continue? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${RED}Operation cancelled.${NC}"
    exit 0
fi

# Step 1: Stop all running containers
echo -e "${GREEN}[1/8] Stopping Docker containers...${NC}"
docker compose down || true
echo ""

# Step 2: Create backup directory
echo -e "${GREEN}[2/8] Creating backup directory...${NC}"
mkdir -p "$BACKUP_DIR"
echo ""

# Step 3: Backup important files and folders
echo -e "${GREEN}[3/8] Backing up important files...${NC}"

# Backup .env file
if [ -f ".env" ]; then
    cp .env "$BACKUP_DIR/.env"
    echo "  ✓ Backed up .env"
fi

# Backup shared folder
if [ -d "shared" ]; then
    cp -r shared "$BACKUP_DIR/shared"
    echo "  ✓ Backed up shared/"
fi

# Backup n8n/backup folder
if [ -d "n8n/backup" ]; then
    cp -r n8n/backup "$BACKUP_DIR/n8n-backup"
    echo "  ✓ Backed up n8n/backup/"
fi

# Backup custom configurations
for dir in searxng neo4j grafana prometheus python-runner paddlex; do
    if [ -d "$dir" ]; then
        cp -r "$dir" "$BACKUP_DIR/$dir"
        echo "  ✓ Backed up $dir/"
    fi
done

# Backup Caddyfile if customized
if [ -f "Caddyfile" ]; then
    cp Caddyfile "$BACKUP_DIR/Caddyfile.backup"
    echo "  ✓ Backed up Caddyfile"
fi

# List Docker volumes for reference
echo ""
echo -e "${GREEN}[4/8] Documenting Docker volumes...${NC}"
docker volume ls | grep -E "n8n|postgres|redis|qdrant|langfuse|flowise|supabase|weaviate|docmost" > "$BACKUP_DIR/docker_volumes.txt" 2>/dev/null || true
echo "  ✓ Volume list saved"
echo ""

# Step 4: Move to parent directory
echo -e "${GREEN}[5/8] Moving to parent directory...${NC}"
cd "$PARENT_DIR"
echo ""

# Step 5: Rename current directory
echo -e "${GREEN}[6/8] Renaming current installation...${NC}"
mv "n8n-installer" "n8n-installer-old-${TIMESTAMP}"
echo "  ✓ Renamed to n8n-installer-old-${TIMESTAMP}"
echo ""

# Step 6: Clone your custom repository
echo -e "${GREEN}[7/8] Cloning your custom repository...${NC}"
git clone "$NEW_REPO" n8n-installer
cd n8n-installer
echo ""

# Step 7: Restore important files
echo -e "${GREEN}[8/8] Restoring your configuration...${NC}"

# Restore .env
if [ -f "$BACKUP_DIR/.env" ]; then
    cp "$BACKUP_DIR/.env" .env
    echo "  ✓ Restored .env"
fi

# Restore shared folder
if [ -d "$BACKUP_DIR/shared" ]; then
    cp -r "$BACKUP_DIR/shared" .
    echo "  ✓ Restored shared/"
fi

# Restore n8n/backup folder
if [ -d "$BACKUP_DIR/n8n-backup" ]; then
    mkdir -p n8n/backup
    cp -r "$BACKUP_DIR/n8n-backup/"* n8n/backup/
    echo "  ✓ Restored n8n/backup/"
fi

# Restore custom configurations
for dir in searxng neo4j grafana prometheus python-runner paddlex; do
    if [ -d "$BACKUP_DIR/$dir" ]; then
        cp -r "$BACKUP_DIR/$dir" .
        echo "  ✓ Restored $dir/"
    fi
done

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Repository replacement completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Review your .env file and add new variables if needed:"
echo "   - DOCMOST_HOSTNAME=docmost.yourdomain.com"
echo "   - DOCMOST_APP_SECRET=\$(openssl rand -hex 32)"
echo "   - Update COMPOSE_PROFILES to include 'docmost' if desired"
echo ""
echo "2. Start your services:"
echo "   ${GREEN}docker compose pull${NC}"
echo "   ${GREEN}docker compose up -d${NC}"
echo ""
echo "3. Check logs:"
echo "   ${GREEN}docker compose logs -f${NC}"
echo ""
echo -e "${YELLOW}Backups location:${NC}"
echo "  - Full backup: ${BACKUP_DIR}"
echo "  - Old installation: ${PARENT_DIR}/n8n-installer-old-${TIMESTAMP}"
echo ""
echo -e "${YELLOW}To remove old installation after verifying everything works:${NC}"
echo "  ${RED}rm -rf ${PARENT_DIR}/n8n-installer-old-${TIMESTAMP}${NC}"
echo "  ${RED}rm -rf ${BACKUP_DIR}${NC}"
echo ""
