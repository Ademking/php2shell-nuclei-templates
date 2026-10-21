#!/usr/bin/env bash
set -u
cd /home/kali/nuclei-template || exit 1

TEMPLATE=templates/php2shell/php2shell-php-version.yaml
TARGET=http://127.0.0.1:18084

for v in 5.3.29 5.4.0 7.4.33 8.1.31 8.2.34 8.2.35 8.3.35 8.3.36 8.4.26 8.4.27 8.5.11 8.5.12 8.6.0 9.0.0; do
  curl -s "$TARGET/set?v=$v" >/dev/null
  out=$(nuclei -t "$TEMPLATE" -u "$TARGET" -nc -silent 2>/dev/null)
  if [ -n "$out" ]; then
    echo "$v MATCH"
  else
    echo "$v no-match"
  fi
done
