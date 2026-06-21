#!/usr/bin/env bash
set -euo pipefail

swift build -c release --product MacCleaner

binary_dir="$(swift build -c release --show-bin-path)"
app_dir=".build/MacCleaner.app"

mkdir -p "$app_dir/Contents/MacOS"
cp Packaging/Info.plist "$app_dir/Contents/Info.plist"
cp "$binary_dir/MacCleaner" "$app_dir/Contents/MacOS/MacCleaner"
chmod +x "$app_dir/Contents/MacOS/MacCleaner"

echo "Built $app_dir"
