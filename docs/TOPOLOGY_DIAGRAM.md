# GoTeleport Docker Swarm Network Topology

## System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         PUBLIC INTERNET                              │
│                         (0.0.0.0/0)                                  │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                    HTTPS (Port 443)
                             │
        ┌────────────────────▼────────────────────┐
        │                                          │
        │    HOST: Docker Swarm Manager            │
        │    ens3 (Public NIC): <public-ip>       │
        │    ens4 (Private NIC): <internal-ip>    │
        │                                          │
        └────────────────────┬────────────────────┘
                             │
        ┌────────────────────┴────────────────────┐
        │                                          │
        ▼                                          ▼
    ┌───────────────────────────┐      ┌──────────────────────┐
    │ ens3 (Public Interface)    │      │ ens4 (Private Iface) │
    │ IP: <public-ip>           │      │ IP: <internal-ip>    │
    │ Gateway: <public-gw>      │      │ Gateway: <vpc-gw>    │
    └───────────────────┬───────┘      └──────────┬───────────┘
                        │                         │
                        │ Table 100: public       │ Table 200: internal
                        │ Routes to Swarm net     │ Routes to VPC net
                        │                         │
        ┌───────────────┴─────────────────────────┴──────────────┐
        │                                                         │
        │    Docker Swarm Overlay Network: teleport-net          │
        │    Subnet: 10.0.9.0/24                                │
        │    Driver: overlay                                     │
        │                                                         │
        │  ┌─────────────────┬──────────────────┬──────────────┐ │
        │  │                 │                  │              │ │
        │  ▼                 ▼                  ▼              ▼ │
        │┌────────────┐ ┌────────────┐ ┌──────────────┐┌────────┐│
        ││ Traefik    │ │ Teleport   │ │  Teleport    ││Teleport││
        ││ (Global)   │ │  Replica 1 │ │  Replica 2   ││Replica3││
        ││            │ │            │ │              ││        ││
        ││ :80        │ │ :3022      │ │  :3022       ││ :3022  ││
        ││ :443       │ │ :3023      │ │  :3023       ││ :3023  ││
        ││ :8080      │ │ :3025      │ │  :3025       ││ :3025  ││
        │└────────────┘ └────────────┘ └──────────────┘└────────┘│
        │     ▲              ▲              ▲              ▲     │
        │     │ Routes HTTPS │              │              │     │
        │     │ to :3080     │              │              │     │
        │     └──────────────┴──────────────┴──────────────┘     │
        │                                                         │
        └─────────────────────────────────────────────────────────┘
                             │
        ┌────────────────────┴────────────────────┐
        │                                          │
        ▼                                          ▼
    ┌──────────────────┐              ┌──────────────────────┐
    │  Storage: Local  │              │  Storage: PostgreSQL │
    │  Volume: certs   │              │  Backend + audit     │
    │  /etc/traefik/   │              │  Cluster state       │
    │  acme.json       │              │  and audit events    │
    └──────────────────┘              └──────────────────────┘
                             │
                             ▼
                   ┌──────────────────────┐
                   │ MinIO S3 Bucket      │
                   │ Session recordings   │
                   └──────────────────────┘
```

---

## Detailed Layer Breakdown

### Layer 1: Public Internet Access

```
┌─────────────────────────────────────────────┐
│  External Clients                           │
│  (SSH, API, Web Browser)                    │
└────────┬────────────────────────────────────┘
         │ HTTPS:443 or SSH:22
         │ Hostname: goteleport.yourdomain.com
         │ DNS Resolution: A record → <public-ip>
         │
         ▼
┌─────────────────────────────────────────────┐
│  Internet Gateway / ISP Router              │
└────────┬────────────────────────────────────┘
         │ NAT (if applicable)
         │
         ▼
