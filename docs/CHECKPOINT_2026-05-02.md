# Checkpoint 2026-05-02

## Scope

This checkpoint captures the PostgreSQL/MinIO deployment rewrite and the Ansible-driven wrapper flow for the GoTeleport repo.

## Completed

- Added a dockerized PostgreSQL backend with `wal2json` support.
- Added MinIO-backed shared session storage for Teleport recordings.
- Updated the Teleport runtime config to be rendered by Ansible into `/opt/datavolume/teleport/teleport.yaml`.
- Turned `scripts/deploy.sh` into a thin wrapper around `ansible/main.yml`.
- Cleaned up host storage paths so `/opt/datavolume` is the canonical host-side storage root.
- Updated docs and validation checks to match the dockerized backend model.

## Current State

- Teleport cluster state and audit events use PostgreSQL inside the stack.
- Session recordings use MinIO via Teleport's S3-compatible storage backend.
- Traefik terminates external TLS and forwards to Teleport's web listener on `:3080`.
- The host-prep flow is still split into:
  - `scripts/prepare_host.sh` for root-only setup
  - `scripts/prepare_host_ubuntu.sh` for the `ubuntu` user Swarm/bootstrap step

## Verification

- `ansible-playbook --check ansible/main.yml -i localhost,` completes successfully.
- Shell scripts pass `bash -n`.
- `git diff --check` is clean.

## Recommended Next Steps

1. Run the full deployment against the target host with the updated Ansible flow.
2. Verify the PostgreSQL and MinIO containers initialize correctly on first boot.
3. Confirm Teleport can authenticate and serve the web API through Traefik.
