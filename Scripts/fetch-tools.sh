#!/usr/bin/env bash
set -euo pipefail

# Scripts/fetch-tools.sh
# Downloads and prepares yt-dlp, QuickJS-ng, and ffmpeg into Resources/Tools/

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="${ROOT_DIR}/Resources/Tools"
VERSIONS_JSON="${ROOT_DIR}/Tools/versions.json"

mkdir -p "${TOOLS_DIR}"

echo "=== Fetching Tools for Kodiz Download Manager ==="

# Read versions from Tools/versions.json
YTDLP_VER=$(grep -o '"version": "[^"]*' "${VERSIONS_JSON}" | head -1 | cut -d'"' -f4)
echo "Target yt-dlp version: ${YTDLP_VER}"

# Download yt-dlp standalone for macOS
if [ ! -f "${TOOLS_DIR}/yt-dlp/yt-dlp" ]; then
    echo "Downloading yt-dlp..."
    mkdir -p "${TOOLS_DIR}/yt-dlp"
    curl -L "https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VER}/yt-dlp_macos.zip" -o "${TOOLS_DIR}/yt-dlp.zip"
    unzip -q -o "${TOOLS_DIR}/yt-dlp.zip" -d "${TOOLS_DIR}/yt-dlp/" || true
    rm -f "${TOOLS_DIR}/yt-dlp.zip"
    chmod +x "${TOOLS_DIR}/yt-dlp/yt-dlp" 2>/dev/null || true
fi

# Download QuickJS-ng for macOS (arm64 / universal)
if [ ! -f "${TOOLS_DIR}/qjs" ]; then
    echo "Downloading QuickJS-ng..."
    curl -L "https://github.com/quickjs-ng/quickjs/releases/download/v0.12.0/qjs-macos-arm64" -o "${TOOLS_DIR}/qjs" || true
    chmod +x "${TOOLS_DIR}/qjs" || true
fi

echo "✓ Tools setup completed in ${TOOLS_DIR}"
