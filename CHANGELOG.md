# Changelog

All notable changes to this project are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## [2.0.0] — 2026-08-21

### Changed
- **Renamed from Ambit to Skillswitch.** The old name said nothing about what the app manages, which
  is the whole problem when the thing being managed is a directory of skills. The app, the bundle
  identifier (`dev.skillswitch.Skillswitch`), the cask and the `SKILLSWITCH_HOME` override all move
  with it.
- **New icon.** Three vertical ticks off the app's own patch row — clay for Claude, cyan for Codex,
  one switched off between them. Flat, because the interfaces it belongs to are flat; vertical,
  because three horizontal bars read as a hamburger menu at 16pt.
- **The library moved from `~/.agent-capabilities` to `~/.skillswitch`.** This is the breaking part.
  Every symlink and hard link in `~/.claude` and `~/.codex` points at absolute paths inside the
  library, Codex agent roles record an absolute `config_file`, and skill scripts are written against
  the library path by convention — so all of those need rewriting, not just the folder.

  **Upgrading by hand:** move the directory, then leave a symlink behind so nothing breaks while you
  work through the rest.

  ```bash
  mv ~/.agent-capabilities ~/.skillswitch
  ln -s ~/.skillswitch ~/.agent-capabilities
  ```

  Then open Skillswitch: exposures that still point through the old path read as ordinary rows, and
  switching one off and on again repoints it. Anything with the old path written *inside* it — Codex
  role files under `agents/codex`, and any skill whose SKILL.md references its own scripts — needs
  the string replaced. Leave copies under `backups/` alone; an edited backup is not a backup. Delete
  the compatibility symlink once nothing references it.

## [1.1.0] — 2026-08-20

### Added
- A **master switch in every column heading**: one click turns all skills, all MCP servers or all
  subagents on for one agent, and another turns them off. Reads the column back as all-on, all-off or
  mixed, obeys the filter that is showing, and leaves rows this app does not govern alone instead of
  counting them as off.
- The same switch appears in each section heading of the per-agent view, so "everything Claude can
  load" can be filled or emptied one kind at a time.

## [1.0.1] — 2026-08-20

### Fixed
- Turning a parked MCP server back on no longer reports it as a source deleted by something else.
  Parking is a move, so the library copy is *meant* to disappear on enable; presence is now judged
  across the parked directory, `~/.claude.json` and `config.toml` together. A server this app never
  parked is still not tracked at all.

## [1.0.0] — 2026-08-20

First release of **Skillswitch** — the scope of what each agent can reach.

### Added
- Capability × agent matrix for **Skills**, **MCP servers** and **Subagents** across Claude Code and
  OpenAI Codex, with an independent switch per agent.
- Per-agent view: everything one agent can load, grouped by kind, with a read-only note of what the
  other agent is doing.
- Menu bar item with a compact popover, plus the full desktop panel on demand.
- **Consolidate**: moves every remaining source into `~/.skillswitch` and links it back, so
  the switches become independent without changing what either agent can see.
- Five honest states — `ON`, `OFF`, `EXTERNAL`, `BROKEN`, `N/A` — all derived from the filesystem and
  the agents' own config files on every scan.
- Missing-source detection: if a library source is deleted by something else, the app says so
  instead of quietly dropping it from the list.
- `--print` and `--consolidate [--yes]` for scripting; `--panel` to open the desktop panel directly.
- `SKILLSWITCH_HOME` to point the whole app at a throwaway tree.

### Mechanisms
- Skills are exposed by per-skill symlink into `~/.claude/skills` and `~/.codex/skills`.
- Claude subagents use **hard links**, because Claude Code's agent scanner skips symlinked `.md`.
- Codex subagents are declared as `[agents.<name>]` in `config.toml` pointing at a role file; the
  Claude `.md` is converted when Codex is switched on.
- Claude MCP servers are parked verbatim in the library when off; Codex MCP servers use the native
  `enabled` key.

### Distribution
- Ad-hoc signed, not notarised: notarisation requires a paid Apple Developer Program membership.
  After installing — including via Homebrew, since the quarantine flag comes from the download
  rather than from brew — clear it with `xattr -dr com.apple.quarantine /Applications/Skillswitch.app`, or
  use **System Settings → Privacy & Security → Open Anyway**. A locally built copy needs neither.

### Safety
- Disabling never deletes a source.
- Removal requires proof of ownership: a symlink must resolve inside the library, a hard link must
  share the library file's inode and not be the last link to its data.
- JSON configs are edited as **text**, splicing one top-level key, so key order, indentation and
  float formatting are preserved byte for byte.
- TOML edits change a single key or table and leave comments, ordering and unknown keys intact.
- Every config write is backup → parse → minimal edit → validate → atomic rename.
