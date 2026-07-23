#!/usr/bin/env bash
#
# Install the mb (MorganaBench) CLI from GitHub Releases.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/morganalabs/mb-cli/main/install.sh | bash
#   MB_VERSION=1.2.3 curl -fsSL ... | bash
#
# Environment variables:
#   MB_VERSION   - Version to install (default: latest)
#   INSTALL_DIR  - Installation directory (default: /usr/local/bin)
#
set -euo pipefail

GITHUB_REPO="morganalabs/mb-cli"

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

# --- Resolve version (latest if not specified) ---
RELEASES_PAGE="https://github.com/${GITHUB_REPO}/releases"
if [ -z "${MB_VERSION:-}" ]; then
  echo "Resolving latest version..."
  # GitHub's /releases/latest points at the release flagged make_latest by CI,
  # so this is the newest published version. The v? keeps the tag_name parse
  # working whether or not the tag carries a leading "v".
  MB_VERSION=$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" \
    | grep '"tag_name"' | head -1 \
    | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"]+)".*/\1/')
  if [ -z "$MB_VERSION" ]; then
    echo "Error: Could not determine the latest version." >&2
    echo "  See ${RELEASES_PAGE} or set MB_VERSION explicitly (e.g. MB_VERSION=0.4.0, no leading 'v')." >&2
    exit 1
  fi
  echo "Latest version: ${MB_VERSION}"
fi

# --- Detect OS and architecture ---
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$OS" in
  linux)  OS="linux" ;;
  darwin) OS="darwin" ;;
  *)      echo "Error: Unsupported OS: $OS" >&2; exit 1 ;;
esac

case "$ARCH" in
  x86_64)        ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)             echo "Error: Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

echo "Detected platform: ${OS}/${ARCH}"

# --- Determine archive name ---
ARCHIVE_NAME="morganabench_${OS}_${ARCH}.tar.gz"
CHECKSUMS_NAME="checksums.txt"

DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/v${MB_VERSION}/${ARCHIVE_NAME}"
CHECKSUMS_URL="https://github.com/${GITHUB_REPO}/releases/download/v${MB_VERSION}/${CHECKSUMS_NAME}"

# --- Download ---
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "Downloading ${ARCHIVE_NAME}..."
if ! curl -fSL --progress-bar --output "${TMPDIR}/${ARCHIVE_NAME}" "$DOWNLOAD_URL"; then
  echo "Error: Download failed — version ${MB_VERSION} may not exist." >&2
  echo "  Available versions: ${RELEASES_PAGE}" >&2
  echo "  (use the number without a leading 'v', e.g. MB_VERSION=0.4.0)" >&2
  exit 1
fi

echo "Downloading checksums..."
curl -fsSL --output "${TMPDIR}/${CHECKSUMS_NAME}" "$CHECKSUMS_URL"

# --- Verify checksum ---
echo "Verifying checksum..."
cd "$TMPDIR"

hash_sha256() {
  local hash
  if command -v gsha256sum &>/dev/null; then
    gsha256sum "$1" | cut -d ' ' -f 1
  elif command -v shasum &>/dev/null; then
    shasum -a 256 "$1" | cut -d ' ' -f 1
  elif command -v sha256sum &>/dev/null; then
    hash=$(sha256sum "$1" 2>/dev/null || sha256sum -b "$1" 2>/dev/null) || true
    if [ -n "$hash" ]; then
      echo "$hash" | cut -d ' ' -f 1
    fi
  elif command -v openssl &>/dev/null; then
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  else
    echo ""
  fi
}

EXPECTED=$(grep "${ARCHIVE_NAME}" "${CHECKSUMS_NAME}" | tr '\t' ' ' | cut -d ' ' -f 1)
ACTUAL=$(hash_sha256 "${ARCHIVE_NAME}")

if [ -z "$ACTUAL" ]; then
  echo "Warning: No sha256sum, shasum, gsha256sum, or openssl found, skipping checksum verification" >&2
elif [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "Error: Checksum mismatch for ${ARCHIVE_NAME}" >&2
  echo "  Expected: $EXPECTED" >&2
  echo "  Actual:   $ACTUAL" >&2
  exit 1
fi

# --- Extract and install ---
echo "Extracting..."
tar xzf "${ARCHIVE_NAME}"

echo "Installing mb to ${INSTALL_DIR}/mb..."
if [ -w "$INSTALL_DIR" ]; then
  mv mb "${INSTALL_DIR}/mb"
else
  echo "  ${INSTALL_DIR} is not writable; using sudo — you may be prompted for your system password." >&2
  sudo mv mb "${INSTALL_DIR}/mb"
fi

chmod +x "${INSTALL_DIR}/mb"

echo ""
echo "✓ mb ${MB_VERSION} installed to ${INSTALL_DIR}/mb"
"${INSTALL_DIR}/mb" --version 2>/dev/null || true
