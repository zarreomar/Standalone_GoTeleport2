# GoTeleport Docker Swarm - Quick Start Guide

**Estimated Setup Time:** 20-30 minutes  
**Difficulty Level:** Intermediate (requires Linux, Docker, Ansible familiarity)

---

## 5-Minute Setup

### 1. Clone & Prepare

```bash
cd /path/to/Standalone_GoTeleport2

# Copy variable template
cp ansible/group_vars/all.yml.example ansible/group_vars/all.yml

# Edit with your values
vi ansible/group_vars/all.yml
```

### 2. Install Required Packages

On the target Ubuntu host, run:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release iproute2 ufw python3-venv
```

If Docker is not installed yet, run the host-prep helpers from the repo root:

```bash
sudo bash scripts/prepare_host.sh
bash scripts/prepare_host_ubuntu.sh
```

### 3. Configure Essential Variables

```yaml
# Required values to change:
image_name: "public.ecr.aws/gravitational/teleport-distroless:18.7.2"
public_domain: "goteleport.yourdomain.com"
acme_email: "admin@yourdomain.com"
public_ip: "203.0.113.10"           # Your ens3 IP
internal_ip: "10.100.50.10"         # Your ens4 IP
```

### 4. Run Validation

```bash
bash scripts/validate.sh

# All checks should show ✓
# Address any ✗ issues before proceeding
```

### 5. Deploy

```bash
# Option A: Using Ansible (recommended)
ansible-playbook -i localhost, -c local ansible/main.yml

# Option B: Using shell script
bash scripts/deploy.sh
```

### 6. Verify

```bash
# Check service status
docker service ls
docker service ps gotTeleport_stack_gotTeleport

# Test connectivity
curl -k https://goteleport.yourdomain.com
```

---

## Host Prep Script

The repository now includes two host-prep scripts:

Root step:
- `scripts/prepare_host.sh`

Ubuntu user step:
- `scripts/prepare_host_ubuntu.sh`

After the root step, log out and back in as `ubuntu` so the new `docker` group membership is active.

Root script performs:
- Installs Docker Engine and the compose/buildx plugins
- Installs base packages used by the deployment and validation steps
- Creates `/etc/teleport` and `/var/lib/teleport`
- Sets up policy routing persistence for `ens3` and `ens4`
- Opens the required firewall ports with UFW
- Adds the `ubuntu` user to the `docker` group when present

Ubuntu user script performs:
- Verifies Docker is usable from the non-root session
- Initializes Swarm if it is not already active
- Creates the attachable `teleport-net` overlay network

Run them in order when preparing a fresh Ubuntu host:

```bash
sudo bash scripts/prepare_host.sh
bash scripts/prepare_host_ubuntu.sh
```

---

## File Structure Explained

```
.
├── service/                          # Container & Orchestration
│   ├── Dockerfile                   # GoTeleport container image
│   └── docker-compose.yml           # Swarm stack definition (with Traefik)
│
├── config/                           # Service Configuration
│   └── teleport.yaml                # GoTeleport configuration
│
├── ansible/                          # Deployment Automation
│   ├── main.yml                     # Root playbook
│   ├── group_vars/
│   │   ├── all.yml.example          # Variable template (COPY & EDIT)
│   │   └── all.yml                  # Your actual variables
│   └── roles/
│       ├── teleport_install/        # Installation tasks
│       └── network_setup/           # Network configuration
│
├── scripts/
│   ├── deploy.sh                    # Manual deployment script
│   ├── prepare_host.sh              # Root-only host package and baseline prep
│   ├── prepare_host_ubuntu.sh       # Ubuntu user Swarm/bootstrap prep
│   └── validate.sh                  # Pre-deployment validation
│
├── docs/
│   ├── DEPLOYMENT_RUNBOOK.md        # Complete deployment guide
│   ├── TOPOLOGY_DIAGRAM.md          # Network architecture
│   └── VALIDATION_CHECKLIST.md      # Pre-flight checklist
│
└── QUICKSTART.md                    # This file
```

---

## Key Concepts

### Docker Swarm Stack
- **Orchestrator:** Manages container distribution across nodes
- **Services:** Defined in `docker-compose.yml`
- **Replicas:** 3 instances for high availability
- **Networks:** Overlay network for service communication

### Dual Network Interfaces
- **ens3 (Public):** Internet-facing, via Traefik HTTPS proxy
- **ens4 (Private):** VPC/internal access via direct service ports
- **Routing:** Linux `ip rule` and `ip route` manage traffic flow

### Traefik Reverse Proxy
- **Handles:** SSL/TLS termination, HTTP→HTTPS redirect, load balancing
- **Certificates:** Automatic renewal via Let's Encrypt ACME
- **Dashboard:** Available at `traefik.goteleport.yourdomain.com:8080` (localhost only)

---

## Common Tasks

### Scale Up Replicas
```bash
docker service scale gotTeleport_stack_gotTeleport=5
```

### View Real-Time Logs
```bash
docker service logs -f gotTeleport_stack_gotTeleport
```

### Check Service Health
```bash
docker service ps gotTeleport_stack_gotTeleport
```

### Update Configuration
```bash
# Edit config
vi config/teleport.yaml

