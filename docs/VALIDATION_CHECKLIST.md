# Pre-Deployment Validation Checklist

## Phase 1: Infrastructure Validation

### Network Interfaces
- [ ] Host has two network interfaces configured
  ```bash
  ip link show | grep -E "ens3|ens4"
  ```

- [ ] Public interface (ens3) has internet connectivity
  ```bash
  ping -I ens3 8.8.8.8
  ```

- [ ] Private interface (ens4) has VPC/internal connectivity
  ```bash
  ping -I ens4 <internal-gateway-ip>
  ```

- [ ] Both interfaces have static IPs assigned
  ```bash
  ip addr show ens3 | grep "inet "
  ip addr show ens4 | grep "inet "
  ```

### Firewall & Security Groups
- [ ] Security group allows inbound on port 80 (HTTP)
- [ ] Security group allows inbound on port 443 (HTTPS)
- [ ] Security group allows inbound on port 3022 (SSH)
- [ ] Security group allows inbound on port 3025 (Health)
- [ ] NACLs don't block Docker Swarm overlay traffic (VXLAN UDP 4789)

### Storage & Disk Space
- [ ] Minimum 50GB available on /var/lib
  ```bash
  df -h /var/lib | tail -1
  ```

- [ ] Directory permissions set correctly
  ```bash
  ls -la /var/lib/teleport 2>/dev/null || echo "Directory will be created"
  ```

- [ ] No mount point issues
  ```bash
  mount | grep "/var/lib"
  ```

---

## Phase 2: Docker Installation & Configuration

### Required Host Packages
- [ ] Base packages are installed
  ```bash
  dpkg -l | grep -E 'ca-certificates|curl|gnupg|lsb-release|iproute2|ufw|python3-venv'
  ```

- [ ] Docker helper script is available
  ```bash
  test -x scripts/prepare_host.sh && echo "✓ prepare_host.sh present"
  test -x scripts/prepare_host_ubuntu.sh && echo "✓ prepare_host_ubuntu.sh present"
  ```

### Docker Daemon
- [ ] Docker is installed and running
  ```bash
  docker --version && docker info
  ```

- [ ] Docker Swarm mode is initialized
  ```bash
  docker info | grep "Swarm.*active"
  ```

- [ ] Current user can run Docker commands (or sudo configured)
  ```bash
  docker ps
  ```

- [ ] Docker daemon has sufficient resources
  ```bash
  docker info | grep -E "Containers|Images|Storage"
  ```

### Docker Networking
- [ ] Overlay network driver is available
  ```bash
  docker run --rm busybox ping -c 1 8.8.8.8
  ```

- [ ] No conflicting networks
  ```bash
  docker network ls | grep -i teleport
  ```

- [ ] VXLAN support enabled (kernel module loaded)
  ```bash
  modinfo vxlan 2>/dev/null || lsmod | grep vxlan
  ```

---

## Phase 3: DNS & Domain Configuration

### Domain Configuration
- [ ] Public domain is registered
  ```bash
  whois goteleport.yourdomain.com
  ```

- [ ] DNS A record points to public IP (ens3)
  ```bash
  nslookup goteleport.yourdomain.com
  # Should return <public-ip>
  ```

- [ ] DNS TTL is reasonable (not too high)
  ```bash
  dig goteleport.yourdomain.com +nocmd +noall +answer
  ```

- [ ] External DNS propagation verified
  ```bash
  # Check from external host
  nslookup goteleport.yourdomain.com 8.8.8.8
  ```

### Wildcard DNS (Optional, for Traefik Dashboard)
- [ ] Wildcard DNS configured (if needed)
  ```bash
  nslookup traefik.goteleport.yourdomain.com
  ```

---

## Phase 4: File Structure & Artifacts

### Required Files Present
- [ ] `service/Dockerfile` exists and is valid
  ```bash
  test -f service/Dockerfile && echo "✓ Dockerfile present"
  ```

- [ ] `service/docker-compose.yml` exists and is valid
  ```bash
  docker-compose -f service/docker-compose.yml config > /dev/null && echo "✓ Valid"
  ```

- [ ] `config/teleport.yaml` exists
  ```bash
  test -f config/teleport.yaml && echo "✓ Config present"
  ```

- [ ] `scripts/deploy.sh` is executable
  ```bash
  test -x scripts/deploy.sh && echo "✓ Executable"
  ```

- [ ] Ansible files present
  ```bash
  test -f ansible/main.yml && test -d ansible/roles && echo "✓ Ansible ready"
  ```

### Documentation Present
- [ ] DEPLOYMENT_RUNBOOK.md exists
  ```bash
  test -f docs/DEPLOYMENT_RUNBOOK.md && echo "✓ Runbook present"
  ```

