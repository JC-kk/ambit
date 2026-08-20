# Releasing

## Cutting a release

1. Update `CHANGELOG.md` and the version in `build.sh` (`CFBundleShortVersionString`).
2. Tag and push:

```bash
git tag -a v1.0.0 -m "v1.0.0" && git push origin v1.0.0
```

`.github/workflows/release.yml` runs the tests, builds the bundle, signs and notarizes it if the
secrets below exist, packages a `.dmg` and a `.zip` with checksums, and opens a **draft** release.
Review it, then publish.

## Signing secrets (optional)

Without these the app is ad-hoc signed and first launch needs right-click → Open. To ship something
that opens on a double click you need an Apple Developer account and these repository secrets:

| Secret | What it is |
|---|---|
| `MACOS_CERTIFICATE` | base64 of a "Developer ID Application" `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | that `.p12`'s password |
| `MACOS_SIGNING_IDENTITY` | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `NOTARY_APPLE_ID` | the Apple ID used for notarization |
| `NOTARY_TEAM_ID` | your 10-character team ID |
| `NOTARY_PASSWORD` | an app-specific password, not your Apple ID password |

Export the certificate with:

```bash
base64 -i DeveloperID.p12 | pbcopy
```

## Homebrew

`Casks/agent-capabilities.rb` is a cask template. To distribute through a tap:

1. Create a repo named `homebrew-tap`.
2. Copy the cask in as `Casks/agent-capabilities.rb`.
3. Update `version` and `sha256` from the release's `checksums.txt`.

Users then install with:

```bash
brew install --cask <your-github-user>/tap/agent-capabilities
```

Bumping the cask on every release can be automated later; doing it by hand for the first few
releases is fine and keeps the checksums honest.
