# Home Lab

Declarative Docker Compose configs for a self-hosted home lab. No build, no tests, no app code —
every change is a compose/config file edit. Deployment happens on the Ubuntu docker host, not here.

## Deploying a service

Always run from the repo root with explicit flags. `cd`-ing into a service dir loses the env files
and Traefik routing breaks:

```bash
docker compose \
  --env-file "./docker-volumes/env-files/common.env" \
  --file "./services/<service>/compose.yaml" up --detach
```

Every service lives under `services/`. `docker-volumes/` now holds only `env-files/`.

Add a second `--env-file` for services with their own (pi-hole, traefik, postgres, sonarqube).

## Validation

There is no test suite or linter. The only check is:

```bash
docker compose --env-file ./docker-volumes/env-files/common.env \
  --file ./services/<service>/compose.yaml config
```

This requires real `.env` files — `docker-volumes/env-files/.gitignore` is `*.env`, so a fresh clone
has only `*.env.example`. Copy and fill them before validating, and never commit the result.

## Conventions

- Services live under `services/<name>/`, one directory each, and the file is always named
  `compose.yaml` — the name the Compose Spec defines and Docker looks for first.
  `docker-compose.yaml` is the legacy fallback and no longer appears in this repo, so there is
  nothing left to glob for. `docker-volumes/` holds only `env-files/`; nothing else belongs there.
- Moving a service dir does not move its host data. Bind mounts are rooted at
  `$BASE_VOLUME_DIRECTORY`, which is a host path independent of the repo layout.
- Bind mounts must use absolute host paths, not relative ones. Relative paths resolve against the
  compose file's directory on the CLI, but inside Portainer's own container for stacks deployed
  there, so they silently point at the wrong place.
- Config needing host-specific values is generated to stdout by a standalone script and saved under
  `$BASE_VOLUME_DIRECTORY` (see `services/dns/generate-dns-config.sh`), keeping real domains out of
  git. Traefik instead commits a `🚨`-placeholder template filled in by hand on the host
  (see `services/traefik/data/config.yml`); either shape is fine, but the real values never land in
  git.
- No `version:` key. The template in README.md still shows `version: "3.9"`; it is stale.
- Anything other stacks consume joins the external `proxy` network. That is how services reach each
  other, by container name, as well as how Traefik reaches them. Do not isolate a shared service:
  `postgres`, `mongo` and `redis` are reached over `proxy` by things outside this repo.
- Components bundled inside one stack are the exception, and stay on a private bridge network with
  only the web-facing container bridging to `proxy`. `paperless` (db, broker, gotenberg, tika) and
  `karakeep` (chrome, meilisearch) are built this way. The test is whether anything outside the stack
  has a reason to reach it.
- HTTP services publish no ports, since Traefik is the only ingress for them. A service speaking a
  non-HTTP protocol still joins `proxy`, carries no Traefik labels, and additionally publishes a port
  when it has to be reachable from the LAN: ftp, kafka, mongo, postgres, redis, plus traefik itself
  and plex for client discovery. Two use `network_mode: host` instead: `dns`, and `beszel-agent`
  because it reports the host's network interface throughput and on a bridge network would see only
  its own veth pair. Host mode is for reading the host's own networking, not for convenience.
- Routing hostname is `<service>.$SERVICE_DOMAIN`. The `local.` prefix lives inside the value, so the
  label is `` Host(`<service>.$SERVICE_DOMAIN`) `` and never `<service>.local.$SERVICE_DOMAIN`. Copy
  the 11-label Traefik block from `services/dashdot/compose.yaml`. Every service now uses
  `$SERVICE_DOMAIN`; there are no remaining deviations to copy by accident.
- `$LOCAL_DOMAIN_NAME` is gone from the repo. It was removed from the env files long before the
  services stopped referencing it, and because Compose interpolates a missing variable to an empty
  string, every one of them rendered `` Host(`<service>.local.`) `` and silently stopped routing
  instead of failing. That is what the `${VAR:?}` guards below exist to prevent.
- Prefer named volumes over bind mounts, on existing services as well as new ones. A bind mount has
  to justify itself with a named host consumer. Re-evaluate every one during a migration, but land
  the conversion as its own commit, since it orphans live data. Bind mounts use
  `$BASE_VOLUME_DIRECTORY/<service>/data/...` and often need a `chown` (grafana 472, prometheus
  65534, pgadmin 5050).
- **Compose files are self-contained and must not depend on a particular env file.** List every
  variable a service needs in its own header, with a one-line description each, and guard each use
  with `${VAR:?required - <what the variable is>}`. Compose then refuses to start rather than
  interpolating an empty string, which is how `Host(`<service>.local.`)` shipped unnoticed. Guard
  `SERVICE_DOMAIN` in the Traefik labels too, not just secrets.
- The guard message says what the variable *is*, never where to put it. The value may come from
  `common.env`, a second `--env-file`, the shell, or Portainer's stack variables, and that is the
  deployer's choice. A `*.env.example` is an optional convenience, never something a compose file
  asserts.
- Quote any `environment:` entry containing a guard. A `: ` inside the message makes YAML parse the
  list item as a map and Compose fails with `unexpected type map[string]interface {}`. Use `-`
  rather than `:` in guard messages.
- Prefer a header comment linking the upstream compose file the config was adapted from. Newer
  services do this; older ones mostly don't.

## Commits

This repo uses sentence-case past tense with a markdown link, overriding the imperative-lowercase
rule in global memory:

    feat: Added compose.yaml for [Service](https://upstream.example.com)

`fix:` for changes to existing services.