- [ ] TOPOLOGY_DIAGRAM.md exists
  ```bash
  test -f docs/TOPOLOGY_DIAGRAM.md && echo "✓ Topology diagram present"
  ```

---

## Phase 5: Configuration Validation

### Docker Compose Validation
- [ ] All image references are valid
  ```bash
  grep -i "image:" service/docker-compose.yml
  # Verify they exist in your registry
  ```

- [ ] All port numbers are unique and available
  ```bash
  docker-compose -f service/docker-compose.yml config | grep -A 5 "ports:"
  ```

- [ ] Volume names don't conflict
  ```bash
  docker volume ls | grep -E "traefik|teleport"
  ```

### Teleport Configuration
- [ ] `teleport.yaml` has valid YAML syntax
  ```bash
  python3 -c "import yaml; yaml.safe_load(open('config/teleport.yaml'))"
  ```

- [ ] All required services are enabled
  ```bash
  grep -E "enabled.*yes" config/teleport.yaml
  ```

- [ ] Data directory path is set
  ```bash
  grep "directory:" config/teleport.yaml
  ```

### Ansible Configuration
- [ ] Variables template copied to `ansible/group_vars/all.yml`
  ```bash
  test -f ansible/group_vars/all.yml || echo "Copy all.yml.example to all.yml"
  ```

- [ ] All placeholder values replaced
  ```bash
  grep "your_" ansible/group_vars/all.yml && echo "⚠ Placeholders found"
  ```

- [ ] Ansible syntax is valid
  ```bash
  ansible-playbook --syntax-check ansible/main.yml
  ```

---

## Phase 6: Dependency Check

### Required CLI Tools
- [ ] Docker CLI installed
  ```bash
  which docker && docker --version
  ```

- [ ] Docker Compose V2 (buildx, etc.) installed
  ```bash
  docker version -f "{{.Server.Version}}"
  ```

- [ ] curl installed (for health checks)
  ```bash
  which curl && curl --version
  ```

- [ ] grep, awk, sed available
  ```bash
  which grep awk sed
  ```

### Optional but Recommended
- [ ] jq installed (for JSON parsing)
  ```bash
  which jq
  ```

- [ ] htop or monitoring tool
  ```bash
  which htop
  ```

- [ ] Ansible installed (if using playbook deployment)
  ```bash
  ansible --version
  ```

---

## Phase 7: Security Validation

### Certificate & SSL
- [ ] ACME email is valid
  ```bash
  grep "acme_email:" ansible/group_vars/all.yml
  ```

- [ ] TLS ports (443) are open
  ```bash
  sudo netstat -tlnp | grep 443
  ```

- [ ] Let's Encrypt staging vs production configured correctly
  ```bash
  grep -i "letsencrypt" service/docker-compose.yml
  ```

### Access Control
- [ ] SSH key authentication configured (not password)
- [ ] Sudo access properly configured for Docker operations
- [ ] No hard-coded passwords in config files
  ```bash
  grep -r "password.*:.*" config/ ansible/ | grep -v "^#"
  ```

### Network Security
- [ ] No public SSH on default port 22
  ```bash
  sudo netstat -tlnp | grep ":22"
  ```

- [ ] Firewall allows only required ports
  ```bash
  sudo ufw status | grep "3022\|3023\|3025\|80\|443"
  ```

---

## Phase 8: Resource Check

### Compute Resources
- [ ] At least 2 CPU cores available
  ```bash
  nproc
  ```

- [ ] At least 2GB RAM available
  ```bash
  free -h | grep "^Mem"
  ```

- [ ] Sufficient swap configured (at least 1GB)
  ```bash
  free -h | grep "^Swap"
  ```

### Docker Resource Limits
- [ ] Memory limit not too restrictive
  ```bash
  docker info | grep "Memory"
  ```

- [ ] No storage quotas preventing image pulls
  ```bash
  docker system df
  ```

---

## Phase 9: Connectivity Tests

### Internal Connectivity
- [ ] Ping Docker gateway
  ```bash
  docker run --rm alpine ping -c 1 172.17.0.1
  ```

- [ ] Resolve internal Docker DNS
  ```bash
  docker run --rm alpine nslookup docker.com
  ```

### External Connectivity
- [ ] Outbound HTTPS works (for pulling images)
  ```bash
  docker run --rm alpine wget -q -O - https://www.google.com > /dev/null && echo "✓ HTTPS OK"
  ```

- [ ] DNS resolution works
  ```bash
  docker run --rm alpine nslookup goteleport.yourdomain.com
  ```

---

## Phase 10: Pre-Deployment Dry Run

