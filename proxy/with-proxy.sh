#!/usr/bin/env bash
# Runs a command with the proxy settings every part of the deployment needs.
# Without a configured proxy it only adds bin/ to the PATH.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Read one variable from /etc/environment (not sourced: it may hold anything).
from_etc() {
  sed -nE "s/^[[:space:]]*(export[[:space:]]+)?$1=[\"']?([^\"']*)[\"']?[[:space:]]*$/\2/p" /etc/environment 2>/dev/null | tail -1
}

http_proxy_url="${HTTP_PROXY:-${http_proxy:-$(from_etc HTTP_PROXY)}}"
http_proxy_url="${http_proxy_url:-$(from_etc http_proxy)}"
https_proxy_url="${HTTPS_PROXY:-${https_proxy:-$(from_etc HTTPS_PROXY)}}"
https_proxy_url="${https_proxy_url:-$(from_etc https_proxy)}"
https_proxy_url="${https_proxy_url:-$http_proxy_url}"
http_proxy_url="${http_proxy_url:-$https_proxy_url}"
base_no_proxy="${NO_PROXY:-${no_proxy:-$(from_etc NO_PROXY)}}"
base_no_proxy="${base_no_proxy:-$(from_etc no_proxy)}"

export PATH="$repo_root/bin:$PATH"
cd "$repo_root"
. proxy/load-config.sh

# Without a proxy there is nothing to set up: run the command as it is.
if [[ -z "$https_proxy_url" ]]; then
  exec "$@"
fi

# Everything that must never go through the proxy:
#  - loopback, the host address and the CF domains, which point back to this machine
#  - the containers on the kind network, addressed by name or IP
#  - cluster-internal names and the kind pod and service networks
internal="localhost,127.0.0.1,::1,.nip.io,.$CLUSTER_DOMAIN,$CF_HOST_IP"
internal+=",docker-io,ghcr-io,quay-io,nfs-server,cloud-provider"
internal+=",cfk8s-control-plane,cfk8s-worker,cfk8s-worker2"
internal+=",.svc,.svc.cluster.local,.cluster.local,10.96.0.0/16,10.244.0.0/16"
# The kind network exists only after the first run; until then cover Docker's default range.
kind_subnets="$(docker network inspect kind --format '{{range .IPAM.Config}}{{.Subnet}},{{end}}' 2>/dev/null || true)"
internal+=",${kind_subnets:-172.16.0.0/12}"
no_proxy_list="$(printf '%s' "${base_no_proxy:+$base_no_proxy,}$internal" | tr ',' '\n' | awk 'NF && !seen[$0]++' | paste -sd, -)"

export HTTP_PROXY="$http_proxy_url" http_proxy="$http_proxy_url"
export HTTPS_PROXY="$https_proxy_url" https_proxy="$https_proxy_url"
export NO_PROXY="$no_proxy_list" no_proxy="$no_proxy_list"

# docker compose hands these on to the containers it creates, which is how the
# registry caches and the cloud provider get them without changing the compose files.
docker_config="${XDG_CACHE_HOME:-$HOME/.cache}/cf-kind-proxy/docker"
mkdir -p "$docker_config"
source_config="${DOCKER_CONFIG:-$HOME/.docker}/config.json"
[[ -s "$source_config" && "$source_config" != "$docker_config/config.json" ]] || source_config=/dev/null
jq -n --slurpfile base <(cat "$source_config" 2>/dev/null) \
  --arg http "$HTTP_PROXY" --arg https "$HTTPS_PROXY" --arg no "$NO_PROXY" \
  '($base[0] // {}) + {proxies: {default: {httpProxy: $http, httpsProxy: $https, noProxy: $no}}}' \
  > "$docker_config/config.json"
chmod 600 "$docker_config/config.json"
export DOCKER_CONFIG="$docker_config"

exec "$@"
