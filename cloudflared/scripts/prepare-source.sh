#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <new source directory>" >&2
  exit 2
fi
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
patch_dir=$(cd -- "$script_dir/.." && pwd)
source "$patch_dir/upstream.env"
source_dir=$1

if [[ -e "$source_dir" ]]; then
  echo "Source directory already exists; choose a new path: $source_dir" >&2
  exit 2
fi
mkdir -p -- "$source_dir"
git -C "$source_dir" init --quiet
git -C "$source_dir" remote add origin https://github.com/cloudflare/cloudflared.git
git -C "$source_dir" fetch --quiet --depth 1 origin "refs/tags/$UPSTREAM_VERSION"
git -C "$source_dir" checkout --quiet --detach FETCH_HEAD
actual_commit=$(git -C "$source_dir" rev-parse HEAD)
if [[ "$actual_commit" != "$UPSTREAM_COMMIT" ]]; then
  echo "Upstream tag does not match the pinned commit; refusing to apply the patch" >&2
  exit 1
fi
git -C "$source_dir" apply --check "$patch_dir/patches/0001-edge-proxy-chain.patch"
git -C "$source_dir" apply "$patch_dir/patches/0001-edge-proxy-chain.patch"
printf 'Prepared cloudflared %s at %s\n' "$UPSTREAM_VERSION" "$actual_commit"
