# Environment Variables & .env files

Copy each `*.env.example` here to the same name without the `.example` extension and fill it in. The
repo-root `.gitignore` ignores `*.env` everywhere, so the filled-in copies never get committed while
the templates stay tracked.

**These files are a convenience, not a contract.** Every compose file lists the variables it needs in
its own header and guards each use with `${VAR:?...}`, so it refuses to start rather than
interpolating an empty string. Where the value actually comes from is your choice: these files, the
shell environment, or Portainer's stack variables. The tables below cover the shared ones; a
service's own header is always the authoritative list for that service.

## Core

### [common.env](./common.env.example)

Used by nearly every service.

| Variable | Example | Description |
|---|---|---|
| `BASE_VOLUME_DIRECTORY` | `/mnt/primary-storage/docker-volumes` | Host directory all bind mounts are rooted at. Independent of the repo layout. |
| `SERVICE_DOMAIN` | `local.example.com` | The domain services are published under. Traefik labels are written ``Host(`<service>.$SERVICE_DOMAIN`)``, so the `local.` prefix lives in this value rather than being repeated in every label. |

### [traefik.env](./traefik.env.example)

| Variable | Example | Description |
|---|---|---|
| `CF_API_EMAIL` | `you@example.com` | The email on your Cloudflare account. |
| `CF_DNS_API_TOKEN` | `b9841238feb177a84330febba8a83208921177bffe733` | Create one at [Cloudflare: Profile -> API Tokens](https://dash.cloudflare.com/profile/api-tokens). It needs `Zone -> Zone -> Read` and `Zone -> DNS -> Edit`. |
| `TRAEFIK_BASIC_AUTH` | `admin:$$2y$$05$$abcdefghij` | htpasswd line guarding the dashboard. See [Traefik Basic Auth](https://doc.traefik.io/traefik/middlewares/http/basicauth/#basicauth). |

Generate the hash, doubling every `$` on the way in:

```bash
#!/usr/bin/env bash

htpasswd -nbB "<your-username>" "<your-plain-text-password>" | sed -e 's/\$/\$\$/g'
```

The doubling is not cosmetic. Compose interpolates `$`-sequences in values it reads from an
`--env-file`, so an unescaped bcrypt hash gets truncated at whichever segment happens to look like a
variable name, and the dashboard then rejects every password. Check the result with
`docker compose --env-file ... --file ./services/traefik/compose.yaml config` and confirm the hash
still ends where it should.

For other DNS providers see the [go-acme Cloudflare docs](https://go-acme.github.io/lego/dns/cloudflare/)
and Traefik's [ACME providers](https://doc.traefik.io/traefik/https/acme/#providers).

#### Traefik configuration files

`acme.json` stores the issued certificates and the ACME account key. Traefik refuses to use it unless
it is owner-read/write only. Create it on the host, under `$BASE_VOLUME_DIRECTORY`, not in the repo:

```bash
#!/usr/bin/env bash

install -m 600 /dev/null "$BASE_VOLUME_DIRECTORY/traefik/data/acme.json"
```

[traefik.yml](../traefik/data/traefik.yml) and [config.yml](../traefik/data/config.yml) are templates
carrying 🚨 placeholders. Copy them to `$BASE_VOLUME_DIRECTORY/traefik/data/` and fill them in there,
so the real values stay out of git:

- `traefik.yml` — `certificatesResolvers.cloudflare.acme.email`, your Cloudflare email.
- `config.yml` — `$SERVICE_DOMAIN`, plus `$COCKPIT_SERVER_IP`, `$ROUTER_IP` and
  `$DOCKER_HOST_METRICS_IP` for the non-container services it routes to.

### [pi-hole.env](./pi-hole.env.example)

| Variable | Example | Description |
|---|---|---|
| `PI_HOLE_WEB_UI_PASSWORD` | `some-random-password` | Admin password for the Pi-hole web interface. |

Passed to the container as `FTLCONF_webserver_api_password`. Pi-hole v6 renamed it from
`WEBPASSWORD`, which the current image silently ignores. See
[pi-hole's documentation](https://github.com/pi-hole/docker-pi-hole#environment-variables).

## Other

### [postgres.env](./postgres.env.example)

The shared Postgres instance and pgAdmin. Services that bundle their own database use their own
names — `PAPERLESS_DB_*`, `TWENTY_DB_*`, `VIKUNJA_DB_*` and so on — precisely so that setting these
does not reach into those stacks.

| Variable | Example | Description |
|---|---|---|
| `POSTGRES_USER` | `postgres` | Superuser username. |
| `POSTGRES_PASSWORD` | `your-password` | Superuser password. |
| `PGADMIN_DEFAULT_EMAIL` | `admin@example.com` | Login for the initial pgAdmin administrator. |
| `PGADMIN_DEFAULT_PASSWORD` | `your-password` | Password for that account. |

Postgres only applies the first two while initialising an empty data directory. On an existing
deployment they must match what the role was created with; changing them here just fails to
authenticate. Rotate with `ALTER ROLE` instead. See
[postgres](https://hub.docker.com/_/postgres) and
[pgAdmin](https://www.pgadmin.org/docs/pgadmin4/latest/container_deployment.html#environment-variables).

### [sonarqube.env](./sonarqube.env.example)

| Variable | Example | Description |
|---|---|---|
| `SONARQUBE_DB_USER` | `postgres` | Role owning SonarQube's bundled database. |
| `SONARQUBE_DB_PASSWORD` | `your-password` | Password for that role. |

The same caveat about an existing data directory applies. See
[sonarqube's documentation](https://docs.sonarsource.com/sonarqube-server/latest/setup-and-upgrade/configuration/environment-variables/).

## Not an env file

`daemon.json` is Docker daemon configuration, not a compose variable file. It sets
`metrics-addr` so the daemon exposes Prometheus metrics for the PLG stack to scrape. It belongs at
`/etc/docker/daemon.json` on the host and is kept here only because that is where it has always
lived.
