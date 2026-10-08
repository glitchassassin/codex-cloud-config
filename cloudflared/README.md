# Patched cloudflared

Based on upstream `2026.10.0`, pinned to commit
`18cdfe0a6fc7b72a0702d255a1f984e776ce0498`. The patch uses only existing dependencies
and the Go standard library. Upstream `go.mod` and `go.sum` remain intact.

## Client usage

Download from the public [GitHub Releases](https://github.com/glitchassassin/codex-cloud-config/releases/latest).
Each release includes static `cloudflared-linux-amd64` and `cloudflared-linux-arm64`
binaries, versioned archives and Debian packages, and `SHA256SUMS.txt`.
Downloads do not require GitHub authentication. The Debian package is named
`cloudflared-codex`, installs `/usr/bin/cloudflared`, and replaces an installed
upstream `cloudflared` package if necessary. The tarball includes the binary,
license, instructions, and source/patch provenance. Verify the matching
`SHA256SUMS-<architecture>.txt` before installing.

For a cloud job, resolve the latest release once so the binary and its checksum
come from the same release, then install the binary in the user's local bin:

```sh
set -eu
case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
release_tag=$(curl -fsSL --retry 3 \
  https://api.github.com/repos/glitchassassin/codex-cloud-config/releases/latest \
  | python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])')
release_base="https://github.com/glitchassassin/codex-cloud-config/releases/download/$release_tag"
download_dir=$(mktemp -d)
curl -fsSL --retry 3 "$release_base/cloudflared-linux-$arch" \
  -o "$download_dir/cloudflared-linux-$arch"
curl -fsSL --retry 3 "$release_base/SHA256SUMS.txt" \
  -o "$download_dir/SHA256SUMS.txt"
(cd "$download_dir" && sha256sum --check --ignore-missing SHA256SUMS.txt)
mkdir -p "$HOME/.local/bin"
install -m 0755 "$download_dir/cloudflared-linux-$arch" "$HOME/.local/bin/cloudflared"
rm -rf -- "$download_dir"
export PATH="$HOME/.local/bin:$PATH"
cloudflared --version
```

For reproducible jobs, set `release_tag` to a specific published tag instead of
querying the latest release. Stable latest binary links are also available at
`https://github.com/glitchassassin/codex-cloud-config/releases/latest/download/cloudflared-linux-amd64`
and the equivalent `cloudflared-linux-arm64` URL. The environment's HTTP policy
must allow `api.github.com`, `github.com`, and GitHub's release asset download
host (`release-assets.githubusercontent.com`). Keep the inherited proxy and CA
settings when downloading.

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
After both builds pass, runs on `main` publish these files and fixed-name binary
assets to a GitHub Release. Pull requests and other branches do not publish.
Only the publication job has repository write permission, using the workflow's
built-in token; no additional secret is needed.

Release tags have the form `cloudflared-v<version>-codex.<revision>-<commit-prefix>`.
Published assets are preserved when a run is retried; interrupted draft uploads
can resume. The latest release advances only for the current `main` commit.

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
