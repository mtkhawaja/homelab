# Home Lab Setup with SSL

I used [Techno Tim's](https://www.youtube.com/@TechnoTim) guide [Put Wildcard Certificates and SSL on EVERYTHING](https://technotim.live/posts/traefik-portainer-ssl) while setting up my home lab.
I highly recommend watching the video and reading his guide. I will be using the same tools and techniques as Tim but will be primarily focusing on documenting my personal setup.

## Prerequisites

- Access to your Router:
    - Used for configuring local DNS and static IP addresses.
    - I use an [RT-AXE7800](https://www.asus.com/networking-iot-servers/wifi-routers/asus-wifi-routers/rt-axe7800/) router.
- A docker host:
    - Refer to [Docker's documentation](https://docs.docker.com/engine/install) for installation instructions.
    - I use [Ubuntu 22.04.3 LTS](https://releases.ubuntu.com/jammy) as my host operating system.
    - See [PC-Part Picker](https://pcpartpicker.com/list/jW6prv) for my server build.
- A domain name that you own:
    - This will cost approximately ~$10 USD per year depending on the domain name.
    - I use [CloudFlare](https://www.cloudflare.com/products/registrar).
- All the necessary env files. See [Environment Variables & .env files](./docker-volumes/env-files/README.md) for more information.

## Conventions

### Service Directory Structure

The following directory structure is used for each service:

```text
service-name/
├── data
│   ├── folder-1
│   ├── folder-2
│   └── ...
└── compose.yaml
```

For multiple services that share the same docker-compose file, the following structure is used instead:

```text
./application-name/
├── service-1
│   └── data
├── service-2
│   └── data
└── compose.yaml
```

The data folder is used for any [bind mounts](https://docs.docker.com/storage/bind-mounts). (You can also use [named volumes](https://docs.docker.com/storage/volumes/) instead).

![high-level-network-diagram](./images/high-level-network-diagram.webp)

## Configure Static IP for the Docker Host

The first step is to configure a static IP address for the docker host so that we don't have to worry about having to update DNS records if the server IP gets re-assigned.

You can run the following command to get the IP address of your docker host:

```bash
#!/usr/bin/env bash

hostname -I

```

Regarding the router configuration, you can follow the instructions provided by ASUS for [assigning a static IP address](https://www.asus.com/support/FAQ/1000906) for their routers. The instructions should be similar for other routers.

## Core Setup

### Docker Network Setup

```bash
#!/usr/bin/env bash

docker network create proxy

```

All services will belong to this network and traefik will route traffic to the appropriate service.
As such, typically, we will **not** be [publishing ports](https://docs.docker.com/network/#published-ports) for our services except for traefik and pi-hole.

### Pi-Hole

#### Ubuntu Specific Configuration

For Ubuntu, the container will fail to start if the `systemd-resolved.service` is running.

As such, as per the [pi-hole documentation](https://github.com/pi-hole/docker-pi-hole#installing-on-ubuntu-or-fedora), you'll need to either disable the stub resolver:

```bash
#!/usr/bin/env bash

# Disable Stub Resolver
sudo sed -r -i.orig 's/#?DNSStubListener=yes/DNSStubListener=no/g' /etc/systemd/resolved.conf
# Update nameserver setting
sudo sh -c 'rm /etc/resolv.conf && ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf'
# Restart the Service
sudo systemctl restart systemd-resolved

```

**Or** disable the `systemd-resolved.service` entirely i.e.

```bash
#!/usr/bin/env bash

sudo systemctl disable systemd-resolved.service
sudo systemctl stop systemd-resolved.service
```

#### Start the Service

Start the [pi-hole service](./services/pi-hole) as follows:

```bash
#!/usr/bin/env bash

docker compose \
  --env-file "./docker-volumes/env-files/common.env" \
  --env-file "./docker-volumes/env-files/pi-hole.env" \
  --file "./services/pi-hole/compose.yaml" up --detach
```

The web UI will be accessible via the following URL: [http://${DOCKER_HOST_IP}/admin](http://localhost/admin)

**Note**: After traefik is up, you can access the web UI via the following URL: [https://pi-hole.$SERVICE_DOMAIN/admin](https://pi-hole.$SERVICE_DOMAIN/admin)

#### Update Router DNS Settings

You'll need to update your router's DNS settings to use the Pi-Hole service after it is up and running.

You can follow the instructions provided by ASUS for [configuring a custom DNS server](https://www.asus.com/support/FAQ/1045253/) for their routers. The instructions should be similar for other routers.

### Traefik

Start the [traefik service](./services/traefik/compose.yaml) as follows:

```shell
#!/usr/bin/env bash

docker compose \
  --env-file "./docker-volumes/env-files/common.env" \
  --env-file "./docker-volumes/env-files/traefik.env" \
  --file "./services/traefik/compose.yaml" up --detach
```

### Portainer

Start the [portainer service](./services/portainer/compose.yaml) as follows:

```bash
#!/usr/bin/env bash

docker compose \
  --env-file "./docker-volumes/env-files/common.env" \
  --file "./services/portainer/compose.yaml" up --detach
```

## Scheduled Host Maintenance

Systemd units that run on the docker host itself (rather than in a container) live under
[systemd/](./systemd), one directory per task. They are not installed by anything in this repo —
copy them to the host and enable them manually:

```bash
#!/usr/bin/env bash

sudo cp ./systemd/docker-prune/docker-prune.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now docker-prune.timer

# Verify
systemctl list-timers docker-prune.timer
```

### Docker Prune

Weekly prune of unused Docker images and build cache.

- [docker-prune.service](./systemd/docker-prune/docker-prune.service)
- [docker-prune.timer](./systemd/docker-prune/docker-prune.timer)
- [docker image prune - Documentation](https://docs.docker.com/reference/cli/docker/image/prune/)

Runs Monday at 04:00, avoiding the Sunday-morning ZFS scrub and `e2scrub_all` windows.

The `until=168h` filter is deliberate: a blind `prune -a` would delete images for any compose stack
that happens to be down that week, forcing a re-pull.

Volume and container pruning are intentionally excluded. `docker volume prune` can destroy live
application data. Container pruning is the subtle one — removing stopped containers makes their
images eligible for the image prune in the same run, so one invocation could cascade well past
intent.

`docker image prune` has no dry-run flag. To see how much is reclaimable beforehand, and to check
the unit after a run:

```bash
#!/usr/bin/env bash

docker system df
sudo systemctl start docker-prune.service   # Trigger manually
journalctl -u docker-prune.service -n 50
```

## Services

For any new service, ensure that the network we created earlier is used and that the following labels are defined:

```yaml 
version: "3.9"
services:
  service-name:
    image: "image-name:latest"
    container_name: "container-name"
    restart: "unless-stopped"
    networks:
      - "proxy"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${SERVICE_NAME}.entrypoints=http"
      - "traefik.http.routers.${SERVICE_NAME}.rule=Host(`${SERVICE_NAME}.$SERVICE_DOMAIN`)"
      - "traefik.http.middlewares.${SERVICE_NAME}-https-redirect.redirectscheme.scheme=https"
      - "traefik.http.routers.${SERVICE_NAME}.middlewares=${SERVICE_NAME}-https-redirect"
      - "traefik.http.routers.${SERVICE_NAME}-secure.entrypoints=https"
      - "traefik.http.routers.${SERVICE_NAME}-secure.rule=Host(`${SERVICE_NAME}.$SERVICE_DOMAIN`)"
      - "traefik.http.routers.${SERVICE_NAME}-secure.tls=true"
      - "traefik.http.routers.${SERVICE_NAME}-secure.service=${SERVICE_NAME}"
      - "traefik.http.services.${SERVICE_NAME}.loadbalancer.server.port=${SERVICE_PORT}"
      - "traefik.docker.network=proxy"
networks:
  proxy:
    external: true
```

**Note:** Include the following label if you [don't want Watchtower to automatically update the container](https://containrrr.dev/watchtower/container-selection/):

```yaml
version: "3.9"
services:
  someimage:
    container_name: someimage
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
```

### Beszel

> Simple, lightweight server monitoring with Docker stats, historical data, and alerts.

Two containers: the hub serving the web UI, and an agent collecting stats from the docker host. The
hub reaches the agent over a unix socket in a shared volume, so the agent listens on no port. The
agent needs the hub's public key, which only exists after the hub has run once, so the first deploy
takes two passes; see the compose file header.

- [compose.yaml](./services/beszel/compose.yaml)
- [Beszel - Getting started](https://beszel.dev/guide/getting-started)
- [Beszel - Agent installation](https://beszel.dev/guide/agent-installation)

### Calibre Web

> Calibre-Web is a web app that offers a clean and intuitive interface for browsing, reading, and downloading eBooks using a valid Calibre database.

- [compose.yaml](./services/calibre-web/compose.yaml)
- [Calibre Web - Installation Instructions](https://docs.linuxserver.io/images/docker-calibre-web/)

### Container Registry

> A stateless, highly scalable server side application that stores and lets you distribute Docker images.

The plain upstream registry. Nexus also serves a container registry, on
`container-registry.$SERVICE_DOMAIN`. Authentication uses a bcrypt htpasswd file generated on the
host; see the compose file header.

- [compose.yaml](./services/registry/compose.yaml)
- [Registry - Dockerhub](https://hub.docker.com/_/registry)
- [Registry - Deployment guide](https://distribution.github.io/distribution/about/deploying/)

### Databasus

> A self-hosted database management and visualisation tool.

- [compose.yaml](./services/databasus/compose.yaml)
- [Databasus - GitHub](https://github.com/databasus/databasus)

### Dashdot

> A modern server dashboard, running on the latest tech, designed with glassmorphism in mind. It is intended to be used for smaller VPS and private servers.

- [compose.yaml](./services/dashdot/compose.yaml)
- [Dashdot - GitHub](https://github.com/MauriceNino/dashdot)
- [Dashdot - Documentation](https://getdashdot.com/docs/installation/docker-compose)

### DNS

> CoreDNS is a DNS server that chains plugins.

Tailnet-only split DNS, so Tailscale clients resolve `*.$SERVICE_DOMAIN` to the docker host. Uses
`network_mode: host` to bind the tailscale0 interface, answers on port 53 rather than HTTP, and so
carries no Traefik labels.

This does **not** replace [Pi-Hole](#pi-hole). The two answer different clients for different
reasons: CoreDNS serves the tailnet and only resolves the lab's own hostnames, while Pi-Hole is the
LAN's resolver and does the ad blocking. Neither is redundant.

Generate the Corefile with
[generate-dns-config.sh](./services/dns/generate-dns-config.sh) before the first start; it holds the
real domain, so it is not kept in git.

- [compose.yaml](./services/dns/compose.yaml)
- [Design and setup notes](./services/dns/TAILSCALE.md)
- [CoreDNS - Manual](https://coredns.io/manual/toc/)

### FTP Server

> A very small and simple Docker image running an FTP server.

Publishes 20-21 for the control and active-data channels, plus 40000-40009 for passive mode, since
Traefik only proxies HTTP. `FTP_PUBLIC_IP` is the address handed to clients for passive connections,
so it has to be one they can reach.

- [compose.yaml](./services/ftp/compose.yaml)
- [FTP Server - Dockerhub](https://hub.docker.com/r/garethflowers/ftp-server)

### Garage

> An open-source distributed object storage service tailored for self-hosting.

S3-compatible object storage, replacing MinIO. Generate `garage.toml` with
[generate-garage-config.sh](./services/garage/generate-garage-config.sh) before the first start; it
holds the RPC secret and admin token, so it is not kept in git.

- [compose.yaml](./services/garage/compose.yaml)
- [Garage - Quick Start](https://garagehq.deuxfleurs.fr/documentation/quick-start/)
- [Garage - Real-world deployment](https://garagehq.deuxfleurs.fr/documentation/cookbook/real-world/)

### Ghost

> The world's most popular modern publishing platform for creating a new media platform.

Ghost plus MySQL. Only Ghost is routed. Ghost stores absolute URLs in post content and email, so
`url` has to match the hostname Traefik publishes.

- [compose.yaml](./services/ghost/compose.yaml)
- [Ghost - Dockerhub](https://hub.docker.com/_/ghost)
- [Ghost - Configuration](https://ghost.org/docs/config/)

### Homarr

> A simple, yet powerful dashboard for your server.

- [compose.yaml](./services/homarr/compose.yaml)
- [Homarr - Installation Instructions](https://homarr.dev/docs/getting-started/installation/docker)

### Jenkins

> The leading open source automation server

Runs the official image directly rather than building a local one. Docker access comes from the
mounted socket plus `group_add`, which needs `DOCKER_GID` set to the host's docker group id:

```bash
#!/usr/bin/env bash

getent group docker | cut -d: -f3
```

Testcontainers talks to the Docker API over that socket and needs no CLI in the container. Pipeline
steps that shell out to `docker`, including `docker.build()`, do need one, so run those on a build
agent. Mounting the socket is equivalent to giving Jenkins root on the host.

- [compose.yaml](./services/jenkins/compose.yaml)
- [Jenkins - Dockerhub](https://hub.docker.com/r/jenkins/jenkins)
- [Testcontainers - Docker environment](https://java.testcontainers.org/supported_docker_environment/)

### Kafka

> A distributed event streaming platform.

A KRaft cluster of three controllers and three brokers. Kafka speaks its own protocol rather than
HTTP, so there are no Traefik labels: the brokers join `proxy` for other stacks to reach at
`kafka-broker-N:19092`, and publish 29092, 39092 and 49092 for LAN clients. `KAFKA_ADVERTISED_HOST`
is the address handed back to clients after the initial handshake, so it has to be one they can
reach.

- [compose.yaml](./services/kafka/compose.yaml)
- [Kafka - Dockerhub](https://hub.docker.com/r/apache/kafka)
- [Kafka - KRaft documentation](https://kafka.apache.org/documentation/#kraft)

### Karakeep

> A self-hostable bookmark-everything app with a touch of AI for the data hoarders out there.

Three containers: the web app plus a headless Chrome for page capture and Meilisearch for full-text
search. Only the web app joins `proxy`. `KARAKEEP_SECRET` and `MEILI_MASTER_KEY` are both required;
rotating the former logs everyone out.

- [compose.yaml](./services/karakeep/compose.yaml)
- [Karakeep - Docker installation](https://docs.karakeep.app/Installation/docker)

### Keycloak

> Open source identity and access management for modern applications and services.

Keycloak plus its own Postgres. Runs in production mode (`start`) rather than `start-dev`, with the
build step at container start so no local image has to be maintained. Traefik terminates TLS, so
`KC_HTTP_ENABLED` is on and `KC_PROXY_HEADERS` is `xforwarded`. The bootstrap admin credentials only
apply on the first start, before an admin account exists.

- [compose.yaml](./services/keycloak/compose.yaml)
- [Keycloak - Running in a container](https://www.keycloak.org/server/containers)
- [Keycloak - Reverse proxy configuration](https://www.keycloak.org/server/reverseproxy)

### Kavita

> Kavita is a fast, feature rich, cross platform reading server.

Manga, comics and books stay bind mounts so the same trees remain reachable over Samba and FTP.

- [compose.yaml](./services/kavita/compose.yaml)
- [Kavita - Installation Instructions](https://wiki.kavitareader.com/installation/docker/)
- [Kavita - Dockerhub](https://hub.docker.com/r/jvmilazz0/kavita)

### Mautic

> Mautic is open-source marketing automation software.

Four containers: the web role, a worker, a cron role and MariaDB. Only the web role is routed.
`MAUTIC_SITE_URL` has to match the hostname Traefik publishes, or tracking pixels and email links
point somewhere unreachable.

- [compose.yaml](./services/mautic/compose.yaml)
- [Mautic - Docker images](https://github.com/mautic/docker-mautic)
- [Mautic - Installation](https://mautic.org/docs/en/getting_started/how_to_install_mautic.html)

### Mongo and Mongo Express

> MongoDB is a source-available, cross-platform, document-oriented database program.

Ships with the mongo-express web UI. The database itself publishes 27017 for LAN access, since
Traefik only proxies HTTP.

- [compose.yaml](./services/mongo/compose.yaml)
- [Mongo - Dockerhub](https://hub.docker.com/_/mongo)
- [Mongo Express - Dockerhub](https://hub.docker.com/_/mongo-express)

### n8n

> A workflow automation platform that combines AI with business process automation.

`N8N_HOST` and `WEBHOOK_URL` have to match the hostname Traefik publishes, or webhook URLs shown in
the editor point somewhere unreachable.

- [compose.yaml](./services/n8n/compose.yaml)
- [n8n - Docker installation](https://docs.n8n.io/hosting/installation/docker/)
- [n8n - Environment variables](https://docs.n8n.io/hosting/configuration/environment-variables/)

### Ollama and Open WebUI

> Open WebUI is an extensible, self-hosted AI interface. Ollama gets up and running with large language models locally.

Served on `ollama.$SERVICE_DOMAIN`, which reaches Open WebUI. Ollama itself carries no Traefik
labels, so other stacks call its API at `http://ollama:11434` over `proxy`. The compose project name
is pinned to `olama` to match the old directory spelling, so the model weights are not orphaned.

- [compose.yaml](./services/ollama/compose.yaml)
- [Open WebUI - Environment variables](https://docs.openwebui.com/getting-started/env-configuration/)
- [Ollama - Dockerhub](https://hub.docker.com/r/ollama/ollama)

### Paperless-ngx

> A community-supported supercharged document management system: scan, index and archive all your physical documents.

Five containers: the webserver plus Postgres, Redis, Gotenberg and Tika. Only the webserver joins
`proxy`; the rest are private to the stack. Documents are dropped into
`$BASE_VOLUME_DIRECTORY/paperless/data/consume` on the host.

- [compose.yaml](./services/paperless/compose.yaml)
- [Paperless-ngx - Setup](https://docs.paperless-ngx.com/setup/)
- [Paperless-ngx - Configuration](https://docs.paperless-ngx.com/configuration/)

### qBittorrent over VPN

> A BitTorrent client, with WireGuard and a kill switch that drops any traffic outside the tunnel.

`QBIT_LAN_NETWORK` is the kill switch's allow list. The compose file appends the docker bridge range
to it, because Traefik reaches the container over `proxy` rather than from the LAN and would
otherwise be firewalled out by the container itself. Drop the WireGuard config at
`$BASE_VOLUME_DIRECTORY/qbit-mullvad/config/wireguard/wg0.conf`; that directory only exists after one
start/stop cycle, so the first run is expected to fail to connect.

Runs `privileged: true`, which the WireGuard path requires. `NET_ADMIN` alone is only enough for
OpenVPN.

- [compose.yaml](./services/qbit/compose.yaml)
- [binhex/arch-qbittorrentvpn - GitHub](https://github.com/binhex/arch-qbittorrentvpn)

### Redis

> The open source, in-memory data store used by millions of developers as a cache, vector database, document database, streaming engine, and message broker.

Publishes 6379 for LAN access, since Traefik only proxies HTTP. `config/redis.conf` and
`scripts/docker-entrypoint-init.sh` have to be copied to `$BASE_VOLUME_DIRECTORY/redis/` on the host
before the first start.

- [compose.yaml](./services/redis/compose.yaml)
- [Redis - Dockerhub](https://hub.docker.com/_/redis)
- [Redis - ACL documentation](https://redis.io/docs/latest/operate/oss_and_stack/management/security/acl/)

### PLG Stack (Prometheus-Loki-Grafana)

- [compose.yaml](./services/plg/compose.yaml)

Five containers in one stack rather than one combined container. `node_exporter` needs the host PID
namespace and a root filesystem mount, and `promtail` needs the Docker socket; merging either would
extend that reach across the rest. Grafana's bind mount needs `chown 472` and Prometheus's needs
`chown 65534` on the host.

Log shipping is [Grafana Alloy](https://grafana.com/docs/alloy/latest/), which replaced Promtail
after Promtail reached end of life on 2 March 2026. Alloy reads container logs through the Docker
API rather than tailing `/var/lib/docker/containers`, so the JSON parsing and tag regex the Promtail
config needed are gone. Its debugging UI is on `alloy.$SERVICE_DOMAIN`.

#### Loki

> Grafana Loki is a horizontally-scalable, highly-available, multi-tenant log aggregation system inspired by Prometheus.

- [Loki - Dockerhub](https://hub.docker.com/r/grafana/loki)
- [Loki - Installation Instructions](https://grafana.com/docs/loki/latest/installation/)
- [Grafana Alloy - Dockerhub](https://hub.docker.com/r/grafana/alloy)
- [Grafana Alloy - Docker installation](https://grafana.com/docs/alloy/latest/set-up/install/docker/)

#### Prometheus

> Prometheus is an open-source systems monitoring and alerting toolkit originally built at SoundCloud.

- [Prometheus - Dockerhub](https://hub.docker.com/r/prom/prometheus)
- [Prometheus - Installation Instructions](https://prometheus.io/docs/prometheus/latest/installation/)
- [Node Exporter - Dockerhub](https://hub.docker.com/r/prom/node-exporter)
- [Node Exporter - Installation Instructions](https://prometheus.io/docs/guides/node-exporter/)

As per [docker's documentation](https://docs.docker.com/config/daemon/prometheus/), you'll need to enable the metrics endpoint in the [daemon.json](https://docs.docker.com/config/daemon/) for Prometheus to work:

```json
{
  "metrics-addr": "127.0.0.1:9323"
}
```

#### Grafana

> Grafana is a multi-platform open source analytics and interactive visualization web application

- [Grafana - Dockerhub](https://hub.docker.com/r/grafana/grafana)
- [Grafana - Installation Instructions](https://grafana.com/docs/grafana/latest/installation/docker/)

#### Fixing Permissions

You may need to fix the permissions if you are using bind mounts:

```shell
#!/usr/bin/env bash

sudo chown -R 472:472 $BASE_VOLUME_DIRECTORY/grafana/data/
sudo chown -R 65534:65534 $BASE_VOLUME_DIRECTORY/prometheus/data/
```

### Nexus Repository Manager

> Nexus by Sonatype is a repository manager that organizes, stores and distributes artifacts needed for development.

Serves two hostnames: the UI on `nexus.$SERVICE_DOMAIN` and its Docker registry connector on
`container-registry.$SERVICE_DOMAIN`. Excluded from Watchtower, since a major upgrade migrates the
database and cannot be rolled back.

- [compose.yaml](./services/nexus/compose.yaml)
- [Nexus Repository Manager - Dockerhub](https://hub.docker.com/r/sonatype/nexus3)

### Plex

> Plex organises all of your personal media so you can enjoy it no matter where you are.

Publishes its own ports as well as sitting behind Traefik: clients on the LAN discover the server by
broadcasting on 1900/udp and the 32410-32414/udp range, which Traefik cannot proxy. Media stays on
bind mounts so it remains reachable over Samba and FTP.

- [compose.yaml](./services/plex/compose.yaml)
- [Plex - Docker images](https://github.com/plexinc/pms-docker)
- [Plex - Installation](https://support.plex.tv/articles/200288586-installation/)

### Pi-Hole

> Network-wide Ad Blocking

The LAN's DNS resolver, and the reason the lab has ad blocking at all. Answers on port 53, which
Traefik cannot proxy, so its ports are published. Separate from [DNS](#dns), which is CoreDNS
serving the tailnet only; keep both.

Excluded from Watchtower: v6 was a breaking release and upgrades here should be deliberate.

- [compose.yaml](./services/pi-hole/compose.yaml)
- [Pi Hole Docker Quick Start](https://github.com/pi-hole/docker-pi-hole/#quick-start)
- [Documentation](https://docs.pi-hole.net/)
- [Firebox Ad Lists](https://firebog.net/)

### Portainer

> Portainer is your container management software to deploy, troubleshoot, and secure applications across cloud, datacenter, and Industrial IoT use cases.

- [compose.yaml](./services/portainer/compose.yaml)
- [Portainer - Installation Instructions](https://docs.portainer.io/start/install-ce)

### Postgres and PgAdmin

- [compose.yaml](./services/postgres/compose.yaml)

> PostgreSQL is a powerful, open source object-relational database system

- [Postgres - Dockerhub](https://hub.docker.com/_/postgres)

> the most popular and feature rich Open Source administration and development platform for PostgreSQL

- [PgAdmin - Dockerhub](https://hub.docker.com/r/dpage/pgadmin4)

Note: With bind mounts, you may need to change the GUI and UID to `5050`.
See [Permission denied: '/var/lib/pgadmin/sessions' in Docker](https://stackoverflow.com/questions/64781245/permission-denied-var-lib-pgadmin-sessions-in-docker) for more information.

```bash
#!/usr/bin/env bash
sudo chown -R 5050:5050 "$BASE_VOLUME_DIRECTORY/admin/data"
```

### SonarQube

> the code quality tool for better code

- [compose.yaml](./services/sonarqube/compose.yaml)
- [SonarQube - Dockerhub](https://hub.docker.com/_/sonarqube)

Note: Ensure that the following key is set in the `/etc/sysctl.conf`:

```text
vm.max_map_count = 262144
```

Then reboot or run the following command:

```bash 
#!/usr/bin/env bash

sysctl -w vm.max_map_count=262144
systemctl restart docker
```

See [What is the parameter "max_map_count" and does it affect the server performance? ](https://access.redhat.com/solutions/99913)
and [Elasticsearch: Max virtual memory areas vm.max_map_count [65530] is too low, increase to at least [262144]](https://stackoverflow.com/questions/51445846/elasticsearch-max-virtual-memory-areas-vm-max-map-count-65530-is-too-low-inc) for more
information.

### Stirling PDF

> A locally hosted web application that allows you to perform various operations on PDF files.

- [compose.yaml](./services/stirling-pdf/compose.yaml)
- [Stirling PDF - Production deployment guide](https://docs.stirlingpdf.com/Production-Deployment-Guide#docker-compose-setup)

### Traefik

> Traefik is the leading open-source reverse proxy and load balancer for HTTP and TCP-based applications that is easy, dynamic and full-featured.

- [compose.yaml](./services/traefik/compose.yaml)
- [Traefik - Dockerhub](https://hub.docker.com/_/traefik)

### Twenty CRM

> A modern CRM offering a powerful, customizable platform, built to be the open-source alternative to Salesforce.

Four containers: the server, a background worker, Postgres and Redis. Only the server is routed;
the rest are private to the stack. `TWENTY_APP_SECRET` signs sessions, so rotating it logs everyone
out.

- [compose.yaml](./services/twenty/compose.yaml)
- [Twenty - Self-hosting with Docker Compose](https://twenty.com/developers/section/self-hosting/docker-compose)
- [Twenty - GitHub](https://github.com/twentyhq/twenty)

### Vikunja

> The open-source, self-hostable to-do app.

Pinned to a specific version rather than `latest`, since major releases run one-way database
migrations on start. Task attachments live on a bind mount under `$BASE_VOLUME_DIRECTORY`.

- [compose.yaml](./services/vikunja/compose.yaml)
- [Vikunja - Full docker example](https://vikunja.io/docs/full-docker-example/)
- [Vikunja - Config options](https://vikunja.io/docs/config-options/)

### Watchtower

> A process for automating Docker container base image updates.

- [compose.yaml](./services/watchtower/compose.yaml)
- [Watchtower - Dockerhub](https://hub.docker.com/r/nickfedor/watchtower)
- [Documentation](https://watchtower.nickfedor.com/)
- [GitHub](https://github.com/nicholas-fedor/watchtower) 
