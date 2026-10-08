#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 || ( "$2" != amd64 && "$2" != arm64 ) ]]; then
  echo "Usage: $0 <patched source directory> <amd64|arm64> <output directory>" >&2
  exit 2
fi
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
patch_dir=$(cd -- "$script_dir/.." && pwd)
source "$patch_dir/upstream.env"
source_dir=$(cd -- "$1" && pwd)
target_arch=$2
mkdir -p -- "$3"
output_dir=$(cd -- "$3" && pwd)
version="$UPSTREAM_VERSION-codex.$PATCH_REVISION"
package_version="$UPSTREAM_VERSION+codex.$PATCH_REVISION"

command -v dpkg-deb >/dev/null || { echo "Package builds require dpkg-deb (run on Linux)" >&2; exit 1; }
build_root=$(mktemp -d)
trap 'rm -rf -- "$build_root"' EXIT
stage="$build_root/cloudflared-$version-linux-$target_arch"
mkdir -p "$stage"

cd -- "$source_dir"
actual_commit=$(git rev-parse HEAD)
[[ "$actual_commit" == "$UPSTREAM_COMMIT" ]] || { echo "Source commit does not match upstream.env" >&2; exit 1; }
# Prevent accidentally packaging an unpatched or partially edited source tree.
git apply --reverse --check "$patch_dir/patches/0001-edge-proxy-chain.patch"
export SOURCE_DATE_EPOCH
SOURCE_DATE_EPOCH=$(git show -s --format=%ct HEAD)
build_time=$(date -u -d "@$SOURCE_DATE_EPOCH" '+%Y-%m-%dT%H:%M:%SZ')
ldflags="-s -w -X main.Version=$version -X main.BuildTime=$build_time -X github.com/cloudflare/cloudflared/cmd/cloudflared/updater.BuiltForPackageManager=codex-cloud-config"
CGO_ENABLED=0 GOOS=linux GOARCH="$target_arch" \
  go build -mod=readonly -trimpath -buildvcs=false -ldflags "$ldflags" \
  -o "$stage/cloudflared" ./cmd/cloudflared
# Exercise the real CLI on the runner's native architecture. Rejecting QUIC
# must happen before DNS, provisioning, or any attempt to contact a proxy.
if [[ $(go env GOHOSTOS) == linux && $(go env GOHOSTARCH) == "$target_arch" ]]; then
  "$stage/cloudflared" --version
  "$stage/cloudflared" tunnel --help > "$build_root/help.txt"
  grep -q -- '--edge-proxy-chain' "$build_root/help.txt"
  if "$stage/cloudflared" tunnel --protocol quic \
    --edge-proxy-chain http://127.0.0.1:1 \
    --url http://localhost:5173 > "$build_root/rejection.txt" 2>&1; then
    echo "CLI unexpectedly accepted a QUIC proxy chain" >&2
    exit 1
  fi
  grep -q -- 'edge-proxy-chain requires' "$build_root/rejection.txt"
fi
install -m 0644 LICENSE "$stage/LICENSE"
install -m 0644 "$patch_dir/README.md" "$stage/README.md"
patch_sha256=$(sha256sum "$patch_dir/patches/0001-edge-proxy-chain.patch" | cut -d ' ' -f 1)
printf 'Upstream: %s\nCommit: %s\nPatch SHA256: %s\nGo: %s\nTarget: linux/%s\n' \
  "$UPSTREAM_VERSION" "$UPSTREAM_COMMIT" "$patch_sha256" "$(go version)" "$target_arch" > "$stage/BUILD-INFO.txt"

# A gzip timestamp of zero plus normalized ownership and file times makes the
# archive repeatable for the same toolchain, source, patch, and architecture.
archive="cloudflared-$version-linux-$target_arch.tar.gz"
tar --sort=name --mtime="@$SOURCE_DATE_EPOCH" --owner=0 --group=0 --numeric-owner \
  -C "$build_root" -cf - "$(basename "$stage")" | gzip -n > "$output_dir/$archive"

deb_root="$build_root/deb"
mkdir -p "$deb_root/DEBIAN" "$deb_root/usr/bin" "$deb_root/usr/share/doc/cloudflared-codex"
install -m 0755 "$stage/cloudflared" "$deb_root/usr/bin/cloudflared"
install -m 0644 "$stage/LICENSE" "$deb_root/usr/share/doc/cloudflared-codex/copyright"
install -m 0644 "$stage/BUILD-INFO.txt" "$deb_root/usr/share/doc/cloudflared-codex/BUILD-INFO.txt"
cat > "$deb_root/DEBIAN/control" <<CONTROL
Package: cloudflared-codex
Version: $package_version
Architecture: $target_arch
Section: net
Priority: optional
Maintainer: codex-cloud-config contributors <noreply@example.invalid>
Depends: ca-certificates
Provides: cloudflared
Conflicts: cloudflared
Replaces: cloudflared
Homepage: https://github.com/cloudflare/cloudflared
Description: Cloudflared with explicit HTTP CONNECT edge proxy support
 Locally maintained patch for cloud workspaces and tailnet relays.
CONTROL
deb="cloudflared-codex_${package_version}_${target_arch}.deb"
dpkg-deb --build --root-owner-group "$deb_root" "$output_dir/$deb"
(
  cd -- "$output_dir"
  sha256sum "$archive" "$deb" > "SHA256SUMS-$target_arch.txt"
)
git diff --exit-code -- go.mod go.sum
printf 'Built %s and %s\n' "$archive" "$deb"
