#!/usr/bin/env bash
# End-to-end check, runs under with-proxy.sh after login and bootstrap.
set -euo pipefail

domain="apps.$CLUSTER_DOMAIN"

check_app() {
  local name=$1 expected=$2 body
  body="$(curl -fsSk --retry 5 --retry-delay 3 --retry-all-errors "https://$name.$domain/")"
  if ! grep -q "$expected" <<<"$body"; then
    echo "FAIL: $name answered: $body" >&2
    exit 1
  fi
  echo "ok: $name"
}

echo "Pushing hello-js (no dependencies)..."
cf push -f examples/hello-js/manifest.yaml
check_app hello-js .

echo "Pushing proxy-test (fetches npm packages while staging)..."
cf push proxy-test -p proxy/test-app -m 256M
check_app proxy-test 'proxy-test 172800000'

echo "Checking outbound access from a running app..."
cf ssh proxy-test -c 'curl -sS -m 20 -o /dev/null -w "%{http_code}\n" https://registry.npmjs.org/ms' | grep -q '^200$'
echo "ok: running app reaches the internet through the proxy"

cf delete -f -r hello-js
cf delete -f -r proxy-test

if cf app console >/dev/null 2>&1; then
  echo "Checking Stratos..."
  . temp/secrets.sh
  console="https://console.$domain"
  cookies="$(mktemp)"
  trap 'rm -f "$cookies"' EXIT
  curl -fsSk -o /dev/null -c "$cookies" --data-urlencode username=ccadmin \
    --data-urlencode "password=$CC_ADMIN_PASSWORD" "$console/pp/v1/auth/login/uaa"
  endpoint="$(curl -fsSk -b "$cookies" "$console/pp/v1/info" | jq -r '.endpoints.cf | keys[0]')"
  # The pages use these routes, which check the CF certificate.
  curl -fsSk -o /dev/null -b "$cookies" "$console/pp/v1/cf/apps/$endpoint"
  echo "ok: Stratos reads from CF"
fi

echo "Verify passed."
