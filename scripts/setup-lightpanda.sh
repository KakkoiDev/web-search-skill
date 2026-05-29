#!/usr/bin/env bash
#
# Setup Lightpanda headless browser
# Downloads the nightly binary for the current platform
#
set -euo pipefail

PLATFORM="$(uname -s)"
ARCH="$(uname -m)"
INSTALL_DIR="${HOME}/.local/bin"
BINARY="${INSTALL_DIR}/lightpanda"

case "${PLATFORM}-${ARCH}" in
  Darwin-arm64|Darwin-aarch64)
    URL="https://github.com/lightpanda-io/browser/releases/download/nightly/lightpanda-aarch64-macos"
    ;;
  Darwin-x86_64)
    URL="https://github.com/lightpanda-io/browser/releases/download/nightly/lightpanda-x86_64-macos"
    ;;
  Linux-x86_64)
    URL="https://github.com/lightpanda-io/browser/releases/download/nightly/lightpanda-x86_64-linux"
    ;;
  Linux-aarch64|Linux-arm64)
    URL="https://github.com/lightpanda-io/browser/releases/download/nightly/lightpanda-aarch64-linux"
    ;;
  *)
    echo "Unsupported platform: ${PLATFORM}-${ARCH}" >&2
    exit 1
    ;;
esac

mkdir -p "${INSTALL_DIR}"

if [ -x "${BINARY}" ]; then
  echo "Lightpanda already installed at ${BINARY}"
  echo "To reinstall, remove it first: rm ${BINARY}"
  exit 0
fi

echo "Downloading Lightpanda for ${PLATFORM}-${ARCH}..."
curl -fsSL -o "${BINARY}" "${URL}" || {
  echo "Download failed. Check: ${URL}" >&2
  exit 1
}

chmod +x "${BINARY}"

echo "Installed lightpanda to ${BINARY}"

# Check if INSTALL_DIR is in PATH
case ":${PATH}:" in
  *:"${INSTALL_DIR}":*) ;;
  *)
    echo ""
    echo "NOTE: ${INSTALL_DIR} is not in your PATH."
    echo "Add it to your shell profile:"
    echo "  export PATH=\"\${HOME}/.local/bin:\${PATH}\""
    ;;
esac

echo ""
echo "Verify: ${BINARY} --help"
