# Service Integration Guide

This guide explains how to automatically integrate new services into n8n-installer from GitHub repositories.

## Overview

The n8n-installer includes automation tools to analyze GitHub repositories and integrate them as services, following the same patterns as existing services (Docmost, Flowise, Langfuse, etc.).

## Tools Available

### 1. Python Analyzer (Recommended)
**File:** `scripts/analyze_and_integrate.py`

A comprehensive Python tool that:
- Clones and analyzes the repository
- Extracts Docker configuration
- Reads README and documentation
- Detects dependencies (Postgres, Redis, etc.)
- Interactively guides you through integration
- Updates all necessary files

### 2. Bash Script
**File:** `scripts/integrate_service.sh`

A simpler bash script for basic integrations.

## Quick Start

### Prerequisites

```bash
# Python 3.x required for the Python tool
python3 --version

# Or use bash script (no dependencies)
bash --version
```

### Using the Python Analyzer

```bash
# Make it executable
chmod +x scripts/analyze_and_integrate.py

# Run with a GitHub URL
./scripts/analyze_and_integrate.py https://github.com/owner/repo
```

### Using the Bash Script

```bash
# Make it executable
chmod +x scripts/integrate_service.sh

# Run with a GitHub URL
./scripts/integrate_service.sh https://github.com/owner/repo
```

## Example: Integrating a New Service

Let's say you want to integrate "Plausible Analytics":

```bash
cd ~/n8n-installer

# Run the analyzer
./scripts/analyze_and_integrate.py https://github.com/plausible/analytics
```

### What Happens:

1. **Repository Analysis**
   ```
   ✓ Repository cloned
   ✓ Found Dockerfile
   ✓ Found docker-compose.yml
   ✓ Found README.md

   Analysis Results:
     - Docker image: plausible/analytics:latest
     - Port: 8000
     - Needs PostgreSQL: Yes
     - Needs Redis: No
     - Environment variables detected: 12
   ```

2. **Interactive Configuration**
   ```
   Service name [plausible]:
   Display name [Plausible Analytics]:
   Description [Lightweight and privacy-friendly analytics]:
   Internal port [8000]:
   Docker image [plausible/analytics:latest]:
   Hostname subdomain [plausible]:
   ```

3. **Automatic Integration**
   ```
   [1/6] Updating docker-compose.yml...
   [2/6] Updating .env.example...
   [3/6] Updating Caddyfile...
   [4/6] Updating secrets...
   [5/6] Updating wizard...
   [6/6] Updating documentation...
   ```

4. **Review and Test**
   ```bash
   # Review changes
   git diff

   # Test the service
   docker compose --profile plausible up -d

   # Check logs
   docker compose logs plausible
   ```

## What Gets Updated

The integration tool modifies these files:

### 1. `docker-compose.yml`
Adds:
- Service definition
- Volume declaration
- Dependencies (if needed)
- Environment variables

**Example:**
```yaml
  plausible:
    image: plausible/analytics:latest
    container_name: plausible
    profiles: ["plausible"]
    restart: unless-stopped
    environment:
      APP_URL: ${PLAUSIBLE_HOSTNAME:+https://}${PLAUSIBLE_HOSTNAME}
      SECRET_KEY_BASE: ${PLAUSIBLE_SECRET_KEY}
      DATABASE_URL: postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/plausible
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - plausible_data:/var/lib/plausible
```

### 2. `.env.example`
Adds:
- Hostname configuration
- Required secrets
- Configuration variables

**Example:**
```bash
############
# Plausible Analytics Configuration
# Lightweight and privacy-friendly analytics
############
PLAUSIBLE_HOSTNAME=plausible.yourdomain.com
PLAUSIBLE_SECRET_KEY=
PLAUSIBLE_ADMIN_EMAIL=
```

### 3. `Caddyfile`
Adds reverse proxy configuration:

**Example:**
```
# Plausible Analytics
{$PLAUSIBLE_HOSTNAME} {
    reverse_proxy plausible:8000
}
```

### 4. Manual Updates Needed

The tool guides you to manually update:

**`scripts/03_generate_secrets.sh`**
```bash
["PLAUSIBLE_SECRET_KEY"]="secret:64"
```

**`scripts/04_wizard.sh`**
```bash
"plausible" "Plausible Analytics (Privacy-friendly analytics)"
```

**`scripts/07_final_report.sh`**
```bash
if is_profile_active "plausible"; then
  echo "================================= Plausible ============================="
  echo "Host: ${PLAUSIBLE_HOSTNAME}"
fi
```

**`README.md`**
Add to the "What's Included" section.

## Advanced Usage

### Analyzing Without Integration

