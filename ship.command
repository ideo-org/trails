#!/bin/bash
# ───────────────────────────────────────────────────────────────────────────
#  Trails → TestFlight (LOCAL FALLBACK).
#  The canonical release path is the tag-driven GitHub workflow
#  (.github/workflows/testflight.yml): push a tag like v0.1.0.
#  This script exists for when CI is unavailable. It uses the same
#  build-number scheme as CI (git rev-list --count HEAD) so the two paths
#  can never collide, refuses to ship a dirty tree.
#
#  Auth: the signed-in Xcode account (team BBNKWP3S9G).
# ───────────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

ARCHIVE="/tmp/trails.xcarchive"
EXPORT="/tmp/trails_upload"
LOG="/tmp/trails_ship.log"

if [ -n "$(git status --porcelain)" ]; then
  echo "✗ Working tree is dirty. Commit or stash before shipping — releases must be reproducible."
  exit 1
fi

TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo 'v0.0.1')"
VERSION="${TAG#v}"
BUILD="$(git rev-list --count HEAD)"

# Extract DEVELOPMENT_TEAM dynamically from ios/Shared.xcconfig
TEAM_ID="$(grep 'DEVELOPMENT_TEAM =' ios/Shared.xcconfig | cut -d'=' -f2 | xargs || echo 'BBNKWP3S9G')"

echo "▶︎ (1/3) Resolving Swift packages..."
xcodebuild -resolvePackageDependencies \
  -project ios/Trails.xcodeproj \
  -scheme Trails

echo "▶︎ (2/3) Archiving v$VERSION (build $BUILD from $(git rev-parse --short HEAD))…  full log: $LOG"
rm -rf "$ARCHIVE"
xcodebuild -project ios/Trails.xcodeproj -scheme Trails \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" archive -allowProvisioningUpdates \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  CODE_SIGN_STYLE="Automatic" \
  CODE_SIGN_IDENTITY="Apple Development" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PROVISIONING_PROFILE_SPECIFIER="" 2>&1 | tee "$LOG" | tail -2

echo "▶︎ (3/3) Uploading to TestFlight…"
rm -rf "$EXPORT"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist ios/ExportOptions-upload.plist -allowProvisioningUpdates 2>&1 | tee -a "$LOG" | tail -3

echo ""
echo "✅ Uploaded build $BUILD. It shows up in App Store Connect → TestFlight"
echo "   after ~10 minutes of Apple processing."
