# Checkpoint 2026-05-01

## Scope

This checkpoint captures the host-preparation and documentation pass for the GoTeleport deployment repo.

## Completed

- Added `scripts/prepare_host.sh` to install the missing host prerequisites and configure the deployment baseline.
- Added `scripts/validate.sh` to provide a quick host/deployment validation pass.
- Updated `QUICKSTART.md` with package-install and host-prep instructions.
- Updated `docs/DEPLOYMENT_RUNBOOK.md` with explicit install steps for required packages.
- Updated `docs/VALIDATION_CHECKLIST.md` so the required packages and host-prep helper are part of pre-flight validation.
- Updated `docs/agent-notes.md` with the new host-prep workflow and checkpoint note.

## Required Host Packages

On a fresh Ubuntu target, install:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release iproute2 ufw python3-venv
```

## Recommended Order

1. Install the required packages.
2. Run `sudo bash scripts/prepare_host.sh`.
3. Copy and customize `ansible/group_vars/all.yml`.
4. Run `ansible-playbook -i localhost, -c local ansible/main.yml --check --diff`.
5. Deploy for real once the dry-run output is clean.
