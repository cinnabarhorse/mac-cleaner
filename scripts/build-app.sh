#!/usr/bin/env bash
set -euo pipefail

swift build -c release --product MacCleaner

binary_dir="$(swift build -c release --show-bin-path)"
app_dir=".build/MacCleaner.app"

mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources"
cp Packaging/Info.plist "$app_dir/Contents/Info.plist"
cp Packaging/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
cp "$binary_dir/MacCleaner" "$app_dir/Contents/MacOS/MacCleaner"
chmod +x "$app_dir/Contents/MacOS/MacCleaner"
codesign --force --deep --sign - "$app_dir" >/dev/null

echo "Built $app_dir"
