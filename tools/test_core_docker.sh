#!/usr/bin/env bash
# Build and test OverstayCore in the official Swift Linux image (works from Windows via Docker Desktop).
# Usage (Git Bash): tools/test_core_docker.sh
IMAGE="swift:6.2@sha256:9bea530093ffff8cf6c259991715ee843fe4d0f932e612f7f4b79cca6e00db87"   # digest-pinned (index digest); same pin as ci.yml core-linux: bump both together
set -euo pipefail
cd "$(dirname "$0")/.."
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W 2>/dev/null || pwd):/src:ro" "$IMAGE" bash -c '
  mkdir -p /work && cp -r /src/Package.swift /src/Sources /src/Tests /work/ &&
  cd /work && swift build --target OverstayCore && swift test --filter OverstayCoreTests'
