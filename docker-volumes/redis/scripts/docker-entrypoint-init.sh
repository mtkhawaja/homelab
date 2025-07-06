#!/usr/bin/env bash
set -e

echo "[entrypoint] Starting Redis ACL bootstrap..."

# Pull credentials from env vars
USERNAME="${REDIS_SUPERUSER_USERNAME}"
PASSWORD="${REDIS_SUPERUSER_PASSWORD}"
ACL_FILE="/usr/local/etc/redis/users.acl"

# Ensure the ACL file exists and is populated
if [[ -z "$USERNAME" || -z "$PASSWORD" ]]; then
  echo "[entrypoint] REDIS_SUPERUSER_USERNAME or REDIS_SUPERUSER_PASSWORD not set. Skipping ACL setup."
else
  if grep -q "user ${USERNAME} " "$ACL_FILE" 2>/dev/null; then
    echo "[entrypoint] ACL user '$USERNAME' already exists in $ACL_FILE."
  else
    echo "[entrypoint] Creating ACL user '$USERNAME' in $ACL_FILE..."
    {
      echo "user ${USERNAME} on >${PASSWORD} allkeys allcommands"
    } >> "$ACL_FILE"
    echo "[entrypoint] Done writing to ACL file."
  fi
fi

# Finally, start Redis using the passed command
exec "$@"
