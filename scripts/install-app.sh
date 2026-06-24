#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

scripts/build-app.sh

source_app=".build/MacCleaner.app"
destination_app="/Applications/Mac Cleaner.app"

ditto "$source_app" "$destination_app"
touch "$destination_app"

if [ -x /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister ]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$destination_app" >/dev/null 2>&1 || true
fi

echo "Installed $destination_app"
