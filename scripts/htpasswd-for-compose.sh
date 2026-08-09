#!/usr/bin/env zsh
#
# Generates a bcrypt htpasswd entry for a Traefik basicauth middleware, and
# prints it in both forms, because which one is correct depends on how the value
# reaches Compose.
#
# Compose interpolates inside env-file values. A bcrypt hash is full of dollar
# signs, so a single-dollar value has the rest of itself eaten as a variable
# name, substituted with nothing, and passed on without a warning. The result
# does not look truncated -- the label lands as something like `user:$2y$05` --
# and Traefik then computes against that corrupted value and rejects every
# login while the browser still shows a perfectly normal password prompt.
# Hunting the password rather than the config is the natural response, which is
# what makes this expensive.
#
#   shell environment variable   $ preserved       use the raw form
#   --env-file                   $ interpolated    use the doubled form
#   Portainer stack variable     $ interpolated    use the doubled form
#   pasted into the compose file $ interpolated    use the doubled form
#
# This repo deploys with --env-file and Portainer, so the doubled form is
# almost always the one wanted.
#
# Usage:
#   ./scripts/htpasswd-for-compose.sh [user]
#   ./scripts/htpasswd-for-compose.sh --check 'user:$2y$05$...'
#   ./scripts/htpasswd-for-compose.sh --inspect <container> <label>
#
# The password is read from a prompt rather than taken as an argument, so it
# does not land in shell history or in the process list.
#
# Requires docker; the hash comes from the httpd image rather than assuming a
# local htpasswd, which macOS does not ship.

set -euo pipefail

BCRYPT_LEN=60

die() {
  print -r -- "error: $*" >&2
  exit 1
}

usage() {
  sed -n '3,32p' "${0:A}" | sed 's/^# \{0,1\}//'
  exit 0
}

# Reports whether a user:hash pair looks well formed, and which form it is in.
check() {
  local value=$1
  local hash=${value#*:}
  local user=${value%%:*}

  [[ $value == *:* ]] || die "no colon in the value; expected user:hash"

  print -r -- "user:   ${user}"
  print -r -- "length: ${#hash} (a bcrypt hash is ${BCRYPT_LEN})"

  if [[ $hash == *'$$'* ]]; then
    print -r -- "form:   DOUBLED -- correct for an env file or Portainer, wrong for a shell variable"
    local collapsed=${hash//\$\$/\$}
    if (( ${#collapsed} == BCRYPT_LEN )); then
      print -r -- "verdict: OK, collapses to a valid ${BCRYPT_LEN}-character hash"
      return 0
    fi
    print -r -- "verdict: BROKEN, collapses to ${#collapsed} characters rather than ${BCRYPT_LEN}"
    return 1
  fi

  if (( ${#hash} == BCRYPT_LEN )); then
    print -r -- "form:   RAW -- correct for a shell variable, will be eaten by an env file"
    print -r -- "verdict: OK"
    return 0
  fi

  print -r -- "form:   RAW"
  print -r -- "verdict: BROKEN, ${#hash} characters rather than ${BCRYPT_LEN}."
  print -r -- "         This is what a swallowed \$ looks like: the dollars were"
  print -r -- "         interpolated away. Reset the variable using the doubled form."
  return 1
}

# Pulls a label off a running container and checks it, which is the only
# reliable verification. `docker compose config` re-escapes $ for display, so a
# correct value and a doubled one are indistinguishable there.
inspect() {
  local container=$1 label=$2
  command -v docker >/dev/null 2>&1 || die "docker not found"
  local value
  value=$(docker inspect "$container" --format "{{index .Config.Labels \"${label}\"}}" 2>/dev/null) \
    || die "could not read ${label} from container ${container}"
  [[ -n $value ]] || die "label ${label} is empty or absent on ${container}"
  print -r -- "container: ${container}"
  print -r -- "label:     ${label}"
  print -r -- ""
  # The value on a container has already been through interpolation, so a
  # correct one is raw here no matter which form was set.
  check "$value"
}

generate() {
  local user=${1:-}

  command -v docker >/dev/null 2>&1 || die "docker not found"

  if [[ -z $user ]]; then
    user=""
    if ! read -r "user?User: "; then
      printf '\n' >&2
      die "no user given"
    fi
    [[ -n $user ]] || die "no user given"
  fi

  local password="" confirm=""
  if ! read -rs "password?Password: "; then
    printf '\n' >&2
    die "no password given"
  fi
  printf '\n' >&2
  [[ -n $password ]] || die "no password given"

  if ! read -rs "confirm?Confirm:  "; then
    printf '\n' >&2
    die "no confirmation given"
  fi
  printf '\n' >&2
  [[ $password == "$confirm" ]] || die "passwords do not match"

  local entry
  entry=$(docker run --rm httpd:alpine htpasswd -nbB "$user" "$password" 2>/dev/null | tr -d '\r\n') \
    || die "htpasswd failed"
  [[ -n $entry ]] || die "htpasswd produced nothing"

  local hash=${entry#*:}
  (( ${#hash} == BCRYPT_LEN )) \
    || die "expected a ${BCRYPT_LEN}-character hash, got ${#hash}; refusing to print a broken value"

  local doubled=${entry//\$/\$\$}

  print -r -- ""
  print -r -- "For an env file or a Portainer stack variable  (this repo's usual path):"
  print -r -- ""
  print -r -- "    ${doubled}"
  print -r -- ""
  print -r -- "For a shell environment variable, or a Traefik usersfile:"
  print -r -- ""
  print -r -- "    ${entry}"
  print -r -- ""
  print -r -- "Verify what actually landed once the container is recreated:"
  print -r -- ""
  print -r -- "    ./scripts/htpasswd-for-compose.sh --inspect <container> \\"
  print -r -- "        traefik.http.middlewares.<name>.basicauth.users"
  print -r -- ""
  print -r -- "Keep the password behind this hash in sync with whatever the service"
  print -r -- "itself expects. If they diverge, Traefik accepts and the app rejects."
}

main() {
  case ${1:-} in
    (-h|--help)
      usage
      ;;
    (--check)
      [[ $# -eq 2 ]] || die "usage: $0 --check 'user:hash'"
      check "$2"
      ;;
    (--inspect)
      [[ $# -eq 3 ]] || die "usage: $0 --inspect <container> <label>"
      inspect "$2" "$3"
      ;;
    (-*)
      die "unknown flag: $1"
      ;;
    (*)
      generate "${1:-}"
      ;;
  esac
}

main "$@"
