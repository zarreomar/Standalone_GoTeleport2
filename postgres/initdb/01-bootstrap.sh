#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[postgres-init] %s\n' "$*"
}

log "Ensuring Teleport audit database exists"
if ! psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${TELEPORT_AUDIT_DB}'" | grep -q 1; then
  createdb --username "${POSTGRES_USER}" --owner "${POSTGRES_USER}" "${TELEPORT_AUDIT_DB}"
fi

log "Granting replication role to Teleport database user"
psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname postgres <<SQL
ALTER ROLE "${POSTGRES_USER}" WITH REPLICATION;
SQL

log "PostgreSQL bootstrap complete"
