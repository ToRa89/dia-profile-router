#!/usr/bin/env bash
set -euo pipefail

# Always run from repo root, regardless of where the script is called from.
cd "$(dirname "$0")/.."

echo "==> Building release..."
swift build -c release

# Capture the binary directory once — avoids a second build invocation.
BIN_PATH="$(swift build -c release --show-bin-path)"

APP="build/Dia Profile Router.app"

echo "==> Assembling bundle: $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN_PATH/DiaProfileRouterApp" "$APP/Contents/MacOS/DiaProfileRouterApp"

# Codesign with a STABLE local self-signed identity if available, else fall back to ad-hoc.
# A stable identity keeps the code-signing "designated requirement" constant across rebuilds,
# so macOS Automation/Accessibility (TCC) grants PERSIST instead of resetting every build.
# Create the identity once (see docs/SIGNING.md). This is NOT a Developer-ID / App Store cert.
SIGN_IDENTITY="${DIAROUTER_SIGN_IDENTITY:-DiaRouter Local Signing}"
if security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
    echo "==> Codesigning with stable identity: $SIGN_IDENTITY"
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
else
    echo "==> Stable identity '$SIGN_IDENTITY' not found — ad-hoc signing (TCC grants will reset each build)."
    codesign --force --deep --sign - "$APP"
fi

# Register with LaunchServices so the app appears in the default-browser picker.
echo "==> Registering with LaunchServices..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

echo ""
echo "Done: $APP"
echo ""
echo "To install:"
echo "  cp -R \"$APP\" /Applications/"
echo "  open \"/Applications/Dia Profile Router.app\""
