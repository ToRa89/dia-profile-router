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

# App icon: rendered from assets/logo.svg at build time (sips + iconutil ship with macOS), so the
# repo stays free of a generated binary that could drift from the source SVG. The icon shows up in
# the Dock while a chooser window is open — without it macOS draws the blank placeholder document.
echo "==> Rendering app icon from assets/logo.svg"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" "256 128x128@2x" \
            "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
    px="${spec%% *}"
    name="${spec##* }"
    sips -s format png -Z "$px" assets/logo.svg --out "$ICONSET/icon_$name.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

# Menu-bar icon: simplified monochrome variant of the same motif, rendered at 1x/2x. Loaded as a
# template image, so macOS tints it for light and dark menu bars.
echo "==> Rendering menu bar icon from assets/menubar-icon.svg"
sips -s format png -Z 18 assets/menubar-icon.svg --out "$APP/Contents/Resources/MenuBarIcon.png" >/dev/null
sips -s format png -Z 36 assets/menubar-icon.svg --out "$APP/Contents/Resources/MenuBarIcon@2x.png" >/dev/null

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
