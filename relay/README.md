# TrueNAS relay

Use the existing Tailscale app with **Host Network enabled** and **Userspace
disabled**. Squid is a separate custom app sharing the host network. It binds
only to the TrueNAS node's Tailscale IPv4 address, not to the LAN or public IP.

Run on TrueNAS, from this repository, replacing the example address:

```sh
sudo bash relay/configure-volume.sh 100.101.102.103
```

This creates or reuses the named volume `cloudflare-relay-config` and writes a
complete `squid.conf` through a temporary helper container. No dataset bind mount
is needed. Configuration files are replaced atomically. For changes, stop the
relay app, run the command again, and start the app through TrueNAS.

In **Apps → Discover Apps → ⋮ → Install via YAML**, use `compose.yaml`. The volume
must be populated before deployment. The app reads the volume at `/etc/squid`
with read-only access. Leave the image's user and entrypoint defaults intact.

Tailscale must be running before Squid can bind its address. Restrict access to
the TrueNAS node's TCP 3128 to the cloud workspace identities. Tailscale grants
are additive: an existing broad allow rule can also permit access to the relay.
The runtime's raw TCP grants also need to include the relay's tailnet IP `/32`;
new grants require a replacement cloud environment.

Squid permits only HTTP CONNECT to the documented global Cloudflare edge IPv4
addresses on TCP 7844 and denies all other requests. It does not decrypt edge
TLS. Use `--edge-ip-version 4` on the patched client. Other Cloudflare regions
need their corresponding destination IPs added explicitly.

Sources: [TrueNAS custom apps](https://apps.truenas.com/managing-apps/installing-custom-apps/),
[Canonical image tags](https://hub.docker.com/r/ubuntu/squid/tags),
[Cloudflare edge addresses](https://developers.cloudflare.com/tunnel/configuration/#firewall-rules).
