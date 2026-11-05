#!/usr/bin/env bash
# Serves your own certificate on the CF gateway, in place of the generated one.
# Reads proxy/tls/tls.crt, tls.key and, for a private CA, ca.crt. Safe to run again.
# Runs under with-proxy.sh, after login.
set -euo pipefail

tls_dir=proxy/tls
secret=cf-gateway-tls
namespace=cf-system
workloads_namespace=cf-workloads

[[ -f "$tls_dir/tls.crt" && -f "$tls_dir/tls.key" ]] || {
  echo "Put tls.crt and tls.key into $tls_dir first." >&2
  exit 1
}

# Check everything first, so that a wrong file never reaches the gateway.
ca_args=()
[[ -f "$tls_dir/ca.crt" ]] && ca_args=(-CAfile "$tls_dir/ca.crt")
for host in "api.cf.$CLUSTER_DOMAIN" "uaa.cf.$CLUSTER_DOMAIN" "any.apps.$CLUSTER_DOMAIN"; do
  openssl verify "${ca_args[@]}" -verify_hostname "$host" "$tls_dir/tls.crt" >/dev/null || {
    echo "$tls_dir/tls.crt is not valid for $host." >&2
    exit 1
  }
done
cert_key="$(openssl x509 -in "$tls_dir/tls.crt" -noout -pubkey | openssl sha256)"
private_key="$(openssl pkey -in "$tls_dir/tls.key" -pubout | openssl sha256)"
[[ "$cert_key" == "$private_key" ]] || {
  echo "$tls_dir/tls.key does not belong to $tls_dir/tls.crt." >&2
  exit 1
}

# The repo's all-in-one-tls secret stays, because the CF components use it internally.
kubectl -n "$namespace" create secret tls "$secret" \
  --cert="$tls_dir/tls.crt" --key="$tls_dir/tls.key" --dry-run=client -o yaml | kubectl apply -f -

# Apps call the API through the gateway, so they must trust the CA behind the new
# certificate. Diego mounts this ConfigMap into every app container.
if [[ -f "$tls_dir/ca.crt" ]]; then
  kubectl -n "$workloads_namespace" patch configmap trusted-system-certs --type=merge \
    -p "$(jq -n --rawfile ca "$tls_dir/ca.crt" '{data: {"trusted-ca-2.crt": $ca}}')"
fi

listener="$(kubectl -n "$namespace" get gateway istio-gateway -o json \
  | jq '.spec.listeners | map(.name) | index("https")')"
kubectl -n "$namespace" patch gateway istio-gateway --type=json \
  -p "[{\"op\":\"replace\",\"path\":\"/spec/listeners/$listener/tls/certificateRefs/0/name\",\"value\":\"$secret\"}]"

# Stratos reads its trusted certificates only when it starts.
if cf app console >/dev/null 2>&1; then
  cf restart console
else
  echo "Stratos not found in the current space. Restart it after login if it runs elsewhere."
fi

echo "Certificate active on https://api.cf.$CLUSTER_DOMAIN"
