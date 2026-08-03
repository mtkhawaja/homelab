#!/usr/bin/env zsh
#
# Validates every service's compose file. This is the repo's only automated
# check; there is no test suite.
#
# `docker compose config` is the native validator: it parses each file against
# the Compose schema and reports structure and syntax errors. Two things around
# it need arranging.
#
# First, it cannot run until the guarded variables have values, so the
# placeholder env below is derived from the ${VAR:?...} patterns in the compose
# files themselves rather than from a checked-in fixture. A new guarded variable
# therefore cannot silently opt a service out of validation.
#
# Second, config passes a bare ${VAR} by interpolating it to an empty string and
# reporting success. That is how Host(`<service>.local.`) shipped across this
# repo unnoticed, and how a bind mount can resolve to /garage/data instead of
# something under $BASE_VOLUME_DIRECTORY -- still an absolute path, so Docker
# just creates it. The guards are what give the first check meaning, so they are
# enforced too.
#
# Usage:
#   ./scripts/validate-compose.sh
#
# Exits non-zero if anything fails. Prints GitHub Actions annotations when
# GITHUB_ACTIONS is set and plain text otherwise.
#
# zsh, matching the other scripts here. Note `status` is a read-only variable in
# zsh, hence `rc`, and command substitutions do not word-split.

set -eu

cd "${0:A:h}/.."

rc=0

report() {
  local file=$1 message=$2
  rc=1
  if [[ -n ${GITHUB_ACTIONS:-} ]]; then
    print -r -- "::error file=${file}::${message}"
  else
    print -r -- "FAIL  ${file}"
    print -r -- "      ${message}"
  fi
}

# Values are throwaway. config only has to interpolate them; nothing connects.
env_file=$(mktemp)
trap 'rm -f "$env_file"' EXIT INT TERM

grep -ohE '\$\{[A-Z0-9_]+:\?' services/*/compose.yaml \
  | sed -E 's/^\$\{//; s/:\?$//' \
  | sort -u \
  | while read -r var; do
      case $var in
        # Bind mount sources have to be absolute paths.
        (*DIRECTORY) print -r -- "${var}=/srv/ci" ;;
        (*)          print -r -- "${var}=ci-placeholder" ;;
      esac
    done > "$env_file"

print -r -- "Derived $(wc -l < "$env_file" | tr -d ' ') placeholder variables"

# Every variable referenced in the file that is neither guarded with :? nor
# given a :- default. Comment lines are skipped: several headers quote the old
# broken syntax on purpose. `$$VAR` is excluded because that is a shell variable
# for the container, not Compose interpolation.
unguarded_vars() {
  local file=$1
  grep -vE '^[[:space:]]*#' "$file" \
    | grep -oE '(^|[^$])\$\{?[A-Z][A-Z0-9_]*\}?([^:a-zA-Z_}]|$)' \
    | grep -oE '[A-Z][A-Z0-9_]*' \
    | sort -u \
    | while read -r name; do
        grep -qE "\\\$\{${name}:[?-]" "$file" || print -r -- "$name"
      done \
    | sort -u | paste -sd' ' -
}

count=0
for f in services/*/compose.yaml; do
  count=$(( count + 1 ))

  if ! out=$(docker compose --env-file "$env_file" --file "$f" config 2>&1); then
    report "$f" "${out##*$'\n'}"
    continue
  fi

  bare=$(unguarded_vars "$f" || true)
  if [[ -n $bare ]]; then
    report "$f" "unguarded variables, use \${VAR:?...} or \${VAR:-default}: ${bare}"
  fi
done

if (( rc == 0 )); then
  print -r -- "OK    ${count} compose files validated"
fi

exit $rc
