#!/usr/bin/env zsh
#
# Documentation Reference:
# https://tailscale.com/kb/1031/install-linux
# https://coredns.io/plugins/bind/
# https://coredns.io/plugins/template/
#
# Prints a CoreDNS Corefile for tailnet split DNS to stdout, with this host's
# tailnet address and the chosen domain filled in. Writes nothing, deploys
# nothing, and reads no other file in this repo.
#
# Progress and prompts go to stderr, so stdout carries only the config:
#
#   ./services/dns/generate-dns-config.sh                # review it
#   ./services/dns/generate-dns-config.sh --yes | pbcopy # paste into Portainer
#   ./services/dns/generate-dns-config.sh --yes > /tmp/Corefile
#
# Install the output where the compose file bind-mounts it from, which is
# $BASE_VOLUME_DIRECTORY/dns/data/Corefile. An absolute host path is required
# because a stack deployed through Portainer resolves relative paths inside
# Portainer's own container rather than on the host.
#
# The domain must match the SERVICE_DOMAIN used by the Traefik labels. If they
# differ, this resolver answers for a zone that nothing routes to.
#
# Run this on the docker host: the tailnet address is read from the machine it
# runs on, and it has to be the one the resolver will answer with.
#
# data/Corefile holds the same config as a placeholder template, for filling in
# by hand instead. The copy below is inline so this script stays standalone, so
# the two are kept in sync by hand: change one, change the other.
#
# Requires zsh, matching the other scripts in this repo. A copied file loses its
# execute bit, and `sh script.sh` then runs under dash on Debian and Ubuntu,
# which has no `pipefail`. The guard below re-runs the script under zsh so that
# case works instead of dying on the first zsh-only construct.
#
# Usage:
#   ./services/dns/generate-dns-config.sh                          # prompts for the domain
#   ./services/dns/generate-dns-config.sh --domain lab.example.com # skip the prompt
#   ./services/dns/generate-dns-config.sh --yes                    # no prompts
#   zsh services/dns/generate-dns-config.sh --yes                  # no execute bit needed

# Kept POSIX-compatible: this runs before we know which shell we are in.
if [ -z "${ZSH_VERSION-}" ]; then
  if command -v zsh >/dev/null 2>&1 && [ -r "$0" ]; then
    exec zsh "$0" "$@"
  fi
  echo "ERROR: this script requires zsh. Install it, or run: zsh $0" >&2
  exit 1
fi

set -euo pipefail

DEFAULT_DOMAIN="local.example.com"

ASSUME_YES=0
DOMAIN_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y | --yes)
      ASSUME_YES=1
      shift
      ;;
    -d | --domain)
      [[ -n "${2:-}" ]] || {
        printf 'ERROR: --domain requires a value\n' >&2
        exit 1
      }
      DOMAIN_ARG="$2"
      shift 2
      ;;
    -h | --help)
      # Print the header comment block, stopping at the first non-comment line,
      # so this cannot drift out of sync with the file as it is edited.
      awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); print } else { exit } }' "$0"
      exit 0
      ;;
    *)
      printf 'ERROR: unknown argument: %s (try --help)\n' "$1" >&2
      exit 1
      ;;
  esac
done

# Everything except the config goes to stderr, so stdout stays clean enough to
# redirect or pipe straight into a clipboard.
step() { printf '\n\033[1m==> %s\033[0m\n' "$1" >&2; }
info() { printf '    %s\n' "$1" >&2; }
warn() { printf '    WARNING: %s\n' "$1" >&2; }
die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# 1. Resolve the domain
# ---------------------------------------------------------------------------
step "Resolving the domain"

if [[ "$(uname -s)" != "Linux" ]]; then
  warn "Not running on Linux. The tailnet address below is this machine's,"
  warn "not the docker host's. Check the output before using it."
fi

if [[ -n "${DOMAIN_ARG}" ]]; then
  service_domain="${DOMAIN_ARG}"
  info "Using ${service_domain} (from --domain)"
