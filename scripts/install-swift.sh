#!/usr/bin/env bash
# Install a Swift toolchain on Linux CI / Claude Code web containers.
#
# The FM* packages are framework-free and build on any Swift 6 toolchain, so a
# Linux container can compile and test them — but only if one is installed.
# macOS developers never need this; Xcode provides the toolchain.
#
# Requires the environment's network policy to allow download.swift.org.
#
# Usage:  ./scripts/install-swift.sh [version]
#         SWIFT_VERSION=6.1.2 ./scripts/install-swift.sh
set -euo pipefail

PREFIX="${SWIFT_PREFIX:-/opt/swift}"
UBUNTU_TAG="ubuntu24.04"
UBUNTU_SLUG="ubuntu2404"

# Tried in order. Override with SWIFT_VERSION or argv[1] to pin exactly.
CANDIDATES=("${1:-${SWIFT_VERSION:-}}" 6.2 6.1.2 6.1 6.0.3)

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

if command -v swift >/dev/null 2>&1; then
  log "Swift already present: $(swift --version 2>&1 | head -1)"
  exit 0
fi

[ "$(uname -s)" = "Linux" ] || die "This script is for Linux. On macOS, install Xcode."

log "Installing runtime dependencies"
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq --no-install-recommends \
  binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev \
  libncurses-dev libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev \
  libz3-dev pkg-config tzdata unzip zlib1g-dev curl ca-certificates \
  >/dev/null

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fetch() {
  local ver="$1"
  local url="https://download.swift.org/swift-${ver}-release/${UBUNTU_SLUG}/swift-${ver}-RELEASE/swift-${ver}-RELEASE-${UBUNTU_TAG}.tar.gz"
  log "Trying Swift ${ver}"
  curl -fSL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$work/swift.tar.gz" "$url"
}

installed=""
for ver in "${CANDIDATES[@]}"; do
  [ -n "$ver" ] || continue
  if fetch "$ver"; then installed="$ver"; break; fi
  log "Swift ${ver} unavailable, trying next"
done

if [ -z "$installed" ]; then
  cat >&2 <<'MSG'
ERROR: could not download a Swift toolchain.

If this failed with a 403 from the proxy, the environment's network policy is
blocking download.swift.org. Allow that host in the environment settings —
see https://code.claude.com/docs/en/claude-code-on-the-web
MSG
  exit 1
fi

log "Extracting to ${PREFIX}"
$SUDO mkdir -p "$PREFIX"
$SUDO tar -xzf "$work/swift.tar.gz" -C "$PREFIX" --strip-components=1

for bin in "$PREFIX"/usr/bin/*; do
  [ -x "$bin" ] || continue
  $SUDO ln -sf "$bin" "/usr/local/bin/$(basename "$bin")"
done

command -v swift >/dev/null 2>&1 || die "swift not on PATH after install"
log "Installed: $(swift --version 2>&1 | head -1)"
