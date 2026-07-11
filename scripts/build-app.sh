#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

swift build -c release --product MacCleaner

binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$repo_root/.build/MacCleaner.app"

mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources"
/usr/bin/ditto "$repo_root/Packaging/Info.plist" "$app_dir/Contents/Info.plist"
/usr/bin/ditto "$repo_root/Packaging/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
/usr/bin/ditto "$binary_dir/MacCleaner" "$app_dir/Contents/MacOS/MacCleaner"
chmod +x "$app_dir/Contents/MacOS/MacCleaner"
/usr/bin/codesign --force --sign - "$app_dir" >/dev/null
/usr/bin/codesign --verify --deep --strict "$app_dir"
touch "$app_dir"

if [ -x /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister ]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_dir" >/dev/null 2>&1 || true
fi

echo "Built $app_dir (ad-hoc signed for local use)"
