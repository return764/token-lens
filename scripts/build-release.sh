#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# TokenLens Release Build Script
#
# Produces a signed/notarized .app bundle, optionally wrapped in a DMG.
#
# Usage:
#   ./scripts/build-release.sh              # unsigned .app (local testing)
#   SIGN=1 ./scripts/build-release.sh        # signed .app (needs Apple Developer cert)
#   DMG=1 ./scripts/build-release.sh         # signed + DMG
#   NOTARIZE=1 ./scripts/build-release.sh    # signed + notarized + DMG
#
# Environment variables:
#   SIGN=1           Code-sign the .app (requires DEVELOPER_ID env var)
#   DMG=1            Create a .dmg disk image
#   NOTARIZE=1       Submit for notarization (requires Apple ID credentials)
#   DEVELOPER_ID      Developer ID Application: "Your Name (TEAMID)"
#   APPLE_ID          Apple ID email for notarization
#   APPLE_PASSWORD    App-specific password for notarization
#   APPLE_TEAM_ID     Team ID for notarization
#   VERSION           Version string (default: from git tag or "1.0.0")
#   BUILD_NUM         Build number (default: 1)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
RELEASE_BIN="$BUILD_DIR/arm64-apple-macosx/release/TokenLensApp"
APP_DIR="$BUILD_DIR/TokenLens.app"
PKG_DIR="$PROJECT_DIR/Package"

VERSION="${VERSION:-$(git -C "$PROJECT_DIR" describe --tags --abbrev=0 2>/dev/null || echo "1.0.0")}"
BUILD_NUM="${BUILD_NUM:-1}"

SIGN="${SIGN:-0}"
DMG="${DMG:-0}"
NOTARIZE="${NOTARIZE:-0}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[BUILD]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Validate environment ────────────────────────────────────────────────────

if [[ "$SIGN" == "1" || "$NOTARIZE" == "1" ]]; then
    if [[ -z "${DEVELOPER_ID:-}" ]]; then
        err "SIGN=1/NOTARIZE=1 requires DEVELOPER_ID env var (e.g. 'Developer ID Application: Your Name (TEAMID)')"
    fi
fi

if [[ "$NOTARIZE" == "1" ]]; then
    if [[ -z "${APPLE_ID:-}" || -z "${APPLE_PASSWORD:-}" || -z "${APPLE_TEAM_ID:-}" ]]; then
        err "NOTARIZE=1 requires APPLE_ID, APPLE_PASSWORD, and APPLE_TEAM_ID"
    fi
fi

# ── Build release binary ────────────────────────────────────────────────────

log "Building release binary (swift build -c release)..."
cd "$PROJECT_DIR"
swift build -c release

if [[ ! -f "$RELEASE_BIN" ]]; then
    err "Release binary not found at $RELEASE_BIN"
fi

log "Release binary: $RELEASE_BIN"

# ── Generate app icon (simple placeholder if none exists) ────────────────────

ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

# Generate a simple icon using ImageMagick or built-in tools
if command -v convert &>/dev/null; then
    # ImageMagick is available
    convert -size 1024x1024 xc:'#3B82F6' \
        -fill white -font Helvetica-Bold -pointsize 400 \
        -gravity center -annotate 0 'TL' \
        "$ICONSET_DIR/icon_512x512@2x.png"
    for size in 16 32 128 256 512; do
        convert "$ICONSET_DIR/icon_512x512@2x.png" -resize "${size}x${size}" "$ICONSET_DIR/icon_${size}x${size}.png"
        if [[ "$size" != "512" ]]; then
            convert "$ICONSET_DIR/icon_512x512@2x.png" -resize "$((size*2))x$((size*2))" "$ICONSET_DIR/icon_${size}x${size}@2x.png"
        fi
    done
elif command -v sips &>/dev/null && command -v python3 &>/dev/null; then
    # Use Python to generate a simple PNG, then sips to resize
    python3 - "$ICONSET_DIR/icon_512x512@2x.png" <<'PYEOF'
import sys, struct, zlib

def create_png(path, size, r, g, b):
    """Create a simple solid-color PNG with centered white text 'TL'."""
    from math import ceil
    width, height = size, size

    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)

    # Build raw pixel data
    raw = b''
    for y in range(height):
        raw += b'\x00'  # filter none
        for x in range(width):
            # Simple circle
            cx, cy = width//2, height//2
            radius = width * 0.38
            dist = ((x - cx)**2 + (y - cy)**2) ** 0.5
            if dist < radius:
                raw += bytes([r, g, b, 255])
            elif dist < radius + 2:
                raw += bytes([min(r+40,255), min(g+40,255), min(b+40,255), 255])
            else:
                raw += bytes([30, 30, 35, 255])

    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', ihdr)
    png += chunk(b'IDAT', zlib.compress(raw))
    png += chunk(b'IEND', b'')

    with open(path, 'wb') as f:
        f.write(png)

