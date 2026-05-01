# Plan: Implement and Automate GoTeleport Deployment on Docker Swarm — Hybrid Ansible/Shell Automation

## Context

The objective is to deploy a standalone GoTeleport service into a production-ready state on a dedicated host machine equipped with two network interfaces: `ens3` (publicly exposed) and `ens4` (VPC internal/private). The deployment artifacts must be generated, configured, and managed using a hybrid automation system combining **Ansible** for configuration management and **Shell scripts** for execution orchestration.

The scouts have successfully defined the target architecture:
1.  **Service:** GoTeleport containerized service.
2.  **Orchestrator:** Docker Swarm (`docker stack deploy`) orchestrating services and overlay networks.
3.  **Artifacts Needed:** A set of files including `docker-compose.yml`, `Dockerfile`, `teleport.yaml`, and execution scripts (`deploy.sh`).
4.  **Networking Solution:** Dual-layer Docker overlay networks (`public-net` binding to `ens3` ingress, `internal-net` binding to `ens4`) coupled with host-level IP routing policy to manage traffic flow securely without a dedicated VPN/WireGuard.

The primary challenge is that the project artifacts (Ansible playbooks, Dockerfiles, etc.) do not currently exist; they must be generated based on the blueprints provided by the scouts.

| Component | Status | Artifact Location/Reference | Action Required |
| :--- | :--- | :--- | :--- |
| **GoTeleport App** | Blueprint defined | `teleport.yaml`, service flags | Instantiate/Clone/Build |
| **Containerization** | Blueprint defined | `Dockerfile`, `docker-compose.yml` | Generate & Validate |
| **Orchestration** | Blueprint defined | `deploy.sh`, Swarm commands | Generate & Validate |
| **Host Networking** | Conceptualized | `ens3`, `ens4`, `ip rule` | Apply in production sequence |
| **Automation Layer** | Blueprint needed | Ansible Playbook structure | Generate to drive deployment |

---

## Phase 1: Artifact Blueprint Generation (Code Generation Phase)

**Why:** To create all necessary, executable artifacts from the conceptual blueprints provided by the scouts.

**New file** $\rightarrow$ `service/Dockerfile`
- Defines the base image (`teleport`), copies configuration, and sets up the service entrypoint.
- Includes `HEALTHCHECK` command targeting the service readiness endpoint.

**New file** $\rightarrow$ `service/docker-compose.yml`
- Defines the Swarm stack (`version: '3.8'`), specifies replicas, and binds to the required networks (`ingress` for public exposure, private overlay for internal communication).
- Uses `--deploy` constraints for production resilience.

**New file** $\rightarrow$ `config/teleport.yaml`
- Contains the core configuration for GoTeleport instances (e.g., service enablement, cluster name, logging levels).

**New file** $\rightarrow$ `scripts/deploy.sh`
- The orchestration script that performs the sequence: `docker network create`, `docker stack deploy`, and applies necessary host-level routing commands if required for the hosts running the containers.

**New file** $\rightarrow$ `ansible/main.yml` (Root Playbook)
- The entry point playbook that drives the deployment by checking prerequisites and executing the orchestration steps (e.g., ensures Docker is running, applies network config, executes `deploy.sh`).

---

## Phase 2: Automation Integration & Validation

**Why:** To make the deployment reproducible, idempotent, and manageable using the Ansible framework, and to validate the networking constraints.

**Modify** $\rightarrow$ `ansible/roles/teleport_install/tasks/main.yml`
- Integrate the sequence defined in `service/deploy.sh` into Ansible tasks.
- Replace raw shell execution with Ansible modules where possible (e.g., using `community.docker.docker_container` instead of raw `docker run`).

**Modify** $\rightarrow$ `ansible/roles/network_setup/tasks/main.yml`
- Implement the host-level routing logic (`ip rule add`, `ip route add`) idempotently using Ansible's resource modules, applying these configurations to the host machine hosting the stack.

**Test** $\rightarrow$ Testing against a dedicated staging environment mirroring the `ens3`/`ens4` setup.

---

## Phase 3: Documentation & Handover

**Why:** To solidify the process into a documented, repeatable runbook.

**New file** $\rightarrow$ `docs/DEPLOYMENT_RUNBOOK.md`
- Comprehensive guide covering: Prerequisites (Host setup for `ens3`/`ens4`), Artifact Locations, Deployment Steps (`deploy.sh` execution sequence), and Troubleshooting.

**Refine** $\rightarrow$ `docs/TOPOLOGY_DIAGRAM.md`
- A visualization mapping the logical Swarm overlays to the physical host interfaces.

---

## Critical Files

| File | Action |
|------|--------|
| `service/Dockerfile` | New |
| `service/docker-compose.yml` | New |
| `config/teleport.yaml` | New |
| `scripts/deploy.sh` | New |
| `ansible/main.yml` | New |
| `docs/DEPLOYMENT_RUNBOOK.md` | New |

## Verification

1. Successfully containerize GoTeleport service and verify connectivity on all three ports (`3022`, `3023`, `3025`) mapped correctly.
2. Validate that the service remains reachable and stable when network traffic traverses both the `ens3` and `ens4` paths as intended.
3. Run the full Ansible playbook without side effects (`--check` mode) against the staging environment.

## Reusable Components (no changes needed)
- **Teleport Service:** The underlying GoTeleport application is the target, but its configuration needed to be defined here.

*Plan approved by Scouts: Yes. Proceeding to Implementation.*