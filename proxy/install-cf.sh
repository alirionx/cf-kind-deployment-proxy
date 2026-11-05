#!/usr/bin/env bash
# Installs the cf CLI into bin/ (gitignored) unless one is already available.
set -euo pipefail

CF_CLI_VERSION="${CF_CLI_VERSION:-8.19.0}"

command -v cf >/dev/null && exit 0

echo "Installing cf CLI ${CF_CLI_VERSION} into bin/..."
mkdir -p bin
download_dir="$(mktemp -d)"
trap 'rm -rf "$download_dir"' EXIT
curl -fsSL "https://packages.cloudfoundry.org/stable?release=linux64-binary&version=${CF_CLI_VERSION}&source=github" \
  | tar -xz -C "$download_dir"
mv "$download_dir/cf8" bin/cf
