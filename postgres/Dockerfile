FROM postgres:15-bookworm

RUN apt-get update \
  && apt-get install -y --no-install-recommends postgresql-15-wal2json \
  && rm -rf /var/lib/apt/lists/*

COPY initdb/ /docker-entrypoint-initdb.d/
RUN chmod +x /docker-entrypoint-initdb.d/*.sh
