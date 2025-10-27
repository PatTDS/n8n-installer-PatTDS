#!/usr/bin/env python3
"""
Service Integration Tool for n8n-installer
Analyzes GitHub repositories and integrates them following n8n-installer patterns
"""

import os
import sys
import json
import subprocess
import tempfile
import shutil
import re
from pathlib import Path
from typing import Dict, List, Optional
import argparse

class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'

class ServiceAnalyzer:
    def __init__(self, github_url: str):
        self.github_url = github_url
        self.repo_name = Path(github_url).stem
        self.repo_owner = github_url.split('/')[-2]
        self.temp_dir = None
        self.analysis = {}

    def clone_repo(self) -> Path:
        """Clone repository for analysis"""
        self.temp_dir = Path(tempfile.mkdtemp())
        repo_path = self.temp_dir / self.repo_name

        print(f"{Colors.YELLOW}Cloning repository...{Colors.NC}")
        subprocess.run(
            ['git', 'clone', '--depth', '1', self.github_url, str(repo_path)],
            check=True,
            capture_output=True
        )
        print(f"{Colors.GREEN}✓ Repository cloned{Colors.NC}\n")
        return repo_path

    def analyze_dockerfile(self, repo_path: Path) -> Dict:
        """Analyze Dockerfile"""
        dockerfile = repo_path / 'Dockerfile'
        if not dockerfile.exists():
            return {}

        print(f"{Colors.GREEN}✓ Found Dockerfile{Colors.NC}")

        with open(dockerfile) as f:
            content = f.read()

        # Extract exposed ports
        ports = re.findall(r'EXPOSE\s+(\d+)', content)

        # Extract environment variables
        env_vars = re.findall(r'ENV\s+([A-Z_]+)', content)

        return {
            'has_dockerfile': True,
            'exposed_ports': ports,
            'env_vars': env_vars
        }

    def analyze_docker_compose(self, repo_path: Path) -> Dict:
        """Analyze docker-compose.yml"""
        compose_files = ['docker-compose.yml', 'docker-compose.yaml']
        compose_file = None

        for cf in compose_files:
            if (repo_path / cf).exists():
                compose_file = repo_path / cf
                break

        if not compose_file:
            return {}

        print(f"{Colors.GREEN}✓ Found docker-compose: {compose_file.name}{Colors.NC}")

        with open(compose_file) as f:
            content = f.read()

        # Extract services
        services = re.findall(r'^\s{2}(\w+):', content, re.MULTILINE)

        # Extract image
        image_match = re.search(r'image:\s+(.+)', content)
        image = image_match.group(1).strip() if image_match else None

        # Extract ports
        ports = re.findall(r'- ["\']?(\d+):', content)

        # Extract environment variables
        env_section = re.search(r'environment:(.*?)(?=\n  [a-z]|\Z)', content, re.DOTALL)
        env_vars = []
        if env_section:
            env_vars = re.findall(r'- ([A-Z_]+)(?:=|:)', env_section.group(1))

        # Check dependencies
        needs_postgres = 'postgres' in content.lower()
        needs_redis = 'redis' in content.lower()
        needs_mysql = 'mysql' in content.lower() or 'mariadb' in content.lower()

        return {
            'has_docker_compose': True,
            'compose_file': compose_file.name,
            'services': services,
            'image': image,
            'ports': ports,
            'env_vars': env_vars,
            'needs_postgres': needs_postgres,
            'needs_redis': needs_redis,
            'needs_mysql': needs_mysql
        }

    def analyze_readme(self, repo_path: Path) -> Dict:
        """Analyze README for service information"""
        readme_files = ['README.md', 'readme.md', 'README', 'README.txt']
        readme = None

        for rf in readme_files:
            if (repo_path / rf).exists():
                readme = repo_path / rf
                break

        if not readme:
            return {}

        print(f"{Colors.GREEN}✓ Found README: {readme.name}{Colors.NC}")

        with open(readme) as f:
            content = f.read()

        # Extract title
        title_match = re.search(r'^#\s+(.+)$', content, re.MULTILINE)
        title = title_match.group(1) if title_match else self.repo_name

        # Extract description (first paragraph)
        desc_match = re.search(r'\n\n(.+?)(?:\n\n|\Z)', content, re.DOTALL)
        description = desc_match.group(1).strip() if desc_match else ""
        description = ' '.join(description.split('\n')[:3])[:200]

        # Look for docker instructions
        has_docker_section = 'docker' in content.lower()

        # Look for environment variables section
        env_section = re.search(r'##?\s+Environment Variables(.*?)(?=\n##?\s+|\Z)', content, re.DOTALL | re.IGNORECASE)
        env_vars_documented = []
        if env_section:
            env_vars_documented = re.findall(r'`([A-Z_]+)`', env_section.group(1))

        return {
            'title': title,
            'description': description,
            'has_docker_section': has_docker_section,
            'documented_env_vars': env_vars_documented
        }

    def analyze_package_json(self, repo_path: Path) -> Dict:
        """Analyze package.json for Node.js projects"""
        package_json = repo_path / 'package.json'
        if not package_json.exists():
            return {}

        with open(package_json) as f:
            data = json.load(f)

        return {
            'name': data.get('name'),
            'description': data.get('description'),
            'version': data.get('version'),
            'is_nodejs': True
        }

    def run_analysis(self) -> Dict:
        """Run complete analysis"""
        print(f"{Colors.BLUE}Repository: {self.github_url}{Colors.NC}\n")
        print(f"{Colors.YELLOW}Analyzing repository structure...{Colors.NC}\n")

        repo_path = self.clone_repo()

        # Run all analyses
        self.analysis = {
            'repo_name': self.repo_name,
            'repo_owner': self.repo_owner,
            'github_url': self.github_url,
            **self.analyze_dockerfile(repo_path),
            **self.analyze_docker_compose(repo_path),
            **self.analyze_readme(repo_path),
            **self.analyze_package_json(repo_path)
        }

        return self.analysis

    def cleanup(self):
        """Clean up temporary files"""
        if self.temp_dir and self.temp_dir.exists():
            shutil.rmtree(self.temp_dir)

