---
name: add-service
description: Use when adding a new service to this homelab repo.
---

# Adding a homelab service

CLAUDE.md already carries the conventions (layout, Traefik labels, `SERVICE_DOMAIN`, guards, volume
preference, validation, commit format) and is loaded every session. **Do not restate or re-derive
it.** Copy the file shape from `services/calibre-web/compose.yaml`, the current reference
implementation.

This skill covers only what reading the repo does not already tell you.

## Adapt upstream, do not trust it

Fetch the upstream compose file. Do not invent one from memory, and do not carry it over unread: it
is written to demo the project on a laptop. Relative bind mounts, published ports Traefik should
front, placeholder secrets, and storage under `/tmp` (Kafka and Loki both default there, which looks
fine until the first restart) all arrive looking deliberate.

Check where the image actually writes and what it actually requires rather than believing the compose
file. `docker run --rm --entrypoint sh <image> -c '...'` is cheap.

## Every bind mount needs a named consumer

**Required output: a storage verdict table.** Every report ends with one. Every bind mount in the
file you are writing gets a row, including ones you are keeping:

| Mount | Verdict | Why |
|---|---|---|
| `$BASE_VOLUME_DIRECTORY/plex/media` | Keep | Served to the host over Samba and FTP |
| `/var/run/docker.sock` | Keep | The Docker daemon; not convertible |
| `$BASE_VOLUME_DIRECTORY/beszel/data` | Named volume | Only this service reads it |

**Keep** requires a named host consumer: media served over Samba or FTP, a path a backup job or
another container reads, config a human edits on the host, a host socket. Name it. Everything else is
a named volume.

| Rationalization | Reality |
|---|---|
| "Upstream used a bind mount" | Upstream is demoing on a laptop. That is not a host consumer. |
| "A bind mount makes the data easier to inspect" | `docker volume inspect` and `docker exec` cover that. Not a consumer. |
| "It is under `$BASE_VOLUME_DIRECTORY`, so it is fine" | That makes the path absolute, which is a separate requirement. It does not justify the mount. |
| "The service might need host access later" | Add it when something actually reads it. |

A new service has no live data, so there is nothing to orphan and no reason to split the commit.
Get the volumes right the first time instead.

## The directory name becomes the project name

Compose derives the project name from the containing directory and namespaces volumes and networks
with it, so `services/vikunja/` gives `vikunja_db-data`. Pick the name deliberately: **renaming the
directory later orphans every named volume**, and the fix is pinning the old name with a top-level
`name:` key forever after.

Match the directory to the routing hostname where you can, so `services/beszel/` serves
`beszel.$SERVICE_DOMAIN`.

## Required steps

1. Fetch the upstream compose file and adapt it, per above.
2. Write the compose file, copying the Traefik label block from `calibre-web`.
3. Run `./scripts/validate-compose.sh`. It runs `docker compose config` over every service and
   rejects unguarded variables. Then read your service's render rather than trusting the exit code:
   both `Host()` rules complete, bind sources absolute, no `ports:` on an HTTP service.
4. **Add the README.md Services entry.** Required, alphabetical, blockquote description plus links to
   the compose file and upstream docs. The catalog currently lists every service; keep it that way.
5. Commit. One service per commit, `feat:` for a new one.

## Do not

- **Edit CLAUDE.md as part of a service commit.** If a convention there is stale, report it and leave
  it. That is its own commit.
- **Deploy.** That happens separately, on the host.
