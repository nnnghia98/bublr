#!/usr/bin/env bash
#
# Build, sign, package and (optionally) notarise a Bublr release.
#
# The unsigned path is the default and needs nothing but Xcode: it produces a DMG you can hand to someone who
# is willing to right-click → Open once. Everything that needs an Apple Developer account is opt-in through
# environment variables, so this script never claims to have notarised something it did not.
#
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)"   codesign the app and the DMG
#   NOTARY_PROFILE="bublr-notary"                            notarytool keychain profile
#       or AC_USERNAME + AC_PASSWORD (+ AC_TEAM_ID)           Apple ID + app-specific password
#
#   ./Tools/release.sh              build + DMG + checksum + cask, unsigned
#   ./Tools/release.sh --publish    ...and create/update the GitHub release for the tag
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Bublr"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Support/Info.plist)
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
APP=".build/Build/Products/Release/${APP_NAME}.app"
DIST="dist"
DMG="${DIST}/${APP_NAME}-${VERSION}.dmg"
TAG="v${VERSION}"
PUBLISH=0

for arg in "$@"; do
    case "$arg" in
        --publish) PUBLISH=1 ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

step() { printf '\n\033[1m→ %s\033[0m\n' "$*"; }

step "Building ${APP_NAME} ${VERSION} (${BUILD}) from ${COMMIT}${DIRTY:+ (+${DIRTY} uncommitted)}"
if [[ "$DIRTY" != "0" ]]; then
    echo "  warning: the working tree is dirty; the binary will carry ${COMMIT} plus local changes" >&2
fi
make build CONFIG=Release >/dev/null
[[ -d "$APP" ]] || { echo "missing ${APP}" >&2; exit 1; }

step "Verifying the build"
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist" | grep -qx "$VERSION" \
    || { echo "version in the bundle does not match ${VERSION}" >&2; exit 1; }

step "Code signing"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
    echo "  signed with ${DEVELOPER_ID}"
else
    echo "  no DEVELOPER_ID set — keeping the ad-hoc signature."
    echo "  A downloaded copy will need right-click → Open (or: xattr -d com.apple.quarantine)."
fi

step "Packaging ${DMG}"
mkdir -p "$DIST"
rm -f "$DMG"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/${APP_NAME}.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "${APP_NAME} ${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
    codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
fi

step "Mounting the DMG to check it"
MOUNT=$(hdiutil attach -nobrowse -readonly "$DMG" | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)
[[ -x "${MOUNT}/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" ]] \
    || { echo "the DMG does not contain a runnable ${APP_NAME}.app" >&2; hdiutil detach "$MOUNT" -quiet; exit 1; }
hdiutil detach "$MOUNT" -quiet
echo "  mounts cleanly and contains ${APP_NAME}.app"

CHECKSUM=$(shasum -a 256 "$DMG" | awk '{print $1}')

step "Notarising"
NOTARISED=0
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    NOTARISED=1
elif [[ -n "${AC_USERNAME:-}" && -n "${AC_PASSWORD:-}" ]]; then
    xcrun notarytool submit "$DMG" --apple-id "$AC_USERNAME" --password "$AC_PASSWORD" \
        ${AC_TEAM_ID:+--team-id "$AC_TEAM_ID"} --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    NOTARISED=1
else
    echo "  skipped: set NOTARY_PROFILE (xcrun notarytool store-credentials) or AC_USERNAME/AC_PASSWORD."
    echo "  The DMG is unsigned-for-distribution: Gatekeeper will ask for a right-click on first launch."
fi

step "Writing checksums and the Homebrew cask"
printf '%s  %s\n' "$CHECKSUM" "$(basename "$DMG")" > "${DIST}/SHA256SUMS"
cat > "${DIST}/bublr.rb" <<CASK
cask "bublr" do
  version "${VERSION}"
  sha256 "${CHECKSUM}"

  url "https://github.com/nnnghia98/bublr/releases/download/v#{version}/${APP_NAME}-#{version}.dmg"
  name "Bublr"
  desc "Chat heads for macOS — one always-on-top bubble per chat provider"
  homepage "https://github.com/nnnghia98/bublr"

  app "${APP_NAME}.app"
CASK

# Tell `brew` users the same thing the release notes do, instead of letting them meet Gatekeeper alone.
if [[ "$NOTARISED" == "0" ]]; then
    cat >> "${DIST}/bublr.rb" <<'CASK'

  caveats <<~EOS
    This build is not notarised. The first launch needs right-click → Open, or:
      xattr -d com.apple.quarantine "#{appdir}/Bublr.app"
  EOS
CASK
fi
cat >> "${DIST}/bublr.rb" <<'CASK'
end
CASK
echo "  dist/SHA256SUMS"
echo "  dist/bublr.rb   (copy into a homebrew-bublr tap: Casks/bublr.rb)"

if [[ "$PUBLISH" == "1" ]]; then
    step "Publishing ${TAG}"
    command -v gh >/dev/null || { echo "gh is not installed" >&2; exit 1; }
    gh release view "$TAG" >/dev/null 2>&1 \
        && gh release upload "$TAG" "$DMG" "${DIST}/SHA256SUMS" "${DIST}/bublr.rb" --clobber \
        || gh release create "$TAG" "$DMG" "${DIST}/SHA256SUMS" "${DIST}/bublr.rb" \
             --title "${APP_NAME} ${VERSION}" --generate-notes
fi

step "Done"
printf '  %s\n  sha256 %s\n' "$DMG" "$CHECKSUM"