class ServiceIntegrator:
    def __init__(self, analysis: Dict, project_root: Path):
        self.analysis = analysis
        self.project_root = project_root
        self.service_name = None
        self.service_config = {}

    def interactive_config(self):
        """Get configuration from user"""
        print(f"\n{Colors.YELLOW}Service Configuration{Colors.NC}\n")

        # Service name
        default_name = self.analysis['repo_name'].lower().replace('-', '').replace('_', '')
        self.service_name = input(f"Service name [{default_name}]: ") or default_name
        self.service_name = re.sub(r'[^a-z0-9-]', '', self.service_name)

        # Display name
        default_display = self.analysis.get('title', self.analysis['repo_name'])
        display_name = input(f"Display name [{default_display}]: ") or default_display

        # Description
        default_desc = self.analysis.get('description', '') or ''
        desc_preview = default_desc[:50] if default_desc else 'No description available'
        description = input(f"Description [{desc_preview}{'...' if len(default_desc) > 50 else ''}]: ") or default_desc

        # Port
        ports_list = self.analysis.get('ports', [])
        default_port = ports_list[0] if ports_list else '3000'
        port = input(f"Internal port [{default_port}]: ") or default_port

        # Image
        default_image = self.analysis.get('image', f'{self.analysis["repo_owner"]}/{self.analysis["repo_name"]}:latest')
        image = input(f"Docker image [{default_image}]: ") or default_image

        # Hostname
        hostname = input(f"Hostname subdomain [{self.service_name}]: ") or self.service_name

        self.service_config = {
            'name': self.service_name,
            'display_name': display_name,
            'description': description,
            'port': port,
            'image': image,
            'hostname': hostname,
            'needs_postgres': self.analysis.get('needs_postgres', False),
            'needs_redis': self.analysis.get('needs_redis', False)
        }

        # Show summary
        print(f"\n{Colors.YELLOW}Summary:{Colors.NC}")
        for key, value in self.service_config.items():
            print(f"  {key}: {value}")

        confirm = input(f"\nProceed? (yes/no): ")
        return confirm.lower() == 'yes'

    def add_to_docker_compose(self):
        """Add service to docker-compose.yml"""
        print(f"{Colors.BLUE}[1/7] Updating docker-compose.yml...{Colors.NC}")

        docker_compose = self.project_root / 'docker-compose.yml'

        # Build service configuration
        service_block = f"""
  {self.service_config['name']}:
    image: {self.service_config['image']}
    container_name: {self.service_config['name']}
    profiles: ["{self.service_config['name']}"]
    restart: unless-stopped
    environment:
      APP_URL: ${{{self.service_config['name'].upper()}_HOSTNAME:+https://}}${{{self.service_config['name'].upper()}_HOSTNAME}}
"""

        # Add dependencies
        if self.service_config['needs_postgres'] or self.service_config['needs_redis']:
            service_block += "    depends_on:\n"
            if self.service_config['needs_postgres']:
                service_block += "      postgres:\n        condition: service_healthy\n"
            if self.service_config['needs_redis']:
                service_block += "      redis:\n        condition: service_healthy\n"

        # Add volume
        volume_name = f"{self.service_config['name']}_data"

        with open(docker_compose, 'a') as f:
            f.write(service_block)

        # Add volume to volumes section
        with open(docker_compose, 'r') as f:
            content = f.read()

        # Find volumes section and add new volume
        content = re.sub(
            r'(volumes:\n)',
            f'\\1  {volume_name}:\n',
            content,
            count=1
        )

        with open(docker_compose, 'w') as f:
            f.write(content)

        print(f"{Colors.GREEN}✓ Added to docker-compose.yml{Colors.NC}")

    def add_to_env_example(self):
        """Add to .env.example"""
        print(f"{Colors.BLUE}[2/7] Updating .env.example...{Colors.NC}")

        env_example = self.project_root / '.env.example'

        description_line = self.service_config['description'][:100] if self.service_config.get('description') else 'Service configuration'
        config_block = f"""
############
# {self.service_config['display_name']} Configuration
# {description_line}
############
{self.service_config['name'].upper()}_HOSTNAME={self.service_config['hostname']}.yourdomain.com
{self.service_config['name'].upper()}_APP_SECRET=
"""

        with open(env_example, 'a') as f:
            f.write(config_block)

        print(f"{Colors.GREEN}✓ Added to .env.example{Colors.NC}")

    def add_to_caddyfile(self):
        """Add to Caddyfile"""
        print(f"{Colors.BLUE}[3/7] Updating Caddyfile...{Colors.NC}")

        caddyfile = self.project_root / 'config' / 'caddy' / 'Caddyfile'

        caddy_block = f"""
# {self.service_config['display_name']}
{{{self.service_config['name'].upper()}_HOSTNAME}} {{
    reverse_proxy {self.service_config['name']}:{self.service_config['port']}
}}
"""

        with open(caddyfile, 'a') as f:
            f.write(caddy_block)

        print(f"{Colors.GREEN}✓ Added to Caddyfile{Colors.NC}")

    def add_to_wizard(self):
        """Add to installation wizard"""
        print(f"{Colors.BLUE}[4/7] Updating wizard (04_wizard.sh)...{Colors.NC}")

        wizard_file = self.project_root / 'scripts' / 'install' / '04_wizard.sh'

        with open(wizard_file, 'r') as f:
            content = f.read()

        # Find where to add (after outline or docmost)
        service_line = f'    "{self.service_config["name"]}" "{self.service_config["display_name"]}"\n'

        # Add after outline if it exists, otherwise after docmost
        if '"outline"' in content:
            content = re.sub(
                r'("outline" ".*?")\n',
                f'\\1\n{service_line}',
                content,
                count=1
            )
        elif '"docmost"' in content:
            content = re.sub(
                r'("docmost" ".*?")\n',
                f'\\1\n{service_line}',
                content,
                count=1
            )
        else:
            # Fallback: add before closing parenthesis of base_services_data
            content = re.sub(
                r'(\nbase_services_data=\([^)]+)',
                f'\\1\n{service_line}',
                content,
                count=1
            )

        with open(wizard_file, 'w') as f:
            f.write(content)

        print(f"{Colors.GREEN}✓ Added to wizard{Colors.NC}")

    def add_to_secrets(self):
        """Add to secrets generation"""
        print(f"{Colors.BLUE}[5/7] Updating secrets (03_generate_secrets.sh)...{Colors.NC}")

        secrets_file = self.project_root / 'scripts' / 'install' / '03_generate_secrets.sh'

        with open(secrets_file, 'r') as f:
            content = f.read()

        secret_line = f'    ["{self.service_config["name"].upper()}_APP_SECRET"]="hex:64"\n'

        # Add after OUTLINE_APP_SECRET or DOCMOST_APP_SECRET
        if 'OUTLINE_APP_SECRET' in content:
            content = re.sub(
                r'(\["OUTLINE_APP_SECRET"\]="hex:64")\n',
                f'\\1\n{secret_line}',
                content,
                count=1
            )
        elif 'DOCMOST_APP_SECRET' in content:
            content = re.sub(
                r'(\["DOCMOST_APP_SECRET"\]="hex:64")\n',
                f'\\1\n{secret_line}',
                content,
                count=1
            )
        else:
            # Fallback: add before closing parenthesis
            content = re.sub(
                r'(\n\))',
                f'{secret_line}\\1',
                content,
                count=1
            )

        with open(secrets_file, 'w') as f:
            f.write(content)

        print(f"{Colors.GREEN}✓ Added to secrets{Colors.NC}")

    def add_to_final_report(self):
        """Add to final installation report"""
        print(f"{Colors.BLUE}[6/7] Updating final report (07_final_report.sh)...{Colors.NC}")

        report_file = self.project_root / 'scripts' / 'install' / '07_final_report.sh'

        report_block = f'''
if is_profile_active "{self.service_config['name']}"; then
  echo
  echo "================================= {self.service_config['display_name']} ============================"
  echo
  echo "Host: ${{{self.service_config['name'].upper()}_HOSTNAME:-<hostname_not_set>}}"
  echo "Description: {self.service_config['description']}"
  echo
  echo "First Time Setup:"
  echo "  - Visit https://${{{self.service_config['name'].upper()}_HOSTNAME:-<hostname_not_set>}}"
  echo "  - Create your admin account"
fi
'''

        with open(report_file, 'r') as f:
            content = f.read()

        # Add after outline section if it exists
        if 'is_profile_active "outline"' in content:
            # Find the outline block and add after it
            content = re.sub(
                r'(if is_profile_active "outline"; then.*?^fi)',
                f'\\1\n{report_block}',
                content,
                count=1,
                flags=re.MULTILINE | re.DOTALL
            )
        elif 'is_profile_active "docmost"' in content:
            # Find the docmost block and add after it
            content = re.sub(
                r'(if is_profile_active "docmost"; then.*?^fi)',
                f'\\1\n{report_block}',
                content,
                count=1,
                flags=re.MULTILINE | re.DOTALL
            )
        else:
            # Fallback: add before paddleocr or python-runner
            if 'is_profile_active "paddleocr"' in content:
                content = re.sub(
                    r'(if is_profile_active "paddleocr")',
                    f'{report_block}\n\\1',
                    content,
                    count=1
                )
            elif 'is_profile_active "python-runner"' in content:
                content = re.sub(
                    r'(if is_profile_active "python-runner")',
                    f'{report_block}\n\\1',
                    content,
                    count=1
                )

        with open(report_file, 'w') as f:
            f.write(content)

        print(f"{Colors.GREEN}✓ Added to final report{Colors.NC}")

    def integrate(self):
        """Run full integration"""
        print(f"\n{Colors.YELLOW}Integrating into n8n-installer...{Colors.NC}\n")

        self.add_to_docker_compose()
        self.add_to_env_example()
        self.add_to_caddyfile()
        self.add_to_wizard()
        self.add_to_secrets()
        self.add_to_final_report()

        print(f"\n{Colors.BLUE}[7/7] Updating README.md...{Colors.NC}")
        print(f"{Colors.YELLOW}⚠ Manual step required: Add {self.service_config['display_name']} to README.md{Colors.NC}")

        print(f"\n{Colors.GREEN}========================================{Colors.NC}")
        print(f"{Colors.GREEN}✓ Integration Complete!{Colors.NC}")
        print(f"{Colors.GREEN}========================================{Colors.NC}\n")

        print(f"{Colors.YELLOW}Next Steps:{Colors.NC}")
        print("1. Review changes: git diff")
        print(f"2. Update README.md (manual)")
        print(f"3. Commit: git commit -am 'Add {self.service_config['display_name']} service'")
        print(f"4. Push: git push origin main\n")

        print(f"{Colors.BLUE}Test with: docker compose --profile {self.service_config['name']} up -d{Colors.NC}\n")

