# Sourced by the other scripts. Sets CF_HOST_IP and CLUSTER_DOMAIN.
# Environment variables take precedence over proxy/config.env.
config_file="$(dirname "${BASH_SOURCE[0]}")/config.env"
env_host_ip="${CF_HOST_IP:-}"
env_domain="${CLUSTER_DOMAIN:-}"
if [[ -f "$config_file" ]]; then
  . "$config_file"
fi
CF_HOST_IP="${env_host_ip:-${CF_HOST_IP:-127.0.0.1}}"
CLUSTER_DOMAIN="${env_domain:-${CLUSTER_DOMAIN:-${CF_HOST_IP//./-}.nip.io}}"
export CF_HOST_IP CLUSTER_DOMAIN
