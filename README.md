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
MAC_CLEANER_HOME=/tmp/mac-cleaner-e2e-home \
MAC_CLEANER_DATA_DIR=/tmp/mac-cleaner-e2e-data \
swift run MacCleaner
```

## Package a local app bundle

```sh
scripts/build-app.sh
```

The generated bundle is placed at `.build/MacCleaner.app`.

## Build a universal test bundle

```sh
scripts/build-universal-app.sh
```

This builds separate arm64 and x86_64 executables, combines them into
`.build/universal/MacCleaner.app`, and applies an ad-hoc signature. It is for
testing only; distributed builds require Developer ID signing and notarization.

## Release

Release builds use the production bundle identifier
`com.cinnabarhorse.MacCleaner`. Existing development installs that used the
old identifier may need Full Disk Access granted again.

The signed release and notarization commands are:

```sh
MAC_CLEANER_VERSION=1.0.0 \
MAC_CLEANER_BUILD_NUMBER=100 \
MAC_CLEANER_SIGNING_IDENTITY='Developer ID Application: Example (TEAMID)' \
scripts/build-release.sh

MAC_CLEANER_NOTARY_PROFILE=mac-cleaner-notary \
scripts/notarize-release.sh
```

The final ZIP and SHA-256 checksum are written to `dist/`. See
[`docs/RELEASING.md`](docs/RELEASING.md) for credential setup, CI secrets, and
the complete validation flow.
