#!/bin/bash
# Fetch Unity WebGL build for Astro
# This script downloads and extracts the Unity WebGL build into public/assets/game
# Works for both development and production builds

set -euo pipefail

WEBGL_URL="${WEBGL_URL:-https://unity-bw.kbve.com/webgl.zip?new}"
EXPECTED_VERSION="${EXPECTED_VERSION:-}"
PUBLIC_DIR="$(dirname "$0")/../public"
GAME_DIR="${PUBLIC_DIR}/assets/game"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Fetching Unity WebGL Build                             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check if game files already exist
if [ -d "$GAME_DIR/Build" ] && [ -f "$GAME_DIR/Build/WebGL.wasm" ]; then
    echo "✓ Unity WebGL files already exist at: $GAME_DIR"
    echo "  Skipping download (remove directory to re-download)"
    echo ""
    exit 0
fi

# Create temp directory for download
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "→ Downloading from: $WEBGL_URL"
echo "→ Target directory: $GAME_DIR"
echo ""

# Download with retry logic
MAX_RETRIES=3
RETRY_DELAY=5
attempt=1

while [ $attempt -le $MAX_RETRIES ]; do
    echo "→ Attempt $attempt/$MAX_RETRIES..."

    if curl -L -f --connect-timeout 10 --max-time 120 -o "$TEMP_DIR/webgl.zip" "$WEBGL_URL" 2>&1; then
        echo "✓ Download successful"
        break
    else
        echo "✗ Download failed"
        if [ $attempt -lt $MAX_RETRIES ]; then
            echo "  Retrying in ${RETRY_DELAY}s..."
            sleep $RETRY_DELAY
        else
            echo ""
            echo "ERROR: Failed to download Unity WebGL build after $MAX_RETRIES attempts"
            echo "  URL: $WEBGL_URL"
            echo ""
            echo "This is expected during development if:"
            echo "  - Unity build hasn't been deployed to GitHub Pages yet"
            echo "  - You're working on non-Unity changes"
            echo ""
            echo "For local development, you can:"
            echo "  1. Manually place webgl files in: $GAME_DIR"
            echo "  2. Skip the game page and work on other features"
            echo "  3. Wait for Unity CI to deploy the build"
            echo ""
            exit 1
        fi
        attempt=$((attempt + 1))
    fi
done

# Verify it's a valid ZIP
echo ""
echo "→ Verifying ZIP integrity..."
if ! unzip -t "$TEMP_DIR/webgl.zip" > /dev/null 2>&1; then
    echo "✗ ERROR: Downloaded file is not a valid ZIP"
    exit 1
fi
echo "✓ ZIP verified"

# Extract to public/assets/game
echo ""
echo "→ Extracting to: $GAME_DIR"
mkdir -p "$GAME_DIR"
if ! unzip -q "$TEMP_DIR/webgl.zip" -d "$GAME_DIR"; then
    echo "✗ ERROR: Failed to extract ZIP"
    exit 1
fi

# Verify required files exist
REQUIRED_FILES=("Build/WebGL.wasm" "Build/WebGL.data" "Build/WebGL.loader.js" "Build/WebGL.framework.js")
MISSING_FILES=0

echo ""
echo "→ Verifying extracted files..."
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$GAME_DIR/$file" ]; then
        echo "✗ Missing: $file"
        MISSING_FILES=$((MISSING_FILES + 1))
    else
        echo "✓ Found: $file"
    fi
done

if [ $MISSING_FILES -gt 0 ]; then
    echo ""
    echo "ERROR: WebGL build is incomplete ($MISSING_FILES missing files)"
    exit 1
fi

# Verify version if provided
if [ -n "$EXPECTED_VERSION" ]; then
    echo ""
    echo "→ Checking version..."
    if [ -f "$GAME_DIR/StreamingAssets/version.json" ]; then
        BUILD_VERSION=$(grep -oP '"version":\s*"\K[^"]+' "$GAME_DIR/StreamingAssets/version.json" 2>/dev/null || echo "")
        if [ -n "$BUILD_VERSION" ]; then
            echo "  Expected: $EXPECTED_VERSION"
            echo "  Build:    $BUILD_VERSION"

            if [ "$BUILD_VERSION" != "$EXPECTED_VERSION" ]; then
                echo "⚠️  WARNING: Version mismatch!"
                echo "  This may indicate the Unity build is outdated"
            else
                echo "✓ Version match"
            fi
        fi
    fi
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ✓ Unity WebGL Build Ready                              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