```bash
# Just analyze, don't integrate
./scripts/analyze_and_integrate.py https://github.com/owner/repo --dry-run
```

### Custom Configuration

```python
# Modify the script for custom behavior
# Edit: scripts/analyze_and_integrate.py

class ServiceIntegrator:
    def add_custom_logic(self):
        # Add your custom integration logic here
        pass
```

## Integration Checklist

After running the automation tool:

- [ ] Review `docker-compose.yml` changes
- [ ] Review `.env.example` additions
- [ ] Review `Caddyfile` changes
- [ ] Add service to `scripts/04_wizard.sh`
- [ ] Add secrets to `scripts/03_generate_secrets.sh`
- [ ] Add to final report `scripts/07_final_report.sh`
- [ ] Update `README.md` with service description
- [ ] Update `cloudflare-instructions.md` if using tunnel
- [ ] Test service deployment
- [ ] Update DNS if using custom domain
- [ ] Commit and push changes

## Testing Your Integration

```bash
# 1. Generate secrets
./scripts/03_generate_secrets.sh

# 2. Add service to profiles
nano .env
# Add to COMPOSE_PROFILES: plausible

# 3. Start the service
docker compose pull plausible
docker compose up -d plausible

# 4. Check status
docker compose ps plausible

# 5. Check logs
docker compose logs -f plausible

# 6. Test access
curl -I https://plausible.yourdomain.com
```

## Common Integration Patterns

### Pattern 1: Simple Service (No Dependencies)
**Example:** Portainer, Uptime Kuma

```yaml
  service:
    image: vendor/service:latest
    container_name: service
    profiles: ["service"]
    restart: unless-stopped
    volumes:
      - service_data:/data
```

### Pattern 2: Requires Database
**Example:** Docmost, Plausible, Langfuse

```yaml
  service:
    image: vendor/service:latest
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      DATABASE_URL: postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/dbname
```

### Pattern 3: Requires Multiple Dependencies
**Example:** Complex applications

```yaml
  service:
    image: vendor/service:latest
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      minio:
        condition: service_healthy
```

### Pattern 4: Requires Basic Auth
**Example:** Prometheus, Grafana, RAGApp

```Caddyfile
{$SERVICE_HOSTNAME} {
    basic_auth {
        {$SERVICE_USERNAME} {$SERVICE_PASSWORD_HASH}
    }
    reverse_proxy service:port
}
```

## Troubleshooting

### Issue: Service won't start

```bash
# Check dependencies
docker compose ps postgres redis

# Check logs
docker compose logs service

# Check environment variables
docker compose config | grep -A 20 "service:"
```

### Issue: Can't access via domain

```bash
# Check Caddy logs
docker compose logs caddy

# Test internal connectivity
docker exec caddy wget -qO- http://service:port

# Check DNS
nslookup service.yourdomain.com
```

### Issue: Database connection fails

```bash
# Create database manually
docker exec postgres psql -U postgres -c "CREATE DATABASE dbname;"

# Check database exists
docker exec postgres psql -U postgres -c "\l"
```

## Best Practices

1. **Always review changes** before committing
2. **Test locally** before deploying to production
3. **Follow naming conventions** (lowercase, hyphens)
4. **Document environment variables** in .env.example
5. **Add health checks** when possible
6. **Use profiles** for optional services
7. **Keep secrets secure** (never commit .env)
8. **Update README** with service description

## Examples

### Successfully Integrated Services

These services were integrated using similar patterns:

- **Docmost** - Notion alternative (Postgres + Redis)
- **Flowise** - AI agent builder (Simple service)
- **Langfuse** - LLM observability (Postgres + Redis + Clickhouse + Minio)
- **Weaviate** - Vector database (Standalone)
- **Portainer** - Docker management (Simple service)
- **Grafana** - Monitoring (Depends on Prometheus)

## Contributing

When you successfully integrate a new service:

1. Test thoroughly
2. Document any special requirements
3. Submit a pull request with:
   - Service integration
   - Updated documentation
   - Example configuration
   - Screenshots (if applicable)

## Support

- Check existing services in `docker-compose.yml` for patterns
- Review `ADDING_NEW_SERVICE.md` for manual integration
- Ask questions in GitHub Discussions
- Report issues in GitHub Issues

## Future Enhancements

Planned improvements for the integration tool:

- [ ] Auto-detect authentication requirements
- [ ] Generate health checks automatically
- [ ] Auto-update README.md
- [ ] Generate Cloudflare Tunnel config
- [ ] Create service documentation template
- [ ] Validate integration before committing
- [ ] Auto-run tests after integration
- [ ] Support for multiple databases
- [ ] Custom service templates
