# Home Lab

Declarative Docker Compose configs for a self-hosted home lab. No build, no tests, no app code —
every change is a compose/config file edit. Deployment happens on the Ubuntu docker host, not here.

## Deploying a service

Always run from the repo root with explicit flags. `cd`-ing into a service dir loses the env files
and Traefik routing breaks:

```bash
docker compose \
  --env-file "./docker-volumes/env-files/common.env" \
  --file "./services/<service>/docker-compose.yaml" up --detach
```

Reworked services live under `services/`; the ones still awaiting a pass are under
`docker-volumes/`. Substitute whichever directory holds the service.

Add a second `--env-file` for services with their own (pi-hole, traefik, postgres, sonarqube, minio).

## Validation

There is no test suite or linter. The only check is:

```bash
docker compose --env-file ./docker-volumes/env-files/common.env \
  --file ./services/<service>/docker-compose.yaml config
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
- HTTP services join the external `proxy` network and publish no ports. Traefik is the only ingress.
  Anything speaking a non-HTTP protocol cannot route through it and publishes ports instead, or uses
  host networking: currently ftp, kafka, mongo, postgres, redis, plus traefik itself, plex for client
  discovery, and dns via `network_mode: host`.
- Routing hostname is `<service>.$SERVICE_DOMAIN`. The `local.` prefix lives inside the value, so the
  label is `` Host(`<service>.$SERVICE_DOMAIN`) `` and never `<service>.local.$SERVICE_DOMAIN`. Copy
  the 11-label Traefik block from `services/dashdot/docker-compose.yaml`. `stirling-pdf` deviates
  with `$SELF_HOSTED_SERVER_URL`; do not copy that one.
- Most services under `docker-volumes/` still reference the removed `$LOCAL_DOMAIN_NAME` and render
  `` Host(`<service>.local.`) `` rather than failing. Fix it in the service being worked on, not
  across the repo.
- Prefer named volumes over bind mounts, on existing services as well as new ones. A bind mount has
  to justify itself with a named host consumer. Re-evaluate every one during a migration, but land
  the conversion as its own commit, since it orphans live data. Bind mounts use
  `$BASE_VOLUME_DIRECTORY/<service>/data/...` and often need a `chown` (grafana 472, prometheus
  65534, pgadmin 5050).
- Document a service's env vars in its compose file: the header says what to set and how to generate
  it, and `${VAR:?message}` makes Compose refuse to start rather than interpolate an empty string.
  Add a `*.env.example` and an `env-files/README.md` row only for services carrying several secrets,
  not for a single variable the compose file already explains.
- Prefer a header comment linking the upstream compose file the config was adapted from. Newer
  services do this; older ones mostly don't.

## Commits

This repo uses sentence-case past tense with a markdown link, overriding the imperative-lowercase
rule in global memory:

    feat: Added docker-compose.yaml for [Service](https://upstream.example.com)

`fix:` for changes to existing services.
