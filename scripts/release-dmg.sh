#!/bin/zsh
# Build a Developer ID-signed, notarized DMG suitable for a GitHub Release.
#
# Required environment variables:
#   TRACKPAD_CLICKER_DEVELOPER_ID_APPLICATION
#   TRACKPAD_CLICKER_NOTARY_PROFILE
#
# Optional environment variables:
#   TRACKPAD_CLICKER_TEAM_ID       (only needed to override the Xcode project setting)
#   TRACKPAD_CLICKER_OUTPUT_DIR    (defaults to ./dist)

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
PROJECT_PATH="$ROOT_DIR/TapDeck.xcodeproj"
SCHEME="TapDeck (Direct)"
PRODUCT_NAME="TapDeck"
ASSET_BASENAME="TapDeck"
TEAM_ID="${TRACKPAD_CLICKER_TEAM_ID:-}"
DEVELOPER_ID_APPLICATION="${TRACKPAD_CLICKER_DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${TRACKPAD_CLICKER_NOTARY_PROFILE:-}"
OUTPUT_DIR="${TRACKPAD_CLICKER_OUTPUT_DIR:-$ROOT_DIR/dist}"
VERSION_OVERRIDE=""

usage() {
  cat <<'EOF'
Usage: scripts/release-dmg.sh [--version VERSION]

Archives the Release target, signs the app and DMG with a Developer ID
Application certificate, submits the DMG to Apple notary service, staples its
ticket, and writes the final DMG plus a SHA-256 checksum to dist/.

Required environment variables:
  TRACKPAD_CLICKER_DEVELOPER_ID_APPLICATION
      The Developer ID Application certificate subject from your Keychain.
  TRACKPAD_CLICKER_NOTARY_PROFILE
      A notarytool keychain profile created with `xcrun notarytool
      store-credentials`.

Options:
  --version VERSION  Override MARKETING_VERSION for this archive.
  -h, --help         Show this message.
EOF
}

die() {
  print -u2 -- "error: $*"
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

while (( $# > 0 )); do
  case "$1" in
    --version)
      (( $# >= 2 )) || die "--version requires a value"
      VERSION_OVERRIDE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1 (run with --help)"
      ;;
  esac
done

[[ -d "$PROJECT_PATH" ]] || die "Xcode project not found: $PROJECT_PATH"
[[ -n "$DEVELOPER_ID_APPLICATION" ]] || die \
  "Set TRACKPAD_CLICKER_DEVELOPER_ID_APPLICATION to a Developer ID Application certificate."
[[ -n "$NOTARY_PROFILE" ]] || die \
  "Set TRACKPAD_CLICKER_NOTARY_PROFILE to a notarytool keychain profile."

for tool in xcodebuild xcrun codesign security hdiutil ditto shasum; do
  require_command "$tool"
done
xcrun --find notarytool >/dev/null 2>&1 || die "Xcode notarytool is required."
xcrun --find stapler >/dev/null 2>&1 || die "Xcode stapler is required."

if ! security find-identity -v -p codesigning | /usr/bin/grep -F \
  -- "\"$DEVELOPER_ID_APPLICATION\"" >/dev/null; then
  die "Developer ID Application signing identity was not found: $DEVELOPER_ID_APPLICATION"
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tapdeck-release.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
ARCHIVE_PATH="$WORK_DIR/TapDeck.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/$PRODUCT_NAME.app"
DMG_STAGE="$WORK_DIR/dmg-root"

mkdir -p "$OUTPUT_DIR"

typeset -a version_build_setting
version_build_setting=()
if [[ -n "$VERSION_OVERRIDE" ]]; then
  version_build_setting=("MARKETING_VERSION=$VERSION_OVERRIDE")
fi

typeset -a team_build_setting
team_build_setting=()
if [[ -n "$TEAM_ID" ]]; then
  team_build_setting=("DEVELOPMENT_TEAM=$TEAM_ID")
fi

print "Archiving Release build…"
xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$WORK_DIR/DerivedData" \
  "CODE_SIGN_STYLE=Manual" \
  "CODE_SIGN_IDENTITY=$DEVELOPER_ID_APPLICATION" \
  "${team_build_setting[@]}" \
  "${version_build_setting[@]}"

[[ -d "$APP_PATH" ]] || die "Archive did not contain the expected app: $APP_PATH"

print "Verifying application signature…"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
[[ -n "$VERSION" ]] || die "Could not read the app version from the archive."
DMG_PATH="$OUTPUT_DIR/$ASSET_BASENAME-$VERSION.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"

# Build a conventional drag-to-Applications disk image. `ditto` preserves the
# bundle metadata and extended attributes that a plain recursive copy may lose.
mkdir -p "$DMG_STAGE"
ditto "$APP_PATH" "$DMG_STAGE/$PRODUCT_NAME.app"
ln -s /Applications "$DMG_STAGE/Applications"

print "Creating DMG…"
rm -f "$DMG_PATH" "$CHECKSUM_PATH"
hdiutil create \
  -volname "$PRODUCT_NAME" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

print "Signing DMG…"
codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

print "Submitting DMG to Apple notary service (this can take a few minutes)…"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

print "Stapling and validating notarization ticket…"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"

shasum -a 256 "$DMG_PATH" > "$CHECKSUM_PATH"

print ""
print "Release assets are ready:"
print "  $DMG_PATH"
print "  $CHECKSUM_PATH"
