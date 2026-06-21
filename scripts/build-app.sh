#!/usr/bin/env bash
set -euo pipefail

swift build -c release --product MacCleaner

binary_dir="$(swift build -c release --show-bin-path)"
app_dir=".build/MacCleaner.app"
app_path="$PWD/$app_dir"

mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources"
cp Packaging/Info.plist "$app_dir/Contents/Info.plist"
cp Packaging/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
cp "$binary_dir/MacCleaner" "$app_dir/Contents/MacOS/MacCleaner"
chmod +x "$app_dir/Contents/MacOS/MacCleaner"

signing_identity="${MAC_CLEANER_CODESIGN_IDENTITY:-}"

if [ -z "$signing_identity" ] && command -v security >/dev/null 2>&1; then
    identity_list="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    signing_identity="$(printf "%s\n" "$identity_list" | awk -F '"' '/"Apple Development:/{ print $2; exit }')"

    if [ -z "$signing_identity" ]; then
        signing_identity="$(printf "%s\n" "$identity_list" | awk -F '"' '/"/{ print $2; exit }')"
    fi
fi

if [ -z "$signing_identity" ]; then
    signing_identity="-"
fi

codesign --force --deep --sign "$signing_identity" "$app_dir" >/dev/null
touch "$app_dir"

if [ -x /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister ]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_path" >/dev/null 2>&1 || true
fi

if [ "$signing_identity" = "-" ]; then
    echo "Built $app_dir with ad-hoc signing"
else
    echo "Built $app_dir signed as $signing_identity"
fi
