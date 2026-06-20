#!/usr/bin/env bash
# Build an Ansible inventory from ips.txt without emitting appKey/appSecret fields.
set -euo pipefail

INPUT="${1:-ips.txt}"
GROUP="${ANSIBLE_GROUP:-openclaw_macs}"
USER_VALUE="${ANSIBLE_USER:-}"

if [ ! -f "$INPUT" ]; then
  echo "Missing input file: $INPUT" >&2
  exit 1
fi

printf '[%s]\n' "$GROUP"
awk '
  {
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/ && !seen[$i]++) {
        print $i
      }
    }
  }
' "$INPUT" | while IFS= read -r ip; do
  if [ -n "$USER_VALUE" ]; then
    printf '%s ansible_user=%s\n' "$ip" "$USER_VALUE"
  else
    printf '%s\n' "$ip"
  fi
done