┌─────────────────────────────────────────────┐
│  Host's Public Interface (ens3)             │
│  IP: <public-ip>                            │
│  Subnet: <public-subnet>                    │
└─────────────────────────────────────────────┘
```

### Layer 2: Host-Level Routing (Linux iproute2)

```
┌─────────────────────────────────────────────────────────┐
│  Linux Kernel Routing Decision                          │
│                                                         │
│  Source IP from ens3?                                   │
│  ├─ YES → Apply rule priority 100 (public table)       │
│  │         Route to Swarm subnet via ens3              │
│  │                                                      │
│  Source IP from ens4?                                   │
│  ├─ YES → Apply rule priority 200 (internal table)    │
│  │         Route to VPC subnet via ens4               │
│  │                                                      │
│  Default route?                                         │
│  └─ Route to default gateway (ens3)                    │
│                                                         │
└─────────────────────────────────────────────────────────┘
     ▼                                            ▼
  Public Path                              Internal Path
  (ens3 → Swarm)                          (ens4 → Swarm)
     │                                            │
     └────────────────┬─────────────────────────┘
                      │
                      ▼
         ┌────────────────────────┐
         │  Docker Swarm Network  │
         │  (teleport-net overlay)│
         └────────────────────────┘
```

### Layer 3: Docker Swarm Overlay Network

```
┌──────────────────────────────────────────────────────────┐
│  Overlay Network: teleport-net                           │
│  Driver: bridge + vxlan                                  │
│  Subnet: 10.0.9.0/24                                     │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Loadbalancing & Service Discovery               │   │
│  │  (Docker DNS: 127.0.0.11:53)                     │   │
│  │                                                  │   │
│  │  Service Name: gotTeleport_stack_gotTeleport    │   │
│  │  VIP: 10.0.9.X (managed by Swarm)              │   │
│  │  Endpoints: Container IPs (replicas)            │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Ingress Network (Published Ports)                │   │
│  │  - 3022 (SSH Auth)                              │   │
│  │  - 3023 (Proxy - routed via Traefik)            │   │
│  │  - 3025 (Health Check)                          │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### Layer 4: Service Mesh

```
┌─────────────────────────────────────────────────────────┐
│  Traefik Reverse Proxy (Global Mode)                    │
│  Runs on all nodes / Swarm managers                     │
│                                                         │
│  Entrypoints:                                           │
│  ├─ web (:80) → Redirect to websecure                  │
│  └─ websecure (:443)                                   │
│                                                         │
│  Router Rules:                                          │
│  ├─ Host(`goteleport.yourdomain.com`)                 │
│  │  Service: gotTeleport-svc (port 3023)              │
│  │  TLS: ACME (Let's Encrypt)                         │
│  │                                                     │
│  └─ Health Checks: /health (interval 30s)              │
│                                                         │
└──────────┬──────────────────────────────────────────────┘
           │ HTTP Router/Loadbalancer
           │
    ┌──────┴──────┐
    │             │
    ▼             ▼
  ┌─────┐      ┌─────┐
  │ R1  │      │ R2  │
  │:3023│      │:3023│
  └─────┘      └─────┘
    │             │
    └──────┬──────┘
           ▼
      Replica 3
       (:3023)
```

### Layer 5: GoTeleport Services (3 Replicas)

```
┌────────────────────────────────────────────────────────┐
│  Container 1 (Replica 1)                               │
│                                                        │
│  Image: your_registry/teleport:latest                │
│  Network: teleport-net                                │
│                                                        │
│  Ports:                                                │
│  ├─ 3022/tcp (SSH Auth)                              │
│  ├─ 3023/tcp (Proxy - Traefik routed)                │
│  └─ 3025/tcp (Health)                                │
│                                                        │
│  Volumes:                                              │
│  └─ /opt/datavolume/teleport:/var/lib/teleport       │
│                                                        │
│  Health Check:                                         │
│  └─ curl https://localhost:3080/webapi/ping          │
│     interval: 30s, timeout: 10s                       │
│                                                        │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│  Container 2 (Replica 2)    [Identical]               │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│  Container 3 (Replica 3)    [Identical]               │
└────────────────────────────────────────────────────────┘
```

---

## Traffic Flow Paths

### Path 1: External Client via HTTPS

