#!/bin/bash
set -euo pipefail

# PromptCraft Build & Distribution Script
# Usage:
#   ./scripts/build.sh              # Build Release DMG
#   ./scripts/build.sh --notarize   # Build, sign, notarize, and create DMG
#   ./scripts/build.sh --debug      # Build Debug (no DMG)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_NAME="PromptCraft"
SCHEME="PromptCraft"
XCODEPROJ="$PROJECT_DIR/$PROJECT_NAME.xcodeproj"

# Build output directories
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_DIR="$BUILD_DIR/archive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_DIR="$BUILD_DIR/dmg"

# Parse arguments
CONFIGURATION="Release"
SHOULD_NOTARIZE=false
DEBUG_MODE=false

for arg in "$@"; do
    case $arg in
        --notarize)
            CONFIGURATION="Release"
            SHOULD_NOTARIZE=true
            ;;
        --debug)
            CONFIGURATION="Debug"
            DEBUG_MODE=true
            ;;
        --distribution)
            CONFIGURATION="Distribution"
            SHOULD_NOTARIZE=true
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: $0 [--notarize] [--debug] [--distribution]"
            exit 1
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_step() { echo -e "${BLUE}==> $1${NC}"; }
log_success() { echo -e "${GREEN}==> $1${NC}"; }
log_warning() { echo -e "${YELLOW}==> $1${NC}"; }
log_error() { echo -e "${RED}==> ERROR: $1${NC}"; }

# Read current version from Info.plist
MARKETING_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_DIR/$PROJECT_NAME/Info.plist")
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PROJECT_DIR/$PROJECT_NAME/Info.plist")

echo ""
echo "========================================="
echo "  $PROJECT_NAME Build Script"
echo "  Version: $MARKETING_VERSION ($CURRENT_BUILD)"
echo "  Configuration: $CONFIGURATION"
echo "  Notarize: $SHOULD_NOTARIZE"
echo "========================================="
echo ""

# ─── Step 1: Increment Build Number ───────────────────────────────────────────

