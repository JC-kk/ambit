# Contributing

## The one rule that matters

**Discovery mechanisms need evidence, not guesses.**

Every mechanism in this app was pinned down against a specific CLI version with a reproducible probe,
because guessing wrong here means silently editing someone's config in a way that does nothing — or
worse, something. Two examples of how that went:

- Codex skill roots were established by running `codex debug prompt-input` against a fixture `HOME`
  and reading which probe skills appeared. That is how `~/.agents/skills` was found.
- Codex subagents were first declared unsupported, wrongly, because `prompt-input` renders prompt
  items and not tools. `codex doctor` validates config at startup, and rejecting each field in turn
  produced the exact schema.

So if you change how something is discovered, the PR should say **which version** you tested and
**what you ran** to confirm it. "The docs say" is not enough; the docs have been behind the binaries
more than once.

## Layout

```
Sources/ACMCore/                 all logic — pure Foundation, no AppKit, no SwiftUI
Sources/AgentCapabilityManager/  the SwiftUI shell
Tests/ACMCoreTests/              fixture-based tests
scripts/make_icon.py             regenerates Resources/AppIcon.icns
```

`ACMCore` deliberately has no UI dependency. Put behaviour there, keep views thin, and the behaviour
stays testable.

## Running things

```bash
swift test --scratch-path /tmp/acm-build     # 52 tests, ~0.2s
./build.sh && open AgentCapabilityManager.app
```

`build.sh` and `swift test` stage outside the project directory on purpose: if the repo sits in an
iCloud-synced folder, the `com.apple.FinderInfo` xattr it adds makes `codesign` refuse the build.

## Tests

Every test runs inside a throwaway `HOME` (see `Tests/ACMCoreTests/Fixture.swift`). Nothing in the
suite may read or write a real `~/.claude`, `~/.codex` or `~/.agents` — if you need to try something
against your own setup, copy it into a fixture first.

A change to a safety rule needs a test that proves the *refusal*, not just the happy path. The
interesting assertions in this codebase are the ones checking that a file is still there.

## Design constraints worth knowing before you propose something

- **Installed and exposed are separate.** Turning something off must never remove a source.
- **Status is derived, never stored.** There is no enabled-state database, because it would drift
  from the filesystem. The one exception is `SourceLedger`, which records *names only* so a source
  that vanishes can be reported rather than silently dropped.
- **Deletions need proof of ownership.** If we cannot prove we created an entry, we do not remove it
  — we disable the switch and explain why in the tooltip.
- **Scope.** Inventory and exposure management for Skills, MCP and Subagents. No marketplace, no
  chat, no key management, no telemetry. A feature that is not needed for inventory or exposure is
  probably out of scope, and saying no early is cheaper than removing it later.

## Copy

Interface text is design material. Name things by what the person controls, keep to sentence case,
and make failure messages say what happened and what to do — never just that something went wrong.
When a switch is disabled, the tooltip owes the reader a reason.
