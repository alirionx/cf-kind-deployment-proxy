#!/usr/bin/env bash
# Prints /etc/hosts lines for clients without a wildcard DNS entry: the CF system
# names and all current app routes. Runs under with-proxy.sh, after login.
set -euo pipefail

{
  cf curl / | jq -r '.. | .href? // empty'
  cf curl '/v3/routes?per_page=5000' | jq -r '.resources[].url'
} | sed -E 's#^[a-z]+://##; s#[:/].*$##' \
  | grep -F ".$CLUSTER_DOMAIN" \
  | sort -u \
  | awk -v ip="$CF_HOST_IP" '{print ip, $0}'
