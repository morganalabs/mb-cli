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
if [ -z "${MB_VERSION:-}" ]; then
  echo "Resolving latest version..."
  MB_VERSION=$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" \
    | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')
  if [ -z "$MB_VERSION" ]; then
    echo "Error: Could not determine latest version. Set MB_VERSION explicitly." >&2
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
  echo "Error: Download failed. Check that version ${MB_VERSION} exists at:" >&2
  echo "  https://github.com/${GITHUB_REPO}/releases/tag/v${MB_VERSION}" >&2
  exit 1
fi

echo "Downloading checksums..."
curl -fsSL --output "${TMPDIR}/${CHECKSUMS_NAME}" "$CHECKSUMS_URL"

# --- Verify checksum ---
echo "Verifying checksum..."
cd "$TMPDIR"
if command -v sha256sum &>/dev/null; then
  grep "${ARCHIVE_NAME}" "${CHECKSUMS_NAME}" | sha256sum --check --quiet
elif command -v shasum &>/dev/null; then
  grep "${ARCHIVE_NAME}" "${CHECKSUMS_NAME}" | shasum -a 256 --check --quiet
else
  echo "Warning: No sha256sum or shasum found, skipping checksum verification" >&2
fi

# --- Extract and install ---
echo "Extracting..."
tar xzf "${ARCHIVE_NAME}"

echo "Installing mb to ${INSTALL_DIR}/mb..."
if [ -w "$INSTALL_DIR" ]; then
  mv mb "${INSTALL_DIR}/mb"
else
  sudo mv mb "${INSTALL_DIR}/mb"
fi

chmod +x "${INSTALL_DIR}/mb"

echo ""
echo "✓ mb ${MB_VERSION} installed to ${INSTALL_DIR}/mb"
"${INSTALL_DIR}/mb" --version 2>/dev/null || true
