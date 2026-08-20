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

## Gatekeeper, without a developer account

Ambit ships **ad-hoc signed**. That is a real signature, so the binary is tamper-evident, but it is
not *notarised* — notarisation requires a paid Apple Developer account.

The practical consequence is one line for the user:

```bash
xattr -dr com.apple.quarantine /Applications/Ambit.app
```

Put that in every release's notes. It is the single most common support question for unsigned macOS
open-source apps, and burying it guarantees issues that say only "it won't open".

Two things worth being accurate about:

- **Control-click → Open no longer works.** Apple removed that bypass for unnotarised apps in
  macOS 15. The GUI route is System Settings → Privacy & Security → "Open Anyway".
- **Homebrew quarantines cask artifacts by default.** `brew install --cask` alone is not enough;
  users need `--no-quarantine`, or the `xattr` line afterwards.

`checksums.txt` is published with every release so the download can be verified independently.

### A free developer account does not help, and its certificate makes things worse

Worth stating plainly, because it looks like it should help. A free Apple Developer account issues
only an **Apple Development** certificate. Distribution needs a **Developer ID Application**
certificate, and that — like notarisation — requires the paid Apple Developer Program.

Signing a public build with the development certificate would be worse than ad-hoc on three counts:

1. Gatekeeper does not accept development certificates for distributed apps, so users are still
   blocked — with a more confusing message than the plain unsigned one.
2. Development certificates expire after a year. Copies already installed would start failing
   signature validation. An ad-hoc signature never expires.
3. It embeds the account's email address in the binary, visible to anyone who runs
   `codesign -dv Ambit.app`.

So: ad-hoc, plus the `xattr` line, until someone pays for a membership.

## Signing secrets (optional, only with a paid membership)

With these set the release workflow signs and notarises automatically and the `xattr` step goes away.
Without them it does nothing and the ad-hoc signature stands, which is the default.

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

`Casks/ambit.rb` is a cask template. To distribute through a tap:

1. Create a repo named `homebrew-tap`.
2. Copy the cask in as `Casks/ambit.rb`.
3. Update `version` and `sha256` from the release's `checksums.txt`.

Users then install with:

```bash
brew install --cask JC-kk/tap/ambit
```

Bumping the cask on every release can be automated later; doing it by hand for the first few
releases is fine and keeps the checksums honest.