### Ansible Check Mode
- [ ] Run Ansible in check mode (no changes)
  ```bash
  ansible-playbook -i localhost, -c local ansible/main.yml --check --diff
  ```

- [ ] Host prep script has been reviewed or executed on the target host
  ```bash
  test -x scripts/prepare_host.sh && echo "✓ prepare_host.sh present"
  test -x scripts/prepare_host_ubuntu.sh && echo "✓ prepare_host_ubuntu.sh present"
  ```

- [ ] Review what changes will be made
- [ ] No errors in check mode output

### Manual Deployment Test (Optional)
- [ ] Run deploy.sh manually in a test environment
- [ ] Verify all steps execute without errors
- [ ] Verify stack comes up correctly

---

## Validation Summary

| Phase | Status | Notes |
|-------|--------|-------|
| Infrastructure | [ ] | |
| Docker | [ ] | |
| DNS | [ ] | |
| Artifacts | [ ] | |
| Configuration | [ ] | |
| Dependencies | [ ] | |
| Security | [ ] | |
| Resources | [ ] | |
| Connectivity | [ ] | |
| Dry Run | [ ] | |

---

## Quick Validation Script

```bash
#!/bin/bash
# Quick validation of all prerequisites

echo "=== GoTeleport Pre-Deployment Validation ==="

# Check interfaces
echo "[1/10] Checking network interfaces..."
ip link show ens3 >/dev/null && echo "✓ ens3 found" || echo "✗ ens3 missing"
ip link show ens4 >/dev/null && echo "✓ ens4 found" || echo "✗ ens4 missing"

# Check Docker
echo "[2/10] Checking Docker..."
docker info >/dev/null 2>&1 && echo "✓ Docker running" || echo "✗ Docker not running"
docker info | grep "Swarm.*active" >/dev/null && echo "✓ Swarm active" || echo "✗ Swarm not active"

# Check DNS
echo "[3/10] Checking DNS..."
nslookup goteleport.yourdomain.com >/dev/null 2>&1 && echo "✓ DNS resolves" || echo "✗ DNS not resolving"

# Check files
echo "[4/10] Checking artifacts..."
test -f service/Dockerfile && echo "✓ Dockerfile" || echo "✗ Dockerfile"
test -f service/docker-compose.yml && echo "✓ docker-compose.yml" || echo "✗ docker-compose.yml"
test -f config/teleport.yaml && echo "✓ teleport.yaml" || echo "✗ teleport.yaml"

# Check disk space
echo "[5/10] Checking disk space..."
SPACE=$(df /var/lib | tail -1 | awk '{print $4}')
if [ "$SPACE" -gt 51200000 ]; then
  echo "✓ Sufficient space: ${SPACE}K"
else
  echo "✗ Insufficient space: ${SPACE}K"
fi

# Check ports
echo "[6/10] Checking ports..."
! lsof -i :80 >/dev/null 2>&1 && echo "✓ Port 80 free" || echo "✗ Port 80 in use"
! lsof -i :443 >/dev/null 2>&1 && echo "✓ Port 443 free" || echo "✗ Port 443 in use"

# Check config
echo "[7/10] Checking configuration..."
test -f ansible/group_vars/all.yml && echo "✓ Ansible variables" || echo "✗ Ansible variables"
docker-compose -f service/docker-compose.yml config >/dev/null 2>&1 && echo "✓ Compose valid" || echo "✗ Compose invalid"

# Check resources
echo "[8/10] Checking resources..."
CPUS=$(nproc)
[ "$CPUS" -ge 2 ] && echo "✓ CPUs: $CPUS" || echo "✗ CPUs: $CPUS (need 2+)"
MEM=$(free -m | grep "^Mem" | awk '{print $2}')
[ "$MEM" -ge 2048 ] && echo "✓ Memory: ${MEM}MB" || echo "✗ Memory: ${MEM}MB (need 2048+)"

# Check connectivity
echo "[9/10] Checking connectivity..."
docker run --rm alpine ping -c 1 8.8.8.8 >/dev/null 2>&1 && echo "✓ Outbound HTTPS" || echo "✗ No outbound connectivity"

# Final summary
echo "[10/10] Summary"
echo "=== Ready to deploy? Review any ✗ items above ==="
```

Save this as `scripts/validate.sh`, run `chmod +x scripts/validate.sh`, then execute with `bash scripts/validate.sh`

---

## Next Steps

Once all items are checked:
1. Review DEPLOYMENT_RUNBOOK.md for detailed instructions
2. Run Ansible playbook: `ansible-playbook -i localhost, -c local ansible/main.yml`
3. Or manually run: `bash scripts/deploy.sh`
4. Monitor logs: `docker service logs gotTeleport_stack_gotTeleport`
