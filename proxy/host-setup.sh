#!/usr/bin/env bash
# One-time host changes that need root. Safe to run again.
set -euo pipefail

proxy_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$proxy_dir/load-config.sh"

echo "Raising inotify limits..."
cat > /etc/sysctl.d/99-cf-kind.conf <<CONF
fs.inotify.max_user_instances=512
fs.inotify.max_user_watches=524288
CONF
sysctl -q --system

echo "Loading NFS kernel modules..."
printf 'nfs\nnfsd\n' > /etc/modules-load.d/cf-kind.conf
modprobe nfs
modprobe nfsd

if [[ "$(getent ahostsv4 "api.cf.$CLUSTER_DOMAIN" | awk 'NR==1 {print $1}')" == "$CF_HOST_IP" ]]; then
  echo "$CLUSTER_DOMAIN already resolves to $CF_HOST_IP, nothing to do."
  exit 0
fi

# The upstream DNS fails or filters answers pointing to private addresses, so the domain
# is answered locally and everything else keeps going to the existing DNS servers.
# This only covers the server itself: other machines need their own working DNS.
echo "Setting up local DNS for *.$CLUSTER_DOMAIN..."
mkdir -p /etc/dnsmasq.d /etc/systemd/resolved.conf.d
cat > /etc/dnsmasq.d/cf-kind.conf <<CONF
listen-address=127.0.0.2
bind-interfaces
no-resolv
no-hosts
address=/$CLUSTER_DOMAIN/$CF_HOST_IP
CONF
cat > /etc/systemd/resolved.conf.d/cf-kind.conf <<CONF
[Resolve]
DNS=127.0.0.2
Domains=~$CLUSTER_DOMAIN
CONF
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq dnsmasq-base dnsmasq
systemctl restart dnsmasq
systemctl restart systemd-resolved