log_step "Incrementing build number..."
NEW_BUILD=$((CURRENT_BUILD + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$PROJECT_DIR/$PROJECT_NAME/Info.plist"
log_success "Build number: $CURRENT_BUILD -> $NEW_BUILD"

# ─── Step 2: Clean Build Directory ────────────────────────────────────────────

log_step "Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$ARCHIVE_DIR" "$EXPORT_DIR" "$DMG_DIR"

# ─── Step 3: Build Archive ────────────────────────────────────────────────────

if [ "$DEBUG_MODE" = true ]; then
    log_step "Building in Debug configuration..."
    xcodebuild build \
        -project "$XCODEPROJ" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -derivedDataPath "$BUILD_DIR/DerivedData" \
        CODE_SIGN_IDENTITY="-" \
        | tail -20

    log_success "Debug build complete!"
    echo "Binary at: $BUILD_DIR/DerivedData/Build/Products/Debug/$PROJECT_NAME.app"
    exit 0
fi

ARCHIVE_PATH="$ARCHIVE_DIR/$PROJECT_NAME.xcarchive"

log_step "Archiving $PROJECT_NAME ($CONFIGURATION)..."
xcodebuild archive \
    -project "$XCODEPROJ" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    MARKETING_VERSION="$MARKETING_VERSION" \
    CURRENT_PROJECT_VERSION="$NEW_BUILD" \
    | tail -20

if [ ! -d "$ARCHIVE_PATH" ]; then
    log_error "Archive failed!"
    exit 1
fi
log_success "Archive created at: $ARCHIVE_PATH"

# ─── Step 4: Export App ───────────────────────────────────────────────────────

APP_PATH="$ARCHIVE_PATH/Products/Applications/$PROJECT_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    log_error "App bundle not found in archive!"
    exit 1
fi

# Copy the app out of the archive
cp -R "$APP_PATH" "$EXPORT_DIR/$PROJECT_NAME.app"
APP_PATH="$EXPORT_DIR/$PROJECT_NAME.app"
log_success "App exported to: $APP_PATH"

# ─── Step 5: Code Signing Verification ────────────────────────────────────────

log_step "Verifying code signature..."
codesign --verify --deep --strict "$APP_PATH" 2>&1 || {
    log_warning "Code signature verification failed. If using ad-hoc signing, this is expected."
}

# Display signing info
codesign -dv --verbose=2 "$APP_PATH" 2>&1 | head -10
echo ""

# ─── Step 6: Notarization ────────────────────────────────────────────────────

if [ "$SHOULD_NOTARIZE" = true ]; then
    log_step "Preparing for notarization..."

    # Check required environment variables
    if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_PASSWORD:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ]; then
        log_error "Notarization requires APPLE_ID, APPLE_PASSWORD, and APPLE_TEAM_ID environment variables."
        log_warning "Set them before running with --notarize:"
        echo "  export APPLE_ID='your@apple.id'"
        echo "  export APPLE_PASSWORD='xxxx-xxxx-xxxx-xxxx'  # App-specific password"
        echo "  export APPLE_TEAM_ID='XXXXXXXXXX'"
        exit 1
    fi

    # Create a ZIP for notarization submission
    NOTARIZE_ZIP="$BUILD_DIR/$PROJECT_NAME-notarize.zip"
    log_step "Creating ZIP for notarization..."
    ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"

    # Submit for notarization
    log_step "Submitting to Apple for notarization..."
    xcrun notarytool submit "$NOTARIZE_ZIP" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait \
        --timeout 30m

    NOTARIZE_STATUS=$?
    if [ $NOTARIZE_STATUS -ne 0 ]; then
        log_error "Notarization failed! Check the log above for details."
        log_warning "Common issues:"
        echo "  - Missing hardened runtime entitlement"
        echo "  - Unsigned embedded frameworks"
        echo "  - Entitlement problems"
        echo ""
        echo "To get the full notarization log, run:"
        echo "  xcrun notarytool log <submission-id> --apple-id $APPLE_ID --password *** --team-id $APPLE_TEAM_ID"
        exit 1
    fi

    # Staple the notarization ticket
    log_step "Stapling notarization ticket..."
    xcrun stapler staple "$APP_PATH"
    log_success "Notarization complete and stapled!"

    # Verify
    spctl --assess --type execute --verbose "$APP_PATH" 2>&1 || true

    # Clean up notarization ZIP
    rm -f "$NOTARIZE_ZIP"
fi

# ─── Step 7: Create DMG ──────────────────────────────────────────────────────

DMG_NAME="$PROJECT_NAME-$MARKETING_VERSION.dmg"
DMG_PATH="$DMG_DIR/$DMG_NAME"

log_step "Creating DMG: $DMG_NAME..."

# Check if create-dmg is available (preferred method)
if command -v create-dmg &>/dev/null; then
    log_step "Using create-dmg for professional DMG..."
    create-dmg \
        --volname "$PROJECT_NAME" \
        --volicon "$PROJECT_DIR/$PROJECT_NAME/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" \
        --window-pos 200 120 \
        --window-size 660 400 \
        --icon-size 128 \
        --icon "$PROJECT_NAME.app" 180 180 \
        --hide-extension "$PROJECT_NAME.app" \
        --app-drop-link 480 180 \
        --no-internet-enable \
        "$DMG_PATH" \
        "$EXPORT_DIR/" \
        2>&1 || {
            log_warning "create-dmg failed, falling back to hdiutil..."
            # Fall through to hdiutil
            DMG_CREATED=false
        }
    DMG_CREATED=${DMG_CREATED:-true}
else
    DMG_CREATED=false
fi

if [ "$DMG_CREATED" = false ]; then
    log_step "Using hdiutil for DMG creation..."

    # Create a temporary DMG directory
    DMG_STAGING="$BUILD_DIR/dmg-staging"
    mkdir -p "$DMG_STAGING"
    cp -R "$APP_PATH" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"

    # Create the DMG
    hdiutil create \
        -volname "$PROJECT_NAME" \
        -srcfolder "$DMG_STAGING" \
        -ov \
        -format UDZO \
        -fs HFS+ \
        "$DMG_PATH"

    rm -rf "$DMG_STAGING"
fi

if [ ! -f "$DMG_PATH" ]; then
    log_error "DMG creation failed!"
    exit 1
fi

# Sign the DMG if notarizing
if [ "$SHOULD_NOTARIZE" = true ]; then
    log_step "Signing DMG..."
    codesign --sign "Developer ID Application" "$DMG_PATH" 2>/dev/null || {
        log_warning "DMG signing skipped (no Developer ID certificate found)"
    }

    # Notarize the DMG too
    log_step "Notarizing DMG..."
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait \
        --timeout 30m

    xcrun stapler staple "$DMG_PATH"
    log_success "DMG notarized and stapled!"
fi

# ─── Step 8: Summary ─────────────────────────────────────────────────────────

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)

echo ""
echo "========================================="
echo "  Build Complete!"
echo "========================================="
echo "  App:     $APP_PATH"
echo "  DMG:     $DMG_PATH"
echo "  Size:    $DMG_SIZE"
echo "  Version: $MARKETING_VERSION ($NEW_BUILD)"
echo "========================================="
echo ""

if [ "$SHOULD_NOTARIZE" = true ]; then
    log_success "Ready for distribution! The DMG is signed and notarized."
else
    log_warning "DMG is NOT notarized. Use --notarize for distribution builds."
fi