elif [[ ${ASSUME_YES} -eq 1 || ! -t 0 ]]; then
  service_domain="${DEFAULT_DOMAIN}"
  info "Using ${service_domain} (default, not prompting)"
else
  # `read` returns non-zero on EOF, which Ctrl-D produces even on a tty. Without
  # this guard `set -e` would kill the script at the prompt with no message.
  reply=""
  if ! read -r "reply?    Domain to publish services under [${DEFAULT_DOMAIN}]: "; then
    printf '\n' >&2
    info "No input read, falling back to the default"
  fi
  service_domain="${reply:-${DEFAULT_DOMAIN}}"
  info "Using ${service_domain}"
fi

info "This must match SERVICE_DOMAIN in the Traefik labels, or the resolver"
info "answers for a zone that nothing routes to."

# ---------------------------------------------------------------------------
# 2. Read the tailnet address
# ---------------------------------------------------------------------------
step "Reading the tailnet address"

command -v tailscale >/dev/null 2>&1 ||
  die "'tailscale' not found. Install it: curl -fsSL https://tailscale.com/install.sh | sh"

tailscale status >/dev/null 2>&1 ||
  die "Tailscale is not logged in. Run 'sudo tailscale up' first."

tailnet_ip="$(tailscale ip -4 2>/dev/null | head -1)"
[[ -n "${tailnet_ip}" ]] || die "Could not read the tailnet address from 'tailscale ip -4'."
info "${tailnet_ip}"

# ---------------------------------------------------------------------------
# 3. Emit the Corefile
#
# The heredoc is unquoted so ${service_domain} and ${tailnet_ip} expand. CoreDNS
# templates use {{ }} rather than $, so they pass through untouched.
# ---------------------------------------------------------------------------
step "Corefile (stdout)"

cat <<EOF
# Generated by services/dns/generate-dns-config.sh on $(date -u '+%Y-%m-%d')
# Do not edit here. Edit the script and re-run.
#
# Tailnet-only DNS resolver providing split DNS for Tailscale clients.
# See services/dns/TAILSCALE.md for the design and setup steps.
#
# This file is the complete configuration. CoreDNS applies no defaults beyond
# what appears here.

${service_domain} {
    # Listen only on the Tailscale interface, so this resolver is unreachable
    # from the LAN and never contends with systemd-resolved, which listens on
    # 127.0.0.53 and 127.0.0.54.
    # "Bind by interface name, binds to the IPs on that interface at the time of
    # startup or reload."
    bind tailscale0

    # Every name in this zone answers with the host's tailnet address. The zone
    # already scopes the template, so no match expression is needed. This covers
    # the domain and every service beneath it:
    #   plex.${service_domain}, traefik-dashboard.${service_domain}, ...
    # Nothing here changes when a service is added.
    template IN A {
        answer "{{ .Name }} 60 IN A ${tailnet_ip}"
    }

    # Answer AAAA with an empty NOERROR (NODATA). Without this, IPv6-capable
    # clients get no reply for AAAA and wait for a timeout before trying A.
    template IN AAAA {
        rcode NOERROR
    }

    log
    errors
}
EOF

# ---------------------------------------------------------------------------
# 4. What to do with it
# ---------------------------------------------------------------------------
cat >&2 <<EOF

$(printf '\033[1m==> Next steps\033[0m')

    1. Save the output above to the path the compose file bind-mounts:
         \$BASE_VOLUME_DIRECTORY/dns/data/Corefile

       Then start the resolver:
         docker compose \\
           --env-file "./services/common.env" \\
           --file "./services/dns/compose.yaml" up --detach

    2. Register the resolver as a restricted nameserver (split DNS):
       https://login.tailscale.com/admin/dns

         Nameservers -> Add nameserver -> Custom -> ${tailnet_ip}
         Enable "Restrict to domain" and set it to ${service_domain}

    3. Clients must be using Tailscale DNS for that setting to apply.
       Linux:  sudo tailscale set --accept-dns=true

    Verify from a tailnet client:
       dig +short traefik-dashboard.${service_domain}   # expect ${tailnet_ip}
       curl -vI https://traefik-dashboard.${service_domain}
EOF
