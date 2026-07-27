# Home Lab

Declarative Docker Compose configs for a self-hosted home lab. No build, no tests, no app code —
every change is a compose/config file edit. Deployment happens on the Ubuntu docker host, not here.

## Deploying a service

Always run from the repo root with explicit flags. `cd`-ing into a service dir loses the env files
and Traefik routing breaks:

```bash
docker compose \
  --env-file "./docker-volumes/env-files/common.env" \
  --file "./docker-volumes/<service>/docker-compose.yaml" up --detach
```

Add a second `--env-file` for services with their own (pi-hole, traefik, postgres, sonarqube, minio).

## Validation

There is no test suite or linter. The only check is:

```bash
docker compose --env-file ./docker-volumes/env-files/common.env \
  --file ./docker-volumes/<service>/docker-compose.yaml config
```

This requires real `.env` files — `docker-volumes/env-files/.gitignore` is `*.env`, so a fresh clone
has only `*.env.example`. Copy and fill them before validating, and never commit the result.

## Conventions

- New and cleaned-up services live under `services/<name>/`. Legacy ones are still under
  `docker-volumes/<name>/` and move to `services/` as they are reworked, so expect both during the
  migration. File is named `docker-compose.yaml` (`karakeep` and `databasus` use `compose.yaml`, so
  glob both when scripting).
- Moving a service dir does not move its host data. Bind mounts are rooted at
  `$BASE_VOLUME_DIRECTORY`, which is a host path independent of the repo layout.
- Bind mounts must use absolute host paths, not relative ones. Relative paths resolve against the
  compose file's directory on the CLI, but inside Portainer's own container for stacks deployed
  there, so they silently point at the wrong place.
- Config needing host-specific values is generated to stdout by a standalone script and saved under
  `$BASE_VOLUME_DIRECTORY` (see `services/dns/generate-dns-config.sh`), keeping real domains out of
  git. Older services instead commit a `🚨`-placeholder template filled in by hand on the host
  (see `docker-volumes/traefik/data/config.yml`).
- No `version:` key. The template in README.md still shows `version: "3.9"`; it is stale.
- Every service joins the external `proxy` network. Do not publish ports — Traefik is the only
  ingress. Exceptions: traefik and pi-hole.
- Routing hostname is `<service>.local.$LOCAL_DOMAIN_NAME`, wired via the 10-label Traefik block
  (copy from an existing service, e.g. `docker-volumes/dashdot/docker-compose.yaml`).
  `stirling-pdf` deviates with `$SELF_HOSTED_SERVER_URL` — do not copy that one.
- Prefer named volumes over bind mounts for new services. Bind mounts use
  `$BASE_VOLUME_DIRECTORY/<service>/data/...` and often need a `chown` (grafana 472, prometheus
  65534, pgadmin 5050).
- New env vars: add a filled row to `docker-volumes/env-files/README.md` and a `*.env.example` entry.
- Prefer a header comment linking the upstream compose file the config was adapted from. Newer
  services do this; older ones mostly don't.

## Commits

This repo uses sentence-case past tense with a markdown link, overriding the imperative-lowercase
rule in global memory:

    feat: Added docker-compose.yaml for [Service](https://upstream.example.com)

`fix:` for changes to existing services.
