# Tailscale

Remote access to the home lab over [Tailscale](https://tailscale.com), keeping one URL per service
that works on the LAN with no VPN connected, and from anywhere over the tailnet.

Tailscale itself runs on the docker host, not in a container. The resolver that makes this work is a
container: [docker-compose.yaml](./docker-compose.yaml).

## The problem

Public DNS gives one answer to everyone. `plex.local.example.com` resolves to the docker host's LAN
address (e.g. `192.168.x.y`) whether you are at home or in another country. On the LAN that address
is directly reachable. Anywhere else it is meaningless, because the address is private space reserved
by RFC 1918 [[9]](#sources) and is not routed across the internet.

It is the equivalent of directions that say "third door on the left": correct inside the house,
useless from across town.

## The approach: split DNS

Keep two answers for the same name, and let each client get the one that is correct for where it is.
The URL stays the same in every case; only the address behind it changes.

| Asking from | Resolved by | Answer | Path |
|---|---|---|---|
| LAN, VPN off | Public DNS | LAN address | Direct on the local network |
| LAN, VPN on | Tailscale split DNS | Tailnet address | Usually a direct peer-to-peer link over the LAN [[10]](#sources) |
| Remote, VPN on | Tailscale split DNS | Tailnet address | Over the tailnet |
| Remote, VPN off | Public DNS | LAN address | Unreachable, as expected |

## How the pieces fit

```
Public DNS (Cloudflare)   *.$SERVICE_DOMAIN → 192.168.x.y   (LAN address)     [unchanged]
CoreDNS on tailscale0     *.$SERVICE_DOMAIN → 100.x.y.z     (tailnet address)
Tailscale admin console   restricted nameserver 100.x.y.z, limited to $SERVICE_DOMAIN
```

A restricted nameserver "only applies to DNS queries matching a specific search domain. Using a
restricted nameserver is also known as split DNS" [[2]](#sources). Queries for `$SERVICE_DOMAIN` go
to our resolver, and everything else uses the client's normal DNS.

The `100.x.y.z` address is the one Tailscale assigns this host, drawn from the CGNAT range
`100.64.0.0/10` [[3]](#sources). "Tailscale IP addresses remain constant regardless of the device's
physical location" [[3]](#sources), so the value only changes if an administrator changes it.

## How the query reaches CoreDNS

Nothing about the router or the public DNS record changes. The split happens on the client device,
because Tailscale makes itself that device's DNS server.

`--accept-dns=true` is what puts the device under Tailscale DNS management, documented as the
setting "to use Tailscale DNS settings (default)" [[11]](#sources). Tailscale then provides the
resolver the device queries: `100.100.100.100`, known as Quad100. That address is not a remote
server. It is "a DNS resolver running on port 53", "a stub resolver, similar to `systemd-resolved`,
except with extra features". "Other devices cannot access your device using `100.100.100.100`", and
"local traffic connecting to 100.100.100.100 doesn't leave your device unless it's necessary to
provide a service" [[8]](#sources).

Tailscale's documentation does not spell out the exact mechanism by which each operating system is
pointed at Quad100, and it varies by platform. The behaviour that matters here is documented: with
Tailscale DNS management on, queries are resolved against the tailnet's DNS configuration rather
than the device's previous resolver.

Every lookup then passes through a resolver Tailscale controls, which checks the name against the
rules the tailnet pushed down:

```
app → OS resolver → 100.100.100.100        (device-local, inside tailscaled)
                          |
        +-----------------+------------------+
   matches $SERVICE_DOMAIN            everything else
        |                                    |
   forwarded over the tailnet          forwarded to the
   to 100.x.y.z:53, where              client's normal
   CoreDNS answers                     upstream DNS
```

The "Restrict to domain" setting from step 3 is exactly that branch. Three things follow from it:

Cloudflare is never asked about `$SERVICE_DOMAIN` while Tailscale is connected, because the suffix
matches and the query goes straight to CoreDNS. The public record still exists and is still correct,
it simply is not consulted on that path, which is why the two answers never conflict.

The router is bypassed as well. That is why this design needs no router configuration, no DNS server
on the LAN, and no wildcard support from consumer router firmware.

It is also why CoreDNS binds `tailscale0`. The forwarded query arrives at this host over the
tailnet, so it lands on that interface. Nothing on the LAN sends queries to the host's tailnet
address, which makes the resolver reachable to tailnet clients and invisible to the LAN at the same
time.

Some platforms express split DNS natively, so not every client routes everything through Quad100.
Windows uses the Name Resolution Policy Table, and Tailscale notes that the `Resolve-DnsName` cmdlet
"properly honors NRPT rules" when testing split DNS there [[2]](#sources). Quad100 is described as
the fallback where the operating system cannot express split DNS itself [[8]](#sources). The
resulting answer is the same either way.

With `--accept-dns` off, none of this happens. The resolver setting is never rewritten, the
restricted nameserver is never consulted, and the client silently falls back to the public record.

## Why there are no subnet routes and no IP forwarding

Because the resolver hands tailnet clients the host's tailnet address, they connect to it directly
over Tailscale. Nothing is routed into the LAN, so nothing is forwarded:

> "Unless your nameservers are public, or using Tailscale IP addresses, you probably need to
> configure subnet routing to allow your devices to reach the private DNS servers." [[2]](#sources)

Using a Tailscale address is the documented way to avoid subnet routing. It also avoids the failure
mode where an advertised route overrides the local route on a client already on that network, which
Tailscale documents as causing dropped packets and lost LAN connectivity [[7]](#sources).

## Why the certificate is unaffected

Traefik matches "requests targeted to a given host", and "if no host is set in the request URL,
these matchers look at the Host header instead" [[12]](#sources). Either way it is the name being
matched, not the address the packet arrived on, so the same router matches on both paths. The wildcard certificate is issued via the Cloudflare DNS-01 challenge
(`certificatesResolvers.cloudflare.acme.dnsChallenge` in
[traefik.yml](../../docker-volumes/traefik/data/traefik.yml)). DNS-01 proves control "by putting a
specific value in a TXT record under that domain name", which works "even if you have multiple web
servers" and can "validate domain names whose webservers aren't exposed to the public internet"
[[13]](#sources). It is also the challenge type that "allows you to issue wildcard certificates"
[[13]](#sources). Nothing about it depends on which address a client used to reach Traefik, so no
certificate has to be reissued.

## Setup

### 1. Generate the Corefile

[generate-dns-config.sh](./generate-dns-config.sh) reads this host's tailnet address, fills it and
the domain into the Corefile it carries inline, and prints the result to **stdout**. It writes
nothing, deploys nothing, and reads no other file in this repo, so it can be copied to a host on its
own and run there.

```bash
#!/usr/bin/env bash

./services/dns/generate-dns-config.sh                          # review it
./services/dns/generate-dns-config.sh --domain lab.example.com # skip the prompt
./services/dns/generate-dns-config.sh --yes > /tmp/Corefile    # capture it
```

It prompts for the domain, defaulting to `SERVICE_DOMAIN` from `common.env` when that exists and to
`local.example.com` otherwise. `--domain` skips the prompt and `--yes` accepts the default. The
prompt is also skipped when there is no terminal, so it stays usable in a pipe.

Progress messages and the prompt go to stderr, so stdout carries only the rendered file. That is what
makes `> file` and `| pbcopy` produce exactly the config and nothing else.

It is a zsh script, matching the other scripts in this repo. Copying the file rather than cloning it
loses the execute bit, and `sh generate-dns-config.sh` then runs under dash on Debian and Ubuntu,
which has no `pipefail`. The script re-runs itself under zsh to cover that, so `sh`, `bash` and `zsh`
all work, with or without the execute bit.

Note the tailnet address it reports. It is needed again in step 3.

Tailscale must already be installed and logged in. If it is not:

```bash
#!/usr/bin/env bash

curl -fsSL https://tailscale.com/install.sh | sh   # [[1]](#sources)
sudo tailscale up
```

### 2. Install the Corefile and start the resolver

Save the generated output to the path the compose file bind-mounts,
`$BASE_VOLUME_DIRECTORY/dns/data/Corefile`, then start the service:

```bash
#!/usr/bin/env bash

docker compose \
  --env-file "./docker-volumes/env-files/common.env" \
  --file "./services/dns/docker-compose.yaml" up --detach
```

If you would rather not run the script, [data/Corefile](./data/Corefile) is the same config as a
template with `🚨` placeholders to fill in by hand, matching the convention traefik's `config.yml`
uses. Either route produces the same file, and neither puts the real domain in git.

The script carries its own copy inline so it can run standalone, which means the two are kept in
sync by hand. Change one, change the other.

An absolute host path is required rather than a relative one. Relative bind paths resolve against the
compose file's directory on the command line, but a stack deployed through Portainer resolves them
inside Portainer's own container, where the repo does not exist.

The zone scopes the template, so a single block covers the domain and every service beneath it, with
nothing to change when you add a service [[6]](#sources).

The resolver binds only to `tailscale0`, since "bind by interface name, binds to the IPs on that
interface at the time of startup or reload" [[5]](#sources). That makes it unreachable from the LAN,
and it never contends with `systemd-resolved`, which "provides a local DNS stub listener on the IP
addresses 127.0.0.53 and 127.0.0.54 on the local loopback interface" [[14]](#sources). Unlike
Pi-hole, none of the stub-resolver disabling described in the main [README](../../README.md) is
required.

### 3. Register it as a restricted nameserver

In the [DNS page of the admin console](https://login.tailscale.com/admin/dns):

- **Nameservers → Add nameserver → Custom**, then enter the tailnet address from step 1
- Enable **Restrict to domain** and set it to your `SERVICE_DOMAIN` (e.g. `local.example.com`)

### 4. Ensure clients use Tailscale DNS

"Clients must be configured to use Tailscale DNS settings for the settings on this page to take
effect" [[2]](#sources). This is the switch that lets Tailscale rewrite the device's resolver
setting, so without it the restricted nameserver above is never consulted. See
[How the query reaches CoreDNS](#how-the-query-reaches-coredns).

```bash
#!/usr/bin/env bash

sudo tailscale set --accept-dns=true   # already the documented default
```

## Verification

```bash
#!/usr/bin/env bash

# On the docker host, the resolver should be listening on the tailnet address only.
# -u and -t are needed separately: CoreDNS serves DNS over both UDP and TCP.
sudo ss -lntup | grep ':53'
docker logs coredns

# From a tailnet client, this must return the TAILNET address, not the LAN address
dig +short traefik-dashboard.$SERVICE_DOMAIN

# End to end
curl -vI https://traefik-dashboard.$SERVICE_DOMAIN
```

If `dig` returns the LAN address instead, the restricted nameserver is not being applied. Check step
3, and check that the client is using Tailscale DNS (step 4).

If it returns nothing, the resolver is not reachable. Confirm the container is running and that
`tailscale0` existed when it started.

## Notes and caveats

### Single point of failure

If the resolver container is down, tailnet clients cannot resolve anything under `$SERVICE_DOMAIN`,
including the Traefik dashboard you would use to diagnose it. The LAN path is unaffected, since it
uses public DNS.

### Startup ordering

CoreDNS binds `tailscale0` at start, and `bind` resolves interface names "at the time of startup or
reload" [[5]](#sources), so the interface must exist first. With `restart: unless-stopped` it will
retry, but a host that starts Docker before Tailscale will log bind failures until it settles. A
change to the tailnet address also requires a restart rather than only a Corefile edit.

### Why CoreDNS rather than dnsmasq

dnsmasq expresses this in one line (`address=/domain/ip`), but the images available for it are
community builds rather than anything published by the dnsmasq project. That is a poor fit for a resolver that decides where every
service request goes, on a host where Watchtower updates `:latest` automatically. CoreDNS publishes
its own image, and the mounted Corefile is the complete configuration, with no image defaults to
merge with or discover at runtime.

### Out-of-zone queries are refused, by design

This is not a general resolver. Anything outside `$SERVICE_DOMAIN` returns REFUSED, which is correct
because Tailscale's restricted nameserver only routes matching queries here.

### The LAN path still relies on a public record pointing at a private address

Some resolvers block that as DNS rebinding [[4]](#sources). It works today, so your current LAN
resolver does not enforce that policy. If you ever change LAN DNS and the name stops resolving at
home while continuing to work over the VPN, this is the cause.

### IPv6

The resolver answers A records only. AAAA queries return an empty `NOERROR` (NODATA) so clients fall
straight through to IPv4 instead of waiting for a timeout.

## Sources

1. Tailscale, [Install Tailscale on Linux](https://tailscale.com/kb/1031/install-linux). Install
   command.
2. Tailscale, [DNS in Tailscale](https://tailscale.com/docs/reference/dns-in-tailscale). "A
   restricted nameserver only applies to DNS queries matching a specific search domain. Using a
   restricted nameserver is also known as split DNS"; "Unless your nameservers are public, or using
   Tailscale IP addresses, you probably need to configure subnet routing"; "Clients must be
   configured to use Tailscale DNS settings for the settings on this page to take effect".
3. Tailscale, [What are these 100.x.y.z
   addresses?](https://tailscale.com/docs/concepts/tailscale-ip-addresses). "IP addresses from the
   CGNAT range are special-use IPv4 addresses from the `100.64.0.0/10` subnet (`100.64.0.0` through
   `100.127.255.255`)", per [RFC 6598](https://datatracker.ietf.org/doc/html/rfc6598); "Tailscale IP
   addresses remain constant regardless of the device's physical location".
4. Tailscale, [DNS problems with internal services and DNS rebinding
   protection](https://tailscale.com/kb/1195/dns-rebinding). Recommends split DNS as the first
   remedy.
5. CoreDNS, [bind plugin](https://coredns.io/plugins/bind/). "Each address has to be an IP or name
   of one of the interfaces of the host. Bind by interface name, binds to the IPs on that interface
   at the time of startup or reload."
6. CoreDNS, [template plugin](https://coredns.io/plugins/template/). How a zone synthesises its own
   answers. Both `bind` and `template` ship in the default CoreDNS build
   ([plugin.cfg](https://github.com/coredns/coredns/blob/master/plugin.cfg)).
7. Tailscale, [Can't connect to local area
   network](https://tailscale.com/docs/reference/troubleshooting/connectivity/connect-lan-failure).
   Why advertising a subnet you are already on causes dropped packets, and background for why this
   design avoids subnet routes.
8. Tailscale, [What is 100.100.100.100?](https://tailscale.com/docs/reference/quad100). "A DNS
   resolver running on port 53"; "a stub resolver, similar to `systemd-resolved`, except with extra
   features"; "Other devices cannot access your device using `100.100.100.100`"; "local traffic
   connecting to 100.100.100.100 doesn't leave your device unless it's necessary to provide a
   service".
9. IETF, [RFC 1918](https://datatracker.ietf.org/doc/html/rfc1918). Address allocation for private
   internets, the reserved ranges including `192.168.0.0/16`.
10. Tailscale, [Connection types](https://tailscale.com/docs/reference/connection-types). Direct
    peer-to-peer connections are attempted first, with relays as fallback, so a direct link is
    typical but not guaranteed.
11. Tailscale, [Manage client
    preferences](https://tailscale.com/docs/features/client/manage-preferences). "To use Tailscale
    DNS settings (default): `tailscale set --accept-dns=true`". Note the Linux-specific default of
    `false` applies to `--accept-routes`, not to `--accept-dns`.
12. Traefik, [Rules and
    priority](https://github.com/traefik/traefik/blob/master/docs/content/reference/routing-configuration/http/routing/rules-and-priority.md).
    "The Host and HostRegexp matchers match requests targeted to a given host... If no host is set
    in the request URL, these matchers look at the Host header instead."
13. Let's Encrypt, [Challenge types](https://letsencrypt.org/docs/challenge-types/). DNS-01 proves
    control "by putting a specific value in a TXT record under that domain name"; it can "validate
    domain names whose webservers aren't exposed to the public internet" and "allows you to issue
    wildcard certificates".
14. systemd, [systemd-resolved.service(8)](https://www.freedesktop.org/software/systemd/man/latest/systemd-resolved.service.html).
    "systemd-resolved provides a local DNS stub listener on the IP addresses 127.0.0.53 and
    127.0.0.54 on the local loopback interface."
