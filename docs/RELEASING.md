# Releasing Mac Cleaner

Mac Cleaner ships as a universal arm64/x86_64 app signed with Developer ID,
using hardened runtime and Apple notarization. App Sandbox is intentionally not
enabled; macOS privacy controls and Full Disk Access continue to govern which
locations the app can scan.

GitHub's macOS 14 image defaults to an older Xcode, so both workflows select
the image's Xcode 16.2 installation explicitly. The Swift package manifest uses
Swift tools 6.0 compatibility and does not depend on newer manifest APIs.

## Local release build

Install a valid `Developer ID Application` certificate and private key in the
login keychain, then run:

```sh
MAC_CLEANER_VERSION=1.0.0 \
MAC_CLEANER_BUILD_NUMBER=100 \
MAC_CLEANER_SIGNING_IDENTITY='Developer ID Application: Example (TEAMID)' \
scripts/build-release.sh
```

All three variables are required. The build fails before compilation when the
identity is missing, is ad-hoc, or does not resolve to a Developer ID
Application certificate. The output is `dist/MacCleaner.app`.

The build script compiles arm64 and x86_64 independently, merges them with
`lipo`, applies version metadata, enables hardened runtime, requests a secure
timestamp, and verifies the bundle and signature. It does not claim that an
unnotarized app passes Gatekeeper.

## Notarization

For local use, save credentials in the Keychain once:

```sh
xcrun notarytool store-credentials mac-cleaner-notary \
  --apple-id APPLE_ID \
  --team-id TEAM_ID \
  --password APP_SPECIFIC_PASSWORD
```

Then submit, staple, validate, and package the signed app:

```sh
MAC_CLEANER_NOTARY_PROFILE=mac-cleaner-notary \
scripts/notarize-release.sh
```

Automation can use an App Store Connect API key instead:

```sh
MAC_CLEANER_NOTARY_KEY=/secure/path/AuthKey_KEYID.p8 \
MAC_CLEANER_NOTARY_KEY_ID=KEYID \
MAC_CLEANER_NOTARY_ISSUER=ISSUER_UUID \
scripts/notarize-release.sh
```

After Apple accepts the submission, the script staples the ticket, validates it
with `stapler`, assesses the app with Gatekeeper, creates
`dist/MacCleaner-VERSION.zip`, and writes its SHA-256 checksum beside it.

## GitHub release secrets

Configure these repository secrets:

- `DEVELOPER_ID_APPLICATION_P12_BASE64`: base64-encoded Developer ID
  certificate and private key exported as a `.p12` file.
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`: password for that `.p12` file.
- `APPLE_API_KEY_P8_BASE64`: base64-encoded App Store Connect API private key.
- `APPLE_API_KEY_ID`: API key identifier.
- `APPLE_API_ISSUER_ID`: API issuer UUID.

The release workflow imports credentials into an ephemeral keychain and files
under the GitHub runner temporary directory. It removes them in an `always()`
cleanup step. Credentials are never written to the repository or release
artifact.

Push a strict semantic-version tag to create a release:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The workflow tests the app, builds and signs the universal bundle, notarizes and
staples it, then attaches the ZIP and checksum to the matching GitHub release.

## Manual verification

The verification script is safe to run independently:

```sh
scripts/verify-app.sh --require-developer-id dist/MacCleaner.app
scripts/verify-app.sh --require-notarized dist/MacCleaner.app
```

It checks the bundle identifier, minimum macOS version, arm64/x86_64 slices,
code signature, secure timestamp, hardened runtime, absence of App Sandbox,
stapled ticket, and Gatekeeper acceptance as appropriate.

Pull-request CI also launches the packaged executable with fresh, disposable
`MAC_CLEANER_HOME` and `MAC_CLEANER_DATA_DIR` directories. This prevents the
smoke test from reading a developer's saved scan report or scanning real user
data.