# Rebuild & redeploy
docker build -t your_registry/teleport:latest service/
docker service update --image your_registry/teleport:latest gotTeleport_stack_gotTeleport
```

### SSH Direct Access
```bash
ssh -p 3022 <username>@<public-ip>
```

### Verify Certificate
```bash
openssl s_client -connect goteleport.yourdomain.com:443 -servername goteleport.yourdomain.com
```

---

## Troubleshooting

### Service Won't Start
```bash
# Check logs
docker service logs gotTeleport_stack_gotTeleport --tail 50

# Check config validity
docker exec $(docker ps -f "label=com.docker.swarm.service.name=gotTeleport_stack_gotTeleport" -q) \
  cat /etc/teleport/teleport.yaml
```

### Can't Reach Service
```bash
# Public access not working?
docker service logs gotTeleport_stack_traefik

# Internal access not working?
ping -I ens4 <internal-ip>
ip route show table internal
```

### Certificate Issues
```bash
# Check ACME status
docker service logs gotTeleport_stack_traefik | grep acme

# Verify DNS
nslookup goteleport.yourdomain.com

# Force renewal
docker volume rm gotTeleport_stack_traefik-certs
docker service update --force gotTeleport_stack_traefik
```

---

## Full Documentation

| Document | Purpose |
|----------|---------|
| **DEPLOYMENT_RUNBOOK.md** | Step-by-step deployment, all options, troubleshooting |
| **TOPOLOGY_DIAGRAM.md** | Network architecture, traffic flows, capacity planning |
| **VALIDATION_CHECKLIST.md** | Pre-flight checks, phase-by-phase validation |

---

## Architecture at a Glance

```
Internet → [ens3: :443] → Traefik → [overlay net] → 3× GoTeleport
            (Public)                               ↓
VPC -----→ [ens4: :3022/3023] ──────────────→ Services
           (Private)
```

---

## What Gets Deployed

| Component | Count | Role |
|-----------|-------|------|
| Traefik | 1 (global) | SSL proxy, HTTP routing |
| GoTeleport | 3 replicas | Auth, Proxy, SSH service |
| Networks | 1 overlay | Service communication |
| Volumes | 2 | Certificates, data persistence |

---

## Security Notes

- ✓ All HTTPS traffic encrypted (TLS 1.3)
- ✓ Automatic certificate renewal (Let's Encrypt)
- ✓ Sensitive data not in config (injected at runtime)
- ✓ Service isolation via overlay network
- ⚠ Firewall rules must allow 80/443 for certificate validation
- ⚠ ens4 access controlled by VPC security groups

---

## Next Steps After Deployment

1. **Test SSH Access**
   ```bash
   ssh -p 3022 <user>@<public-ip>
   ```

2. **Configure Users & Roles**
   - Access web UI: `https://goteleport.yourdomain.com`

3. **Set Up Audit Logging**
   - Check `/var/lib/teleport/log/audit/`

4. **Enable Session Recording**
   - Already configured in `teleport.yaml`

5. **Add to Monitoring**
   - Health endpoint: `https://goteleport.yourdomain.com:3025/health`
   - Service logs: `docker service logs gotTeleport_stack_gotTeleport`

---

## Getting Help

- **Deployment Issues:** See docs/DEPLOYMENT_RUNBOOK.md → Troubleshooting
- **Network Issues:** See docs/TOPOLOGY_DIAGRAM.md → Failure Modes
- **Validation Errors:** See docs/VALIDATION_CHECKLIST.md
- **Service Logs:** `docker service logs -f gotTeleport_stack_<service>`

---

## Key Files to Review Before Deploying

1. **ansible/group_vars/all.yml** - Your deployment variables
2. **service/docker-compose.yml** - Service definitions (includes Traefik)
3. **config/teleport.yaml** - GoTeleport configuration
4. **ansible/main.yml** - Deployment playbook steps

---

**Ready to deploy?** Start with: `bash scripts/validate.sh`
