# Releasing a GitHub DMG

`scripts/release-dmg.sh` creates the public release artifact. It archives the
Release target, signs the app and disk image using a Developer ID Application
certificate, submits the DMG for notarization, staples the ticket, and writes a
SHA-256 checksum alongside the DMG.

No signing identity, team identifier, Apple ID, app-specific password, or API
key is stored in this repository. Keep those values in your shell environment,
CI secret store, and Keychain.

## One-time notarization setup

Create a local `notarytool` Keychain profile. The command prompts
interactively when credential options are not supplied:

```zsh
xcrun notarytool store-credentials "tapdeck-notary"
```

An App Store Connect API key is also supported by `notarytool` if preferred.

## Create a release

Find the Developer ID Application identity in the Keychain, then set it only
for the current shell session:

```zsh
security find-identity -v -p codesigning
export TAPDECK_DEVELOPER_ID_APPLICATION='Developer ID Application: …'
export TAPDECK_NOTARY_PROFILE='tapdeck-notary'
scripts/release-dmg.sh --version 0.3.3
```

The version flag is optional and otherwise uses the Release target's
`MARKETING_VERSION`. The script creates these GitHub Release assets:

```
dist/TapDeck-<version>.dmg
dist/TapDeck-<version>.dmg.sha256
```

If the Xcode project needs a different signing team from its checked-in build
setting, set `TAPDECK_TEAM_ID` in the execution environment. Do not
commit that value. Set `TAPDECK_OUTPUT_DIR` to override the default `dist/` output directory.

For a development build, use the Xcode build command in [README.md](README.md#build-and-run).
Debug builds use Apple Development signing and are not suitable for public distribution.
