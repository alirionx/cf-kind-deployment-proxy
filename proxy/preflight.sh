#!/usr/bin/env bash
# Checks the host before a deployment. Runs under with-proxy.sh.
set -uo pipefail

errors=0
ok()   { echo "  ok    $*"; }
fail() { echo "  FAIL  $*"; errors=$((errors + 1)); }
warn() { echo "  warn  $*"; }

echo "Tools"
for tool in docker make curl jq tar; do
  command -v "$tool" >/dev/null && ok "$tool" || fail "$tool is missing"
done
docker compose version >/dev/null 2>&1 && ok "docker compose" || fail "docker compose is missing (package docker-compose-v2 on Ubuntu, docker-compose on Debian)"

echo "Docker daemon"
if daemon_proxy="$(docker info --format '{{.HTTPSProxy}}' 2>/dev/null)"; then
  ok "reachable"
  if [[ -n "${HTTPS_PROXY:-}" ]]; then
    [[ -n "$daemon_proxy" ]] && ok "proxy configured" || fail "the daemon has no proxy (systemd drop-in)"
  fi
else
  fail "not reachable for $(id -un) (docker group?)"
fi

if [[ -n "${HTTPS_PROXY:-}" ]]; then
  echo "Proxy"
  ok "using ${HTTPS_PROXY//\/\/*@/\/\/***@}"
  proxy_host="$(sed -E 's#^[a-z]+://##; s#^.*@##; s#[:/].*$##' <<<"$HTTPS_PROXY")"
  proxy_ip="$(getent ahostsv4 "$proxy_host" | awk 'NR==1 {print $1}')"
  if [[ -z "$proxy_ip" ]]; then
    fail "cannot resolve the proxy host $proxy_host"
  elif ip route get "$proxy_ip" 2>/dev/null | grep -qE 'dev (docker0|br-)'; then
    fail "proxy $proxy_ip is routed into a Docker network: address ranges overlap"
  fi
else
  echo "Proxy"
  ok "none configured, using direct access"
fi

echo "Internet access"
# Every host from the whitelist file: first column of its tables, then the port.
# The package sources are skipped: they are only needed to set up the server, and a
# proxy that denies plain HTTP answers with its own status code, which looks like success.
while read -r host port; do
  [[ "$port" == 80 ]] && url="http://$host/" || url="https://$host/"
  code="$(curl -sS -m 15 -o /dev/null -w '%{http_code}' "$url" 2>/tmp/preflight.$$)"
  if [[ "$code" != 000 ]]; then
    ok "$host ($code)"
  elif grep -qiE 'certificate|SSL' /tmp/preflight.$$; then
    fail "$host: TLS not trusted, the proxy may intercept TLS ($(tail -1 /tmp/preflight.$$))"
  else
    fail "$host: $(tail -1 /tmp/preflight.$$)"
  fi
done < <(awk -F'|' '/^## / {skip = /^## Operating system packages/}
  !skip && /^\| `/ {gsub(/[` ]/, "", $2); gsub(/ /, "", $3); print $2, $3}' proxy/WHITELIST.md)
rm -f /tmp/preflight.$$

echo "Host settings (fix with: make -f Makefile.proxy host-setup)"
# Read from /proc: sysctl is in /usr/sbin, which is not in the PATH of normal users on Debian.
instances="$(cat /proc/sys/fs/inotify/max_user_instances)"
watches="$(cat /proc/sys/fs/inotify/max_user_watches)"
[[ "$instances" -ge 512 && "$watches" -ge 524288 ]] && ok "inotify limits" \
  || fail "inotify limits too low ($instances/$watches, need 512/524288)"
[[ "$(systemctl show containerd -p LimitNOFILE --value 2>/dev/null)" != infinity ]] && ok "open files limit for containers" \
  || fail "containerd has LimitNOFILE=infinity, the nfs-server container would use up all memory"
if [[ "${INSTALL_OPTIONAL_COMPONENTS:-true}" == "true" ]]; then
  for module in nfs nfsd; do
    grep -qE "^$module " /proc/modules && ok "kernel module $module" || fail "kernel module $module is not loaded"
  done
fi
resolved="$(getent ahostsv4 "api.cf.$CLUSTER_DOMAIN" | awk 'NR==1 {print $1}')"
[[ "$resolved" == "$CF_HOST_IP" ]] && ok "$CLUSTER_DOMAIN resolves to $CF_HOST_IP" \
  || fail "api.cf.$CLUSTER_DOMAIN does not resolve to $CF_HOST_IP (got: ${resolved:-nothing})"

echo "Configuration"
if [[ "$CF_HOST_IP" == 127.0.0.1 ]] || ip -o -4 addr show | grep -qF " $CF_HOST_IP/"; then
  ok "host address $CF_HOST_IP"
else
  fail "CF_HOST_IP $CF_HOST_IP is not an address of this host, check proxy/config.env"
fi
if [[ -f temp/certs/all-in-one.conf ]] && ! grep -qF "$CLUSTER_DOMAIN" temp/certs/all-in-one.conf; then
  fail "temp/ belongs to another domain, run: make -f Makefile.proxy down"
fi

if [[ "$errors" -gt 0 ]]; then
  echo "Preflight failed with $errors problem(s)."
  exit 1
fi
echo "Preflight passed."
