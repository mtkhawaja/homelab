#!/usr/bin/env zsh
#
# Lints every shell script in the repo, dispatching on the shebang.
#
# Most scripts here target zsh, which shellcheck refuses outright with SC1071
# ("ShellCheck only supports sh/bash/dash/ksh"). Pointing it at them anyway just
# produces a wall of errors about the shebang, so zsh scripts get `zsh -n`
# instead. That is a parse check rather than static analysis: it catches syntax
# errors, not unquoted expansions. It is what zsh offers.
#
# Genuine bash scripts get the real thing.
#
# Usage:
#   ./scripts/lint-shell.sh
#
# Exits non-zero if any script fails its check.

set -eu

cd "${0:A:h}/.."

rc=0

report() {
  local file=$1 message=$2
  rc=1
  if [[ -n ${GITHUB_ACTIONS:-} ]]; then
    print -r -- "::error file=${file}::${message}"
  else
    print -r -- "FAIL  ${file}: ${message}"
  fi
}

zsh_count=0
bash_count=0
skipped=0

# -print0 and read -d '' so a path containing whitespace cannot split.
find . -name '*.sh' -not -path './.git/*' -print0 \
  | sort -z \
  | while IFS= read -r -d '' file; do
      shebang=$(head -1 "$file")
      case $shebang in
        (*zsh)
          zsh_count=$(( zsh_count + 1 ))
          if ! out=$(zsh -n "$file" 2>&1); then
            report "$file" "${out##*$'\n'}"
          fi
          ;;
        (*bash|*/sh|*\ sh)
          bash_count=$(( bash_count + 1 ))
          if ! out=$(shellcheck "$file" 2>&1); then
            report "$file" "shellcheck reported problems"
            print -r -- "$out"
          fi
          ;;
        (*)
          skipped=$(( skipped + 1 ))
          print -r -- "SKIP  ${file}: unrecognised shebang (${shebang})"
          ;;
      esac
    done

print -r -- "Checked ${zsh_count} zsh with a parse check, ${bash_count} bash with shellcheck, skipped ${skipped}"

if (( rc == 0 )); then
  print -r -- "OK    shell scripts linted"
fi

exit $rc