```
Client (Internet)
    ↓
    │ HTTPS:443 → goteleport.yourdomain.com
    │ (DNS resolves to <public-ip> on ens3)
    ▼
Host ens3 Interface
    ↓
    │ Kernel routing (table 100: public)
    │ Routes to Swarm subnet via ens3
    ▼
Traefik Service (Global)
    ├─ Accepts on :443
    ├─ Validates TLS cert
    ├─ Matches Host(`goteleport.yourdomain.com`)
    ├─ Forwards to gotTeleport-svc:3023
    ↓
GoTeleport Replica (loadbalanced)
    ├─ Processes HTTPS request
    ├─ Authenticates client
    ├─ Routes to backend service
    ↓
Response (encrypted via TLS)
    ↓
Traefik
    ↓
Host ens3
    ↓
Client (response received)
```

### Path 2: Internal Client via Private Network

```
Internal Client (VPC network)
    ↓
    │ Request to <internal-ip>:3023
    │ or via overlay network VIP
    ▼
Host ens4 Interface
    ↓
    │ Kernel routing (table 200: internal)
    │ Routes to Swarm subnet via ens4
    ▼
GoTeleport Service VIP (10.0.9.X)
    │
    ├─ Service loadbalancer distributes
    │  among 3 replicas
    ▼
GoTeleport Container
    │
    ├─ Process internal request
    ├─ No TLS termination (direct)
    │
    ▼
Response via ens4 back to internal client
```

### Path 3: SSH Direct Access (3022)

```
SSH Client
    ↓
    │ SSH:3022 → <public-ip>
    ▼
Host ens3 Interface
    ↓
    │ Kernel routing
    │ Ingress loadbalancer
    ▼
GoTeleport SSH Service (Replica)
    ├─ Authenticate via auth service
    ├─ Authorize SSH key
    ├─ Open SSH session
    ↓
Response (SSH protocol)
    ↓
SSH Client (connected)
```

---

## Storage Architecture

```
┌──────────────────────────────────────────┐
│  Docker Named Volumes                    │
└──────────────────────────────────────────┘
        │
        ├─ traefik-certs
        │  └─ /etc/traefik/acme.json
        │     (SSL certificates, Let's Encrypt)
        │     Managed by Traefik service
        │     Persistent across restarts
        │
        ├─ postgres-data
        │  └─ /var/lib/postgresql/data
        │     (Teleport cluster state + audit events backend)
        │
        ├─ minio-data
        │  └─ /data
        │     (shared S3-compatible session recordings)
        │
        └─ /opt/datavolume/teleport
           └─ /var/lib/teleport/
              └─ local runtime cache / spool
```

**Volume Driver:** Bind mounts on the host under `/opt/datavolume/`
**Backing Storage:** `/opt/datavolume/` for Traefik config/certs, PostgreSQL data, Teleport state, and MinIO objects
**Cluster State:** PostgreSQL 13+ with `wal2json` logical decoding
**Replication Strategy:** PostgreSQL provides shared state; MinIO provides shared session replay storage

---

## DNS and Service Discovery

```
┌────────────────────────────────────────────┐
│  External DNS                              │
│                                            │
│  goteleport.yourdomain.com A <public-ip>  │
└────────────────────────────────────────────┘
           ▲
           │ Client DNS query
           │
    ┌──────┴──────────────┐
    │                     │
    ▼                     ▼
Public Client        Internal Client
(Internet)           (VPC)
    │                     │
    └─────────────────────┘
           │
           │ DNS Resolution complete
           │ Connects to public/internal IP
           │
    ┌──────┴──────────────┐
    │                     │
    ▼                     ▼
ens3 (Public)         ens4 (Private)
    │                     │
    └─────────────────────┘
           ▼
    Docker Swarm Network
```

**Internal Service Discovery (Overlay Network):**
```
Container inside overlay network:
  nslookup gotTeleport_stack_gotTeleport
  → 127.0.0.11 (Swarm DNS)
  → Returns VIP: 10.0.9.X
  → Loadbalancer routes to active replica
```

---

## Failure Modes & Resilience

### Scenario 1: Single Replica Fails

