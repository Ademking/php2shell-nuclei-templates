#!/usr/bin/env bash
# php2shell nuclei template regression tests.
#
# Expected lab (all servers already running):
#   18080  vulnerable PHP, display_errors=On, cleanup=Off, strict_mode=Off
#   18082  same, session.upload_progress.enabled=Off
#   18083  same, display_errors=Off
#   18085  same, session.use_strict_mode=On
#   18086  same, session.upload_progress.cleanup=On
#   18081  nginx + php-cgi, /app = php_serialize, /api = php
#   18084  tiny non-PHP HTTP server with configurable X-Powered-By
#
# Override the defaults through environment variables if your lab differs.

set -u

cd "$(dirname "$0")/../.." || exit 1

NUCLEI="${NUCLEI:-nuclei}"
TEMPLATES="${TEMPLATES:-templates/php2shell}"
LAB_HOST="${LAB_HOST:-172.28.16.1}"
LAB_PORT="${LAB_PORT:-18080}"
OFF_PORT="${OFF_PORT:-18082}"
QUIET_PORT="${QUIET_PORT:-18083}"
STRICT_PORT="${STRICT_PORT:-18085}"
CLEANUP_PORT="${CLEANUP_PORT:-18086}"
CGI_HOST="${CGI_HOST:-127.0.0.1}"
CGI_PORT="${CGI_PORT:-18081}"
VERSION_SERVER="${VERSION_SERVER:-http://127.0.0.1:18084}"
SESSION_PATH="${SESSION_PATH:-C:/Users/ASUS/AppData/Local/Temp/opencode/php2shell-lab/sessions/sess_}"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '      unexpected output: %s\n' "$2"; }

expect() {
  local desc="$1" want="$2" out="$3"
  if [ "$want" = match ] && [ -n "$out" ]; then
    pass "$desc"
  elif [ "$want" = nomatch ] && [ -z "$out" ]; then
    pass "$desc"
  else
    fail "$desc" "$out"
  fi
}

run() {
  local tpl="$1"
  shift
  "$NUCLEI" -t "$TEMPLATES/$tpl" "$@" -silent -nc 2>/dev/null
}

set_version() {
  curl -s "$VERSION_SERVER/set?v=$1" >/dev/null
}

echo "== validate all templates =="
if "$NUCLEI" -validate -t "$TEMPLATES/" >/dev/null 2>&1; then
  pass "all templates validate"
else
  fail "all templates validate"
fi

echo "== CVE-2026-109618 active session-fixation check =="
out=$(run CVE-2026-109618.yaml -u "http://$LAB_HOST:$LAB_PORT")
expect "vulnerable PHP matches" match "$out"

out=$(run CVE-2026-109618.yaml -u "http://$LAB_HOST:$OFF_PORT")
expect "upload_progress=Off does not match" nomatch "$out"

out=$(run CVE-2026-109618.yaml -u "http://$LAB_HOST:$QUIET_PORT")
expect "display_errors=Off does not match" nomatch "$out"

out=$(run CVE-2026-109618.yaml -u "$VERSION_SERVER")
expect "non-PHP server does not match" nomatch "$out"

echo "== CVE-2026-109619 version range =="
for pair in \
  5.3.29:nomatch 5.4.0:match 7.4.33:match 8.1.31:match \
  8.2.34:match 8.2.35:nomatch 8.3.35:match 8.3.36:nomatch \
  8.4.26:match 8.4.27:nomatch 8.5.11:match 8.5.12:nomatch \
  8.6.0:nomatch 9.0.0:nomatch; do
  v=${pair%%:*}
  want=${pair##*:}
  set_version "$v"
  out=$(run CVE-2026-109619.yaml -u "$VERSION_SERVER")
  expect "PHP $v ($want)" "$want" "$out"
done

echo "== session injection -> LFI chain =="
LFI_ARGS=(-var upload_path=/nosession.php -var "session_path=$SESSION_PATH")

out=$(run php2shell-session-injection-lfi.yaml -u "http://$LAB_HOST:$LAB_PORT" "${LFI_ARGS[@]}")
expect "LFI chain matches vulnerable lab" match "$out"

out=$(run php2shell-session-injection-lfi.yaml -u "http://$LAB_HOST:$QUIET_PORT" "${LFI_ARGS[@]}")
expect "LFI chain works with display_errors=Off" match "$out"

out=$(run php2shell-session-injection-lfi.yaml -u "http://$LAB_HOST:$OFF_PORT" "${LFI_ARGS[@]}")
expect "LFI chain does not match upload_progress=Off" nomatch "$out"

out=$(run php2shell-session-injection-lfi.yaml -u "http://$LAB_HOST:$STRICT_PORT" "${LFI_ARGS[@]}")
expect "LFI chain does not match use_strict_mode=On" nomatch "$out"

out=$(run php2shell-session-injection-lfi.yaml -u "http://$LAB_HOST:$CLEANUP_PORT" "${LFI_ARGS[@]}")
expect "LFI chain does not match cleanup=On" nomatch "$out"

out=$(run php2shell-session-injection-lfi.yaml -u "http://$LAB_HOST:$LAB_PORT" \
  -var upload_path=/nosession.php -var lfi_path=/nope.php?page= -var "session_path=$SESSION_PATH")
expect "LFI chain does not match without LFI" nomatch "$out"

echo "== handler mismatch chain =="
out=$(run php2shell-handler-mismatch.yaml -u "http://$CGI_HOST:$CGI_PORT")
expect "php_serialize -> php mismatch matches" match "$out"

out=$(run php2shell-handler-mismatch.yaml -u "http://$CGI_HOST:$CGI_PORT" \
  -var write_path=/app/upload.php -var read_path=/app/upload.php)
expect "same php_serialize handler does not match" nomatch "$out"

out=$(run php2shell-handler-mismatch.yaml -u "http://$CGI_HOST:$CGI_PORT" \
  -var write_path=/api/endpoint.php -var read_path=/api/endpoint.php)
expect "same php handler does not match" nomatch "$out"

out=$(run php2shell-handler-mismatch.yaml -u "$VERSION_SERVER")
expect "non-PHP server does not match" nomatch "$out"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