create_png(sys.argv[1], 1024, 59, 130, 246)
PYEOF

    for size in 16 32 128 256 512; do
        sips -Z "$size" "$ICONSET_DIR/icon_512x512@2x.png" --out "$ICONSET_DIR/icon_${size}x${size}.png" &>/dev/null
        if [[ "$size" != "512" ]]; then
            sips -Z "$((size*2))" "$ICONSET_DIR/icon_512x512@2x.png" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" &>/dev/null
        fi
    done
else
    warn "Neither ImageMagick nor python3+sips available — skipping icon generation"
    warn "The .app will use the default executable icon"
    ICONSET_DIR=""
fi

if [[ -n "$ICONSET_DIR" && -d "$ICONSET_DIR" ]]; then
    ICON_FILE="$BUILD_DIR/AppIcon.icns"
    iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE" 2>/dev/null || {
        warn "iconutil failed — skipping icon"
        ICONSET_DIR=""
    }
    log "App icon generated"
fi

# ── Create .app bundle ──────────────────────────────────────────────────────

log "Creating .app bundle at $APP_DIR..."

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Inject version into Info.plist and copy
sed -e "s|1\.0\.0|$VERSION|g" \
    -e "s|<string>1</string>|<string>$BUILD_NUM</string>|g" \
    "$PKG_DIR/Info.plist" > "$APP_DIR/Contents/Info.plist"

# Copy binary
cp "$RELEASE_BIN" "$APP_DIR/Contents/MacOS/TokenLensApp"
chmod 755 "$APP_DIR/Contents/MacOS/TokenLensApp"

# Copy icon if available
if [[ -n "${ICONSET_DIR:-}" && -f "${ICON_FILE:-}" ]]; then
    cp "$ICON_FILE" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Copy GRDB bundle if it exists (dynamic linking)
GRDB_BUNDLE="$BUILD_DIR/arm64-apple-macosx/release/GRDB_GRDB.bundle"
if [[ -d "$GRDB_BUNDLE" ]]; then
    mkdir -p "$APP_DIR/Contents/Resources"
    cp -R "$GRDB_BUNDLE" "$APP_DIR/Contents/Resources/"
    log "GRDB bundle copied"
fi

log "App bundle created: $APP_DIR"

# ── Code signing ─────────────────────────────────────────────────────────────

if [[ "$SIGN" == "1" ]]; then
    log "Code signing with: $DEVELOPER_ID"

    # Sign GRDB bundle first if present
    if [[ -d "$APP_DIR/Contents/Resources/GRDB_GRDB.bundle" ]]; then
        codesign --force --options runtime --timestamp \
            --sign "$DEVELOPER_ID" \
            "$APP_DIR/Contents/Resources/GRDB_GRDB.bundle"
    fi

    # Sign the main binary with entitlements
    codesign --force --options runtime --timestamp \
        --entitlements "$PKG_DIR/TokenLens.entitlements" \
        --sign "$DEVELOPER_ID" \
        "$APP_DIR"

    # Verify signature
    log "Verifying code signature..."
    codesign -dvvv "$APP_DIR"
    log "Code signing complete"
fi

# ── Create DMG ───────────────────────────────────────────────────────────────

if [[ "$DMG" == "1" ]]; then
    DMG_PATH="$BUILD_DIR/TokenLens-${VERSION}.dmg"
    DMG_TMP="$BUILD_DIR/dmg_tmp"

    log "Creating DMG: $DMG_PATH"

    rm -rf "$DMG_TMP" "$DMG_PATH"
    mkdir -p "$DMG_TMP"
    cp -R "$APP_DIR" "$DMG_TMP/"

    # Create a symlink to /Applications
    ln -s /Applications "$DMG_TMP/Applications"

    hdiutil create -volname "TokenLens" \
        -srcfolder "$DMG_TMP" \
        -ov -format UDZO \
        "$DMG_PATH"

    rm -rf "$DMG_TMP"

    # Sign DMG if signing is enabled
    if [[ "$SIGN" == "1" ]]; then
        codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG_PATH"
    fi

    log "DMG created: $DMG_PATH"
fi

# ── Notarization ─────────────────────────────────────────────────────────────

if [[ "$NOTARIZE" == "1" ]]; then
    DMG_PATH="${DMG_PATH:-$BUILD_DIR/TokenLens-${VERSION}.dmg}"
    if [[ ! -f "$DMG_PATH" ]]; then
        err "DMG not found at $DMG_PATH. Run with DMG=1 first or provide DMG_PATH."
    fi

    log "Submitting for notarization..."
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait

    log "Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"

    log "Notarization complete: $DMG_PATH"
fi

# ── Done ─────────────────────────────────────────────────────────────────────

log "=============================================="
log "Build complete!"
log "App:  $APP_DIR"
if [[ "$DMG" == "1" ]]; then
    log "DMG:  $DMG_PATH"
fi
log ""
log "To run the app locally:"
log "  open $APP_DIR"
log ""
log "To distribute unsigned (users must right-click → Open):"
log "  zip -r TokenLens.zip $APP_DIR"
log ""
log "For signed distribution:"
log "  SIGN=1 DMG=1 ./scripts/build-release.sh"
log "  # Requires DEVELOPER_ID in environment"
log "=============================================="
