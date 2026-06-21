# Mac Cleaner

Mac Cleaner is a native SwiftUI macOS utility for scanning user-accessible storage, finding large files and folders, classifying known app footprints, and moving selected items to Trash after confirmation.

## Build

```sh
swift build
```

## Test

```sh
swift test
```

## Run

```sh
swift run MacCleaner
```

For controlled UI testing, point the app at a disposable home directory:

```sh
MAC_CLEANER_HOME=/tmp/mac-cleaner-e2e-home swift run MacCleaner
```

## Package a local app bundle

```sh
scripts/build-app.sh
```

The generated bundle is placed at `.build/MacCleaner.app`.

## Install for Full Disk Access

For reliable macOS privacy permissions, install the app at a stable path before granting Full Disk Access:

```sh
scripts/install-app.sh
```

The installer builds and copies the app to `/Applications/Mac Cleaner.app`. Then open **System Settings > Privacy & Security > Full Disk Access**, enable **Mac Cleaner**, quit and reopen the app, and scan again.
