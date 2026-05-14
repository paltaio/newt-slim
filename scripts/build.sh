#!/usr/bin/env bash
# Usage: scripts/build.sh <upstream-tag> <goos> <goarch> [goarm|gomips]
#   scripts/build.sh v1.4.0 linux arm 7
#   scripts/build.sh v1.4.0 linux mipsle softfloat
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "usage: $0 <upstream-tag> <goos> <goarch> [goarm|gomips]" >&2
  exit 2
fi

UPSTREAM_TAG="$1"
GOOS="$2"
GOARCH="$3"
EXTRA="${4:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone --depth=1 --branch "$UPSTREAM_TAG" \
  https://github.com/fosrl/newt.git "$WORK/upstream"

(
  cd "$WORK/upstream"
  git -c user.email=bot@local -c user.name=newt-slim \
    am --3way "$ROOT"/patches/*.patch
)

case "$GOARCH" in
  arm)            export GOARM="$EXTRA" ;;
  mips|mipsle)    export GOMIPS="$EXTRA" ;;
esac

export CGO_ENABLED=0 GOOS GOARCH
mkdir -p "$ROOT/out"
SUFFIX="${GOOS}-${GOARCH}${EXTRA:+-${EXTRA}}"
OUT="$ROOT/out/newt-${UPSTREAM_TAG}-min-${SUFFIX}"

(
  cd "$WORK/upstream"
  go build \
    -tags=minimal \
    -trimpath \
    -ldflags "-s -w -buildid= -X main.newtVersion=${UPSTREAM_TAG}+min" \
    -o "$OUT" .
)

cp "$OUT" "${OUT}.upx"
upx --best --lzma "${OUT}.upx" >/dev/null
ls -lh "$OUT" "${OUT}.upx"
