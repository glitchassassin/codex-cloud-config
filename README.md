# Codex cloud configuration

Publish protected development previews from cloud workspaces whose raw TCP
connections can reach a Tailscale relay through the runtime's CONNECT proxy.

```text
cloudflared → proxy:8088 → TrueNAS Squid:3128 → Cloudflare edge:7844
```

- [`relay/`](relay/README.md) contains the TrueNAS app YAML, Squid configuration,
  and a script to populate its named Docker volume.
- [`cloudflared/`](cloudflared/README.md) contains a patch against pinned upstream
  source, build scripts, and client usage instructions.
- [The build workflow](.github/workflows/build-cloudflared.yml) tests the patch
  and creates Linux amd64 and arm64 tarballs and Debian packages with checksums.

The relay must have Internet access. The cloud environment needs a raw TCP grant
for the relay's tailnet IPv4 address, and Tailscale policy must permit TCP 3128
from the cloud workspace's sidecar identity to the TrueNAS node.

Published preview access is controlled separately by `--allowed-mail`. Proxy
access does not authenticate visitors to the preview URL.
