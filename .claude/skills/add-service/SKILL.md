---
name: add-service
description: Use when adding a new service to this homelab repo, or when moving an existing service from docker-volumes/ to services/.
---

# Adding or migrating a homelab service

CLAUDE.md already carries the conventions (layout, Traefik labels, `SERVICE_DOMAIN`, volume
preference, validation, commit format) and is loaded every session. **Do not restate or re-derive
it.** Copy the file shape from `services/calibre-web/compose.yaml`, the current
reference implementation.

This skill covers only what reading the repo does not already tell you.

## Re-evaluate every bind mount, but convert in a separate commit

This repo is actively moving from host mounts to named volumes. On an existing service a bind mount
has to justify itself, and "it was already a bind mount" is not a justification.

**Required output: a storage verdict table.** Every migration report ends with one. Every bind mount
in the file gets a row. None may be omitted, including ones you are leaving alone:

| Mount | Verdict | Why |
|---|---|---|
| `$BASE_VOLUME_DIRECTORY/vikunja/data/files` | Convert | Only Vikunja reads it, no host consumer |

**Keep** requires a named host consumer: media served over Samba or FTP, a path a backup job or
another container reads, config a human edits on the host. Name it. Everything else is **Convert**.

Data safety is never a Keep reason. It is the reason a Convert lands in its own commit.

**The move commit changes no volume key**, whatever the verdict says. Converting orphans live data:
the container starts against an empty volume while the real files sit on the host, unreferenced. A
Convert verdict becomes the *next* commit, and that commit carries the host-side copy in the compose
file header where whoever deploys will see it.

| Rationalization | Reality |
|---|---|
| "Converting would orphan the data, so Keep" | That is why Convert is a separate commit. It is not a reason to keep the bind mount. |
| "The repo prefers named volumes for new services only" | No. Existing services are exactly what the migration is for. |
| "The verdict is Convert, so I'll do it now" | The verdict is a recommendation. The host-side copy runs first, and not in this commit. |
| "I documented the copy command" | In the report, not the artifact. Whoever deploys reads the file. |
| "Docker seeds the volume from the image" | From the image, not from the host bind path. The user's files are not in the image. |

**Red flags. Stop and split the commit:**

- A `volumes:` key changed in a file you also moved.
- You are writing a `docker run ... cp -a` recovery command into a report.
- You are explaining why a data migration is safe.

## The project name is the directory name

Compose derives the project name from the containing directory and namespaces volumes and networks
with it. `docker-volumes/vikunja/` to `services/vikunja/` keeps the name `vikunja`, so
`vikunja_db-data` still resolves. **Renaming the directory orphans every named volume.**

Verify on every move rather than assuming. Render the old file and the new one, and diff the
resolved `volumes:` and `networks:` blocks. They must match.

```bash
git show HEAD:docker-volumes/<name>/docker-compose.yaml > /tmp/before.yaml
# then `docker compose ... config` (see CLAUDE.md) against /tmp/before.yaml and the new path
```

If the directory name has to change, pin the old one with a top-level `name:` key, and say so in a
comment on the volume key.

## Required steps

1. Fetch the upstream compose file and adapt it. Do not invent one.
2. Write the compose file, copying the Traefik label block from `calibre-web`.
3. Validate with `docker compose config` (command in CLAUDE.md). Read the render, do not just check
   the exit code: both `Host()` rules complete, bind sources absolute, no `ports:`.
4. **Add the README.md Services entry.** Required, alphabetical, blockquote description plus links to
   the compose file and upstream docs. Recent commits skipped this and the catalog is now missing six
   services. Do not follow that precedent.
5. Commit. One service per commit. `fix:` for anything that already existed.

## Do not

- **Edit CLAUDE.md as part of a service commit.** If a convention there is stale, report it and leave
  it. That is its own commit.
- **Fix `$LOCAL_DOMAIN_NAME` in other services.** 25 files still reference it. Only touch the one you
  are working on.
- **Deploy.** That happens separately, on the host.
