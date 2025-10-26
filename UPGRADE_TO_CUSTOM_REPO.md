# Upgrading to Custom Repository (PatTDS Fork)

This guide explains how to safely replace the original n8n-installer repository with your custom fork that includes Docmost integration.

## Quick Overview

Your custom fork at https://github.com/PatTDS/n8n-installer-PatTDS includes:
- All original n8n-installer features
- Docmost service integration (Notion alternative)
- Custom configurations and improvements

## Prerequisites

- SSH access to your VPS
- Existing n8n-installer installation running
- Backup of your `.env` file (optional, but recommended)

## Important: What Gets Preserved

✅ **Automatically Preserved:**
- All Docker volumes (databases, n8n workflows, user data)
- PostgreSQL data
- Redis data
- n8n workflows and credentials
- All uploaded files and storage

⚠️ **Must Be Backed Up Manually:**
- `.env` configuration file
- Custom Caddy configurations (if modified)
- Custom scripts or configurations

## Method 1: Automated Script (Recommended)

### Step 1: Upload the replacement script to your VPS

```bash
# On your VPS, navigate to n8n-installer directory
cd ~/n8n-installer  # or wherever your installation is located

# Download the replacement script
curl -o replace_repo.sh https://raw.githubusercontent.com/PatTDS/n8n-installer-PatTDS/main/scripts/replace_repository.sh

# Make it executable
chmod +x replace_repo.sh
```

### Step 2: Run the script

```bash
sudo bash replace_repo.sh
```

The script will:
1. Stop all containers
2. Backup your `.env` and important files
3. Rename current installation
4. Clone your custom repository
5. Restore your configurations
6. Provide next steps

### Step 3: Update configuration

```bash
# Edit your .env file
nano .env
```

Add Docmost configuration (if you want to use it):
```bash
# Docmost Configuration
DOCMOST_HOSTNAME=docmost.yourdomain.com
DOCMOST_APP_SECRET=your-32-char-secret-here

# Update COMPOSE_PROFILES to include docmost
COMPOSE_PROFILES=n8n,docmost,monitoring  # Add other profiles you use
```

Generate the secret:
```bash
openssl rand -hex 32
```

### Step 4: Start services

```bash
# Pull latest images
docker compose pull

# Start all services
docker compose up -d

# Check logs
docker compose logs -f
```

---

## Method 2: Manual Replacement (Alternative)

If you prefer more control, follow these manual steps:

### Step 1: Backup important files

```bash
# Navigate to your installation
cd ~/n8n-installer

# Stop containers
docker compose down

# Create backup directory
mkdir -p ~/n8n-backup
cp .env ~/n8n-backup/.env
cp -r shared ~/n8n-backup/shared 2>/dev/null || true
cp -r n8n/backup ~/n8n-backup/n8n-backup 2>/dev/null || true

# List volumes for reference
docker volume ls > ~/n8n-backup/volumes.txt
```

### Step 2: Switch repository

```bash
# Check current remote
cd ~/n8n-installer
git remote -v

# Option A: Change remote (if you want to keep git history)
git remote set-url origin https://github.com/PatTDS/n8n-installer-PatTDS.git
git fetch origin
git reset --hard origin/main

# Option B: Fresh clone (cleaner approach)
cd ~
mv n8n-installer n8n-installer-old-backup
git clone https://github.com/PatTDS/n8n-installer-PatTDS.git n8n-installer
cd n8n-installer
```

### Step 3: Restore configurations

```bash
# Restore .env
cp ~/n8n-backup/.env .env

# Restore shared folder
cp -r ~/n8n-backup/shared . 2>/dev/null || true

# Restore n8n backups
mkdir -p n8n/backup
cp -r ~/n8n-backup/n8n-backup/* n8n/backup/ 2>/dev/null || true
```

### Step 4: Update and start

```bash
# Add Docmost configuration to .env
nano .env

# Pull and start
docker compose pull
docker compose up -d
```

---

## Method 3: Git Update (Keeping Current Directory)

Simplest method if you just want to update files:

```bash
cd ~/n8n-installer

# Stop services
docker compose down

# Backup .env
cp .env .env.backup

# Change remote
git remote set-url origin https://github.com/PatTDS/n8n-installer-PatTDS.git

# Force update to your fork
git fetch origin
git reset --hard origin/main

# Restore .env
cp .env.backup .env

# Update configuration for Docmost
nano .env

# Start services
docker compose pull
docker compose up -d
```

---

## Post-Upgrade Verification

### 1. Check all services are running

```bash
docker compose ps
```

All services should show "Up" status.

### 2. Check logs for errors

```bash
docker compose logs -f
```

Press `Ctrl+C` to exit logs.

### 3. Verify your services are accessible

- n8n: https://n8n.yourdomain.com
- Other services you have enabled

### 4. Test Docmost (if enabled)

- Access: https://docmost.yourdomain.com
- Create workspace and admin account
- Verify real-time editing works

---

## Troubleshooting

### Services won't start

```bash
# Check logs
docker compose logs

# Check specific service
docker compose logs docmost

# Restart specific service
docker compose restart docmost
```

### Lost .env configuration

If you forgot to backup your `.env`:

```bash
# List environment variables from running containers (if still running)
docker inspect n8n | grep -A 50 Env

# Or restore from old directory
cp ~/n8n-installer-old-backup/.env ~/n8n-installer/.env
```

### Want to rollback

```bash
cd ~
docker compose -f n8n-installer/docker-compose.yml down
mv n8n-installer n8n-installer-new-failed
mv n8n-installer-old-backup n8n-installer
cd n8n-installer
docker compose up -d
```

---

## Cleanup After Successful Upgrade

After verifying everything works for a few days:

```bash
# Remove old installation backup
rm -rf ~/n8n-installer-old-backup

# Remove manual backup
rm -rf ~/n8n-backup
```

---

## Adding Docmost After Upgrade

If you didn't enable Docmost during upgrade, you can add it later:

### 1. Edit .env

```bash
nano .env
```

Add:
```bash
DOCMOST_HOSTNAME=docmost.yourdomain.com
DOCMOST_APP_SECRET=$(openssl rand -hex 32)
```

Update profiles:
```bash
COMPOSE_PROFILES=n8n,docmost,your-other-profiles
```

### 2. Deploy Docmost

```bash
docker compose pull docmost
docker compose up -d docmost
```

### 3. Access and setup

Visit https://docmost.yourdomain.com and complete the setup wizard.

---

## Support

If you encounter issues:

1. Check logs: `docker compose logs -f`
2. Check service status: `docker compose ps`
3. Verify .env configuration
4. Ensure DNS is properly configured
5. Check firewall rules (ports 80, 443)

## Useful Commands

```bash
# View all running containers
docker compose ps

# View logs for all services
docker compose logs -f

# View logs for specific service
docker compose logs -f docmost

# Restart all services
docker compose restart

# Restart specific service
docker compose restart docmost

# Stop all services
docker compose down

# Start all services
docker compose up -d

# Pull latest images
docker compose pull

# View Docker volumes
docker volume ls

# Check disk space
df -h
docker system df
```