def main():
    parser = argparse.ArgumentParser(description='Analyze and integrate GitHub repos into n8n-installer')
    parser.add_argument('github_url', help='GitHub repository URL')
    parser.add_argument('--auto', action='store_true', help='Auto-confirm integration')
    args = parser.parse_args()

    print(f"{Colors.GREEN}========================================{Colors.NC}")
    print(f"{Colors.GREEN}n8n-installer Service Integration{Colors.NC}")
    print(f"{Colors.GREEN}========================================{Colors.NC}\n")

    # Analyze repository
    analyzer = ServiceAnalyzer(args.github_url)

    try:
        analysis = analyzer.run_analysis()

        print(f"\n{Colors.YELLOW}Analysis Results:{Colors.NC}")
        print(f"  Repository: {analysis['repo_name']}")
        print(f"  Has Docker: {analysis.get('has_dockerfile', False)}")
        print(f"  Has Compose: {analysis.get('has_docker_compose', False)}")
        print(f"  Needs PostgreSQL: {analysis.get('needs_postgres', False)}")
        print(f"  Needs Redis: {analysis.get('needs_redis', False)}")

        if not analysis.get('has_docker_compose') and not analysis.get('has_dockerfile'):
            print(f"\n{Colors.RED}Error: No Docker support found{Colors.NC}")
            return 1

        # Get project root
        script_dir = Path(__file__).parent
        project_root = script_dir.parent

        # Integrate
        integrator = ServiceIntegrator(analysis, project_root)

        if integrator.interactive_config():
            integrator.integrate()
        else:
            print(f"{Colors.RED}Integration cancelled{Colors.NC}")
            return 1

    finally:
        analyzer.cleanup()

    return 0

if __name__ == '__main__':
    sys.exit(main())
