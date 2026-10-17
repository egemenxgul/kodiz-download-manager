#!/usr/bin/env bash
set -euo pipefail

# Scripts/fetch-tools.sh
# Downloads and prepares verified binaries of yt-dlp and QuickJS-ng into Resources/Tools/

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="${ROOT_DIR}/Resources/Tools"
VERSIONS_JSON="${ROOT_DIR}/Tools/versions.json"

mkdir -p "${TOOLS_DIR}"

echo "=== Fetching Tools for Kodiz Download Manager ==="

# Helper function to read json keys using python3
get_json_val() {
    local key_path="$1"
    python3 -I -c "
import json, sys
data = json.load(open('${VERSIONS_JSON}'))
keys = '${key_path}'.split('.')
val = data
for k in keys:
    val = val[k]
print(val)
"
}

verify_sha256() {
    local file_path="$1"
    local expected_hash="$2"
    local actual_hash
    actual_hash=$(shasum -a 256 "${file_path}" | awk '{print $1}')
    if [ "${actual_hash}" != "${expected_hash}" ]; then
        echo "❌ SHA-256 verification failed for ${file_path}!"
        echo "Expected: ${expected_hash}"
        echo "Actual:   ${actual_hash}"
        exit 1
    fi
    echo "✓ SHA-256 verified for $(basename "${file_path}")"
}

# 1. Fetch & Verify yt-dlp
YTDLP_VER=$(get_json_val "yt-dlp.version")
YTDLP_URL=$(get_json_val "yt-dlp.release_url")
YTDLP_SHA=$(get_json_val "yt-dlp.sha256")

echo "--- yt-dlp (${YTDLP_VER}) ---"
mkdir -p "${TOOLS_DIR}/yt-dlp"

if [ ! -f "${TOOLS_DIR}/yt-dlp/yt-dlp" ]; then
    TMP_ZIP="/tmp/kodiz-yt-dlp.zip"
    echo "Downloading yt-dlp from ${YTDLP_URL}..."
    curl -fL "${YTDLP_URL}" -o "${TMP_ZIP}"
    verify_sha256 "${TMP_ZIP}" "${YTDLP_SHA}"

    echo "Extracting yt-dlp..."
    unzip -q -o "${TMP_ZIP}" -d "${TOOLS_DIR}/yt-dlp/"
    rm -f "${TMP_ZIP}"

    # Ensure executable named yt-dlp is available alongside its _internal folder
    if [ -f "${TOOLS_DIR}/yt-dlp/yt-dlp_macos" ]; then
        ln -sf "yt-dlp_macos" "${TOOLS_DIR}/yt-dlp/yt-dlp"
        chmod +x "${TOOLS_DIR}/yt-dlp/yt-dlp_macos" "${TOOLS_DIR}/yt-dlp/yt-dlp"
    fi
fi

# Smoke test yt-dlp
echo "Testing yt-dlp binary..."
"${TOOLS_DIR}/yt-dlp/yt-dlp" --version
echo "✓ yt-dlp ready at ${TOOLS_DIR}/yt-dlp/yt-dlp"

# 2. Fetch & Build Universal QuickJS-ng
QJS_VER=$(get_json_val "quickjs-ng.version")
QJS_URL_ARM64=$(get_json_val "quickjs-ng.release_url_arm64")
QJS_SHA_ARM64=$(get_json_val "quickjs-ng.sha256_arm64")
QJS_URL_X86_64=$(get_json_val "quickjs-ng.release_url_x86_64")
QJS_SHA_X86_64=$(get_json_val "quickjs-ng.sha256_x86_64")

echo "--- QuickJS-ng (${QJS_VER}) ---"
if [ ! -f "${TOOLS_DIR}/qjs" ]; then
    TMP_ARM64="/tmp/kodiz-qjs-arm64"
    TMP_X86_64="/tmp/kodiz-qjs-x86_64"

    echo "Downloading arm64 qjs..."
    curl -fL "${QJS_URL_ARM64}" -o "${TMP_ARM64}"
    verify_sha256 "${TMP_ARM64}" "${QJS_SHA_ARM64}"

    echo "Downloading x86_64 qjs..."
    curl -fL "${QJS_URL_X86_64}" -o "${TMP_X86_64}"
    verify_sha256 "${TMP_X86_64}" "${QJS_SHA_X86_64}"

    echo "Creating universal binary with lipo..."
    lipo -create "${TMP_ARM64}" "${TMP_X86_64}" -output "${TOOLS_DIR}/qjs"
    chmod +x "${TOOLS_DIR}/qjs"
    rm -f "${TMP_ARM64}" "${TMP_X86_64}"
fi

# Smoke test qjs
echo "Testing QuickJS-ng universal binary..."
"${TOOLS_DIR}/qjs" -e 'console.log("QuickJS-ng initialized successfully")'
echo "✓ QuickJS-ng ready at ${TOOLS_DIR}/qjs"

# 3. ffmpeg status
FFMPEG_STATUS=$(get_json_val "ffmpeg.status")
echo "--- ffmpeg: ${FFMPEG_STATUS} (out of scope for this task) ---"

echo "=== All required tools fetched and verified in ${TOOLS_DIR} ==="
