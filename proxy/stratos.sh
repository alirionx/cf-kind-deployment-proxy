#!/usr/bin/env bash
# Deploys the Stratos web console as a CF app into the targeted space.
# Runs under with-proxy.sh, after login and bootstrap.
set -euo pipefail

STRATOS_VERSION="${STRATOS_VERSION:-5.5.5}"

asset="stratos-cf-v${STRATOS_VERSION}.zip"
base_url="https://github.com/cloudfoundry/stratos/releases/download/v${STRATOS_VERSION}"
download_dir=temp/stratos

mkdir -p "$download_dir"
if [[ ! -f "$download_dir/$asset" ]]; then
  echo "Downloading Stratos ${STRATOS_VERSION}..."
  curl -fsSL -o "$download_dir/$asset.part" "$base_url/$asset"
  mv "$download_dir/$asset.part" "$download_dir/$asset"
fi
curl -fsSL "$base_url/SHA256SUMS" | grep " $asset\$" | (cd "$download_dir" && sha256sum -c --quiet -)

cf push console -p "$download_dir/$asset" -b binary_buildpack -c ./jetstream \
  -m 512M -k 1024M -t 180 -u port --no-start

# The package ships a public default key. Its SQLite database is not persistent,
# so new secrets on every deployment only mean that users log in again.
cf set-env console ENCRYPTION_KEY "$(openssl rand -hex 32)"
cf set-env console SESSION_STORE_SECRET "$(openssl rand -hex 32)"
cf set-env console SESSION_STORE_EXPIRY 240

# Stratos ignores skip-ssl on the routes behind most of its pages, so it must trust the
# CF certificate. Diego already mounts the CA there, Go just does not look in that folder.
cf set-env console SSL_CERT_DIR /etc/cf-system-certificates:/etc/ssl/certs
cf restart console

echo "Stratos: https://console.apps.$CLUSTER_DOMAIN (log in as ccadmin)"
