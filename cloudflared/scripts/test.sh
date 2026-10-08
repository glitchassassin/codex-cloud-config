#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <patched source directory>" >&2
  exit 2
fi
cd -- "$1"

files=(
  edgeproxy/chain.go edgeproxy/chain_test.go edgediscovery/dial.go
  cmd/cloudflared/flags/flags.go cmd/cloudflared/tunnel/cmd.go
  cmd/cloudflared/tunnel/configuration.go cmd/cloudflared/tunnel/quick_tunnel.go
  cmd/cloudflared/tunnel/subcommands.go cmd/cloudflared/tunnel/edge_proxy_test.go
  supervisor/tunnel.go
)
unformatted=$(gofmt -l "${files[@]}")
if [[ -n "$unformatted" ]]; then
  printf 'Go files need formatting:\n%s\n' "$unformatted" >&2
  exit 1
fi

go test -mod=readonly -race -timeout=5m \
  ./edgeproxy ./edgediscovery/... ./cmd/cloudflared/tunnel ./supervisor ./quicktunnelauth
go vet -mod=readonly \
  ./edgeproxy ./edgediscovery/... ./cmd/cloudflared/tunnel ./supervisor ./quicktunnelauth
git diff --exit-code -- go.mod go.sum
