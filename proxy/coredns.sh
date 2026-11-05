#!/usr/bin/env bash
# The helmfile only sends 127-0-0-1.nip.io to the gateway inside the cluster.
# This adds the same rule for any other domain, before the installation needs it.
set -euo pipefail

[[ "$CLUSTER_DOMAIN" != 127-0-0-1.nip.io ]] || exit 0

corefile="$(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}')"
pattern="${CLUSTER_DOMAIN//./\\.}"
if grep -qF "$pattern" <<<"$corefile"; then
  exit 0
fi

rule="    rewrite name regex (.*)\\.$pattern istio-gateway-istio.cf-system.svc.cluster.local answer auto"
updated="$(RULE="$rule" awk '/kubernetes/ && !done {print ENVIRON["RULE"]; done=1} {print}' <<<"$corefile")"
kubectl -n kube-system patch configmap coredns --type=json \
  -p="$(jq -n --arg cf "$updated" '[{"op":"replace","path":"/data/Corefile","value":$cf}]')"
