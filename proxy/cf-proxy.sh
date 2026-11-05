#!/usr/bin/env bash
# Gives staging and running app containers the proxy settings.
# Runs under with-proxy.sh, after login. Apps pushed earlier need a restage.
set -euo pipefail

if [[ -z "${HTTPS_PROXY:-}" ]]; then
  echo "No proxy configured, nothing to do."
  exit 0
fi

proxy_env="$(jq -nc --arg http "$HTTP_PROXY" --arg https "$HTTPS_PROXY" --arg no "$NO_PROXY,.apps.internal" \
  '{HTTP_PROXY: $http, http_proxy: $http, HTTPS_PROXY: $https, https_proxy: $https, NO_PROXY: $no, no_proxy: $no}')"

# The repo's Cilium policy blocks private networks for app containers, and proxies
# usually sit in one. Policies add up, so this opens only the proxy address and port.
proxy_authority="$(sed -E 's#^[a-z]+://##; s#^.*@##; s#/.*$##' <<<"$HTTPS_PROXY")"
proxy_host="${proxy_authority%:*}"
proxy_port="${proxy_authority##*:}"
[[ "$proxy_authority" == *:* ]] || proxy_port=80
proxy_cidrs="$(getent ahostsv4 "$proxy_host" | awk '!seen[$1]++ {print "        - " $1 "/32"}')"

kubectl apply -f - <<YAML
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: forward-proxy
spec:
  endpointSelector:
    matchExpressions:
      - key: cloudfoundry.org/app-guid
        operator: Exists
  egress:
    - toCIDR:
$proxy_cidrs
      toPorts:
        - ports:
            - port: "$proxy_port"
              protocol: TCP
YAML

cf set-staging-environment-variable-group "$proxy_env"
cf set-running-environment-variable-group "$proxy_env"
