# Environment Variables & .env files

Make sure to update the [.env files](./docker-volumes/env-files) with the appropriate values and rename them to remove the '.example' extension.
Doing this in advance will make it easier to run the docker-compose commands later on.

## Core

### [common.env](./common.env.example)

| Environment Variable / Label | Example                             | Description                                |
|------------------------------|-------------------------------------|--------------------------------------------|
| BASE_VOLUME_DIRECTORY        | /mnt/primary-storage/docker-volumes | Primarily used when defining bind mounts.  |
| LOCAL_DOMAIN_NAME            | example.com                         | Primarily used for Traefik related labels. |

These are custom environment variables that are used across multiple services.

### [pi-hole.env](./pi-hole.env.example)

| Environment Variable / Label | Example              | Description                                     |
|------------------------------|----------------------|-------------------------------------------------|
| WEBPASSWORD                  | some-random-password | The password used to access the pi-hole Web UI. |

Refer to [pi-hole's documentation](https://github.com/pi-hole/docker-pi-hole#environment-variables) for more information about the available environment variables.

### [traefik.env](./traefik.env.example)

| Environment Variable / Label | Example                                                | Description                                                                                                                                                                                                           |
|------------------------------|--------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| CF_API_EMAIL                 | [you@example.com](mailto:you@example.com)              | The email you used to setup your CloudFlare account                                                                                                                                                                   |
| CF_DNS_API_TOKEN             | b9841238feb177a84330febba8a83208921177bffe733          | You can create an API Token on [CloudFlare: Profile -> API Tokens](https://dash.cloudflare.com/profile/api-tokens). Please ensure that the token has the `Zone -> Zone -> Read` and `Zone -> DNS -> Edit` permissions |
| TRAEFIK_BASIC_AUTH           | your-username:$$apr1$$JyS4hrqM$$KDpwRacw7Caga95e.X8Of. | See [Traefik Basic Auth](https://doc.traefik.io/traefik/middlewares/http/basicauth/#basicauth) for more information                                                                                                   |

**Note**: For `TRAEFIK_BASIC_AUTH` You can use the following command to generate a hashed (bcrypt) password:

For additional configuration options, see [go-acme documentation for CloudFlare](https://go-acme.github.io/lego/dns/cloudflare/). Additionally, refer to the
providers section in [traefik's documentation](https://doc.traefik.io/traefik/https/acme/#providers) for more information about other providers.

```bash
#!/usr/bin/env bash

echo $(htpasswd -nb "<your-username>" "<your-plain-text-password>") | sed -e s/\\$/\\$\\$/g
```

#### Traefik Configuration Files

- Create the [acme.json](../traefik/data/acme.json.example) file:
- Ensure that the [acme.json](../traefik/data/acme.json.example) has owner read/write permissions only i.e. [chmod 600](https://chmodcommand.com/chmod-600):

```bash
#!/usr/bin/env bash

touch "./docker-volumes/traefik/data/acme.json"
chmod 600 "$BASE_VOLUME_DIRECTORY/traefik/data/acme.json"
```

In the [traefik.yml](../traefik/data/traefik.yml) file, update the `certificatesResolvers.cloudflare.acme.email` value with your CloudFlare email address:

```yaml
certificatesResolvers:
  cloudflare:
    acme:
      email: 🚨$CF_API_EMAIL🚨
```

In the [config.yml](../traefik/data/config.yml) file:

- $LOCAL_DOMAIN_NAME - Your domain name
- $COCKPIT_SERVER_IP - The IP address of the machine running cockpit
- $ROUTER_IP - The IP address of your router

## Other

### [postgres.env](./postgres.env.example)

| Environment Variable / Label | Example           | Description                                                                              |
|------------------------------|-------------------|------------------------------------------------------------------------------------------|
| POSTGRES_USER                | postgres          | Superuser username                                                                       |
| POSTGRES_PASSWORD            | your-password     | Superuser password for PostgreSQL                                                        |
| PGADMIN_DEFAULT_EMAIL        | admin@example.com | Email address used when setting up the initial administrator account to login to pgAdmin |
| PGADMIN_DEFAULT_PASSWORD     | your-password     | Password used when setting up the initial administrator account to login to pgAdmin      |

Refer to [postgres' documentation](https://hub.docker.com/_/postgres) and
[pgadmin's container deployment documentation](https://www.pgadmin.org/docs/pgadmin4/latest/container_deployment.html#environment-variables) for more information about the available environment variables.

### [sonarqube.env](./sonarqube.env.example)

| Environment Variable / Label | Example          | Description            |
|------------------------------|------------------|------------------------|
| SONAR_JDBC_USERNAME          | sonar            | Database user          |
| SONAR_JDBC_PASSWORD          | your-db-password | Database user password |

Refer to [sonarqube's documentation](https://docs.sonarsource.com/sonarqube/9.9/setup-and-upgrade/configure-and-operate-a-server/environment-variables/) for more information about the available environment variables.