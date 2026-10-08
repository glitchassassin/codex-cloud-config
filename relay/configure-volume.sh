#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <TrueNAS tailnet IPv4 address>" >&2
  exit 2
fi
relay_ip=$1
# Validate before substituting into the configuration or touching Docker.
IFS=. read -r octet1 octet2 octet3 octet4 extra <<< "$relay_ip"
if [[ -n ${extra:-} || ! $relay_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Expected a tailnet IPv4 address in 100.64.0.0/10" >&2
  exit 2
fi
for octet in "$octet1" "$octet2" "$octet3" "$octet4"; do
  if [[ ${#octet} -gt 3 ]] || (( 10#$octet > 255 )); then
    echo "Invalid IPv4 address" >&2
    exit 2
  fi
done
if (( 10#$octet1 != 100 || 10#$octet2 < 64 || 10#$octet2 > 127 )); then
  echo "Expected a tailnet IPv4 address in 100.64.0.0/10" >&2
  exit 2
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
docker volume create cloudflare-relay-config >/dev/null
sed "s/@RELAY_TAILNET_IP@/$relay_ip/" "$script_dir/squid.conf.template" |
  docker run --rm -i --network none \
    --mount type=volume,src=cloudflare-relay-config,dst=/config \
    alpine:3 sh -eu -c '
      cat > /config/squid.conf.new
      chmod 0644 /config/squid.conf.new
      mv /config/squid.conf.new /config/squid.conf
    '
echo "Configuration written to cloudflare-relay-config. Start or restart the relay in TrueNAS."
