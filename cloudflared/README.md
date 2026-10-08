# Patched cloudflared

Based on upstream `2026.10.0`, pinned to commit
`18cdfe0a6fc7b72a0702d255a1f984e776ce0498`. The patch uses only existing dependencies
and the Go standard library. Upstream `go.mod` and `go.sum` remain intact.

## Client usage

Install the Linux package or extract the matching binary archive from the
**Build patched cloudflared** workflow's artifacts. The Debian package is named
`cloudflared-codex`, installs `/usr/bin/cloudflared`, and replaces an installed
upstream `cloudflared` package if necessary. The tarball includes the binary,
license, instructions, and source/patch provenance. Verify the matching
`SHA256SUMS-<architecture>.txt` before installing.

Preserve the cloud environment's inherited `HTTP_PROXY`, `HTTPS_PROXY`, and CA
trust. Use the real TrueNAS tailnet IPv4 address and your allowed email address:

```sh
export TUNNEL_EDGE_PROXY_CHAIN='http://proxy:8088,http://100.101.102.103:3128'
cloudflared tunnel --protocol http2 --edge-ip-version 4 \
  --url http://localhost:5173 --allowed-mail you@example.com
```

The same setting is available as `--edge-proxy-chain` or the `edge-proxy-chain`
key in a cloudflared YAML configuration file. Put tunnel flags before `run` for
named tunnels. The ordered chain dials the runtime proxy, CONNECTs to the
tailnet relay, and then CONNECTs to the discovered Cloudflare edge. With no
chain configured, upstream's direct connection and protocol selection remain.

When a chain is configured, `auto` selects HTTP/2 and explicit QUIC is rejected.
The proxy path never falls back to a direct edge socket. Malformed URLs fail
early. Proxy URLs must be `http://host:port`, with no credentials, paths, queries,
or fragments; relay authentication comes from tailnet access controls.

Cloudflared still performs the original TLS handshake with the edge, including
hostname, trust-root, and certificate checks. The patch preserves bytes read
ahead while parsing CONNECT responses, applies connection timeouts and
cancellation, and closes rejected or failed sockets. Direct connectivity
prechecks are skipped for explicit proxy chains because those probes do not
use the configured route.

Quick Tunnel provisioning uses the environment HTTP proxy. The OTP broker's
JWKS client already uses Go's default proxy-aware transport. Allow HTTPS to
`api.trycloudflare.com` and `login.trycloudflare.com` through the environment's
supported HTTP policy configuration; configuring the raw relay does not grant
those HTTP destinations. The Go system CA trust must include the runtime proxy
CA. Protected previews require an interactive browser login.

Normal DNS must resolve Cloudflare's edge SRV and A records. The upstream direct
DNS-over-TLS fallback to `1.1.1.1:853` is not relayed by this patch or permitted
by the Squid allowlist. IPv6 and regional edge pools are not in the supplied
relay configuration. Cloudflare Quick Tunnel limitations still apply.

The build sets a local version suffix and package-manager marker so the
upstream auto-updater cannot replace the patched binary with an unpatched one.

## Building

The workflow runs on pushes or pull requests changing this directory or the
workflow, and can also be started with **Run workflow**. It first applies the
patch to pinned upstream source and runs race tests plus vet for the affected
packages. Two build jobs then produce static Linux amd64 and arm64 binaries,
tarballs, Debian packages, and SHA256 checksum files as Actions artifacts.
It does not publish a release or container image.

To run the same commands locally on Linux with Git, the version of Go in
`go-version`, and `dpkg-deb`:

```sh
bash cloudflared/scripts/prepare-source.sh .build/cloudflared
bash cloudflared/scripts/test.sh .build/cloudflared
bash cloudflared/scripts/build.sh .build/cloudflared amd64 dist
bash cloudflared/scripts/build.sh .build/cloudflared arm64 dist
```

Upgrade by changing `upstream.env`, refreshing the patch against the new pinned
commit, and running the tests and both builds. Increment `PATCH_REVISION` for
patch changes. Actions are pinned to verified commits; the Go version is pinned
in `go-version`.

Sources: [upstream source](https://github.com/cloudflare/cloudflared/tree/2026.10.0),
[protected Quick Tunnels](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/#restrict-access-by-email).
