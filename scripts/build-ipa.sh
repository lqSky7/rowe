#!/usr/bin/env bash
# build-ipa.sh — generate RoweIOS.xcodeproj via XcodeGen and package an unsigned .ipa.
#
#   ./scripts/build-ipa.sh                 # Debug
#   ./scripts/build-ipa.sh release         # Release
#
# Output: Rowe-<version>-unsigned.ipa in the repository root.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS_DIR="$REPO_ROOT/RoweApp/RoweIOS"
cd "$IOS_DIR"

CONFIG=Debug
for argument in "$@"; do
  case "$argument" in
    debug|Debug) CONFIG=Debug ;;
    release|Release) CONFIG=Release ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "build-ipa: unknown argument '$argument'" >&2
      exit 2
      ;;
  esac
done

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "build-ipa: xcodegen is required (brew install xcodegen)" >&2
  exit 1
fi

echo "==> Generating RoweIOS.xcodeproj from RoweApp/RoweIOS/project.yml"
xcodegen generate --spec project.yml

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist)
OUTPUT="$REPO_ROOT/Rowe-${VERSION}-unsigned.ipa"

echo "==> Rowe iOS ${VERSION} (${BUILD}), ${CONFIG}"

PRODUCTS_DIR=$(
  xcodebuild -project RoweIOS.xcodeproj -scheme RoweIOS \
    -configuration "$CONFIG" -sdk iphoneos \
    -showBuildSettings 2>/dev/null \
  | sed -n 's/^ *BUILT_PRODUCTS_DIR = //p' | head -1
)
if [[ -z "$PRODUCTS_DIR" ]]; then
  echo "build-ipa: could not read BUILT_PRODUCTS_DIR" >&2
  exit 1
fi

echo "==> Building RoweIOS"
xcodebuild -project RoweIOS.xcodeproj -scheme RoweIOS \
  -configuration "$CONFIG" -sdk iphoneos -destination 'generic/platform=iOS' \
  ENABLE_DEBUG_DYLIB=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

APP="$PRODUCTS_DIR/RoweIOS.app"
if [[ ! -d "$APP" ]]; then
  APP="$PRODUCTS_DIR/Rowe.app"
fi
if [[ ! -d "$APP" ]]; then
  echo "build-ipa: no .app bundle found in $PRODUCTS_DIR" >&2
  exit 1
fi

APP_NAME="$(basename "$APP")"
EXEC_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP/Info.plist")

echo "==> Packaging $OUTPUT"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/rowe-ipa.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT INT TERM
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/$APP_NAME"

rm -f "$OUTPUT"
(cd "$STAGE" && zip -qry "$OUTPUT" Payload)

for required in "Payload/$APP_NAME/$EXEC_NAME" "Payload/$APP_NAME/Info.plist"; do
  if ! unzip -l "$OUTPUT" | awk -v path="$required" 'index($0, path) { found = 1 } END { exit !found }'; then
    echo "build-ipa: $OUTPUT is missing $required" >&2
    exit 1
  fi
done

echo "==> Built $OUTPUT ($(du -h "$OUTPUT" | cut -f1 | tr -d ' '))"