```
Before: 3/3 healthy replicas
    ↓
One replica crashes
    ↓
Swarm detects failure (health check timeout)
    ↓
Swarm schedules replacement on healthy node
    ↓
After: 3/3 healthy replicas (new one started)

Client impact: None (if >1 replica available)
Time to recovery: ~30-60 seconds
```

### Scenario 2: Node Failure

```
Before: 3 replicas across 3 nodes
    ↓
Node 1 goes down (network partition)
    ↓
Swarm detects node down (heartbeat timeout)
    ↓
Replicas on Node 1 marked unhealthy
    ↓
Swarm reschedules to healthy nodes
    ↓
After: Services restarted on remaining nodes

Client impact: Brief connection loss (< 10s)
              Automatic reconnection via loadbalancer
Data impact: None (shared storage)
```

### Scenario 3: Traefik Failure

```
Before: Traefik global mode (runs on all nodes)
    ↓
Traefik container crashes
    ↓
Swarm restarts Traefik on same/different node
    ↓
External connectivity briefly interrupted
    ↓
Traefik recovers (internal clients unaffected)

Client impact: External HTTPS unavailable ~10s
Internal impact: None (direct access via VIP)
Time to recovery: ~5-15 seconds
```

---

## Capacity Planning

| Component | 1 Replica | 3 Replicas (HA) |
|-----------|-----------|-----------------|
| CPU (est) | 500m      | 1.5 CPU cores   |
| Memory    | 512 MB    | 1.5 GB          |
| Disk      | 10 GB     | 30 GB (logs)    |
| Bandwidth | ~10 Mbps  | ~30 Mbps        |

**Recommended Production:** 3 replicas across 3+ nodes

---

## Network Policies & Security

```
┌──────────────────────────────────────────────────┐
│  Ingress Rules (Allowed Inbound)                 │
└──────────────────────────────────────────────────┘

ens3 (Public):
  ├─ TCP:80   (Traefik HTTP → HTTPS redirect)
  ├─ TCP:443  (Traefik HTTPS/TLS)
  └─ TCP:3022 (SSH Auth direct access)

ens4 (Private/VPC):
  ├─ TCP:3022 (SSH from VPC clients)
  ├─ TCP:3023 (Proxy from VPC clients)
  └─ TCP:3025 (Health checks from LB)

Swarm Overlay Network:
  └─ All traffic allowed (internal)


┌──────────────────────────────────────────────────┐
│  Egress Rules (Allowed Outbound)                 │
└──────────────────────────────────────────────────┘

ens3:
  └─ DNS (UDP:53), NTP (UDP:123), etc.

Swarm Network:
  ├─ Container-to-container (all ports)
  └─ External DNS (UDP:53)

ACME (Let's Encrypt):
  └─ TCP:80/443 (certificate renewal)
```

---

## Monitoring Touchpoints

```
Monitoring Target         Metric              Tool
────────────────────────────────────────────────────
Service Health            Replicas running    docker service ps
Container Health          Health check status docker inspect
Network Connectivity      Route status        ip route show
Disk Usage                Storage volume      df -h
TLS Certificates          Expiration date     openssl s_client
Service Logs              Errors/Warnings     docker service logs
Swarm Status              Node health         docker node ls
Traffic Flow              Throughput/latency  Traefik dashboard
```

---

## Configuration Variables Reference

```bash
# Host Networking
PUBLIC_IP="<ens3 IP, e.g., 203.0.113.10>"
INTERNAL_IP="<ens4 IP, e.g., 10.100.50.10>"

# DNS & SSL
PUBLIC_DOMAIN="goteleport.yourdomain.com"
ACME_EMAIL="admin@yourdomain.com"

# Docker Registry
REGISTRY_URL="your_registry.azurecr.io"
IMAGE_TAG="latest"

# Subnets
SWARM_SUBNET="10.0.9.0/24"
INTERNAL_SUBNET="172.16.0.0/12"

# Service Config
CLUSTER_NAME="goteleport-prod"
REPLICAS=3
ENVIRONMENT="production"
LOG_SEVERITY="INFO"
```

---

End of Topology Documentation
