# Agent Capability Manager — Design Note

A local macOS control panel for the **exposure** of Skills, MCP servers and Subagents
to **Claude Code** and **OpenAI Codex**. Not a marketplace, not an agent app.

## 0. Stack decision: native SwiftUI (not Tauri 2)

Checked the machine first:

| | status |
|---|---|
| Rust / cargo | **not installed** (Tauri 2 needs a full rustup toolchain + long first build) |
| Xcode 27 / Swift 6.4 | **installed** |
| Node 22 | installed |

The whole product is local filesystem + config editing with a small matrix UI. There is no
web surface, no server, no cross-platform requirement. SwiftUI gives instant cold start, a
single ~1 MB binary, zero third-party dependencies, and native Finder/AppKit integration.
Tauri would add a ~1.5 GB toolchain install and a webview for no benefit here.

Layout: SPM package, two targets.
* `SkillswitchCore` — all scanning / status / mutation logic. No AppKit. Fully unit-testable against
  temp fixture directories.
* `Skillswitch` — SwiftUI shell.

No SQLite, no state manager, no persisted "enabled" database. Status is always re-derived
from the filesystem and the agents' own config files.

## 1. Field research (verified on this machine, 2026-08-20)

Versions: Claude Code `2.1.234`, Codex CLI `0.147.0`.

### Codex skill discovery — measured, not guessed

Probe: fixture `HOME` + `CODEX_HOME`, then `codex debug prompt-input` (offline, deterministic,
renders the model-visible prompt, which contains `<skills_instructions>`).

Result — Codex 0.147 scans **all** of:

```
$CODEX_HOME/skills/          <- ~/.codex/skills
~/.agents/skills/            <- CONFIRMED, this is the trap
<cwd>/.codex/skills/
<cwd>/.agents/skills/
```

and **symlinked skill directories are discovered normally**.

> This validates the brief's warning. `~/.agents/skills` **must not** be the central store —
> anything placed there is unconditionally ON for Codex.

### Claude Code skill discovery

`~/.claude/skills/<name>/SKILL.md`. The loader lists directory entry *names* and then reads
`<name>/SKILL.md`; it does **not** filter on `isDirectory()`/`isSymbolicLink()`, so per-skill
symlinks work. Claude also has two native, non-destructive per-skill switches in `settings.json`:

* `skillOverrides: { "<name>": "off" | "name-only" | "user-invocable-only" }` — `"off"` hides the
  skill from both the model and `/name`. Works for **any** skill regardless of source.
* `enabledPlugins: { "<name>@skills-dir": false }` — the `/skills` UI's own toggle for
  `~/.claude/skills` entries.

### Claude Code subagent discovery — the symlink gotcha

`~/.claude/agents/*.md` with YAML frontmatter. The directory walker used by default does:

```js
for (const g of entries) { if (g.isSymbolicLink()) continue; ... }
```

**Symlinked `.md` files are skipped.** So subagents cannot use the skill mechanism.
We use **hard links** instead: a hard link is a regular file at `readdir`/`lstat` level, so it is
always discovered, it shares an inode with the library file (edit one = edit both, single source
of truth), and unlinking the exposure never touches the library copy.

Hard links also give the strongest possible *ownership proof*: an exposed file is ours iff its
`(st_dev, st_ino)` matches a file in the central library. No name matching, no manifest.

### Codex subagents — supported, via config.toml agent roles

Codex 0.147 *does* have custom subagents. The first pass got this wrong because it used
`codex debug prompt-input` as the observable, and that renders prompt input items, not tools — an
agent role never appears there. `codex doctor` validates config at startup and is the right probe.

The schema, confirmed by making `codex doctor` reject each mistake in turn:

```toml
# ~/.codex/config.toml
[agents.<name>]
description = "..."
config_file = "/abs/path/to/role.toml"   # must point at an existing file
nickname_candidates = ["Rex"]            # optional
```

```toml
# the role file
name = "seo-technical"                   # required, non-empty
description = "..."                      # required
developer_instructions = '''...'''       # required, non-blank
```

Getting any of it wrong yields `Ignoring malformed agent role definition: …` and a `⚠ config` row;
getting it right yields `✓ config loaded`. That is how the app's generated roles are verified.

Because Claude wants frontmatter plus a prompt body and Codex wants three TOML keys, a subagent
enabled for both has **one file per agent**. Enabling Codex for a Claude-only subagent converts it:
frontmatter `description` → `description`, the markdown body → `developer_instructions`.

Exposure for Codex is therefore a config edit, not a link. Disabling lifts the whole
`[agents.<name>]` table out and parks the exact text under `agents/codex/parked/`, so re-enabling
restores it byte-for-byte — including keys we never modelled.

### MCP### MCP

* **Codex** — `~/.codex/config.toml`, `[mcp_servers.<name>]`, native `enabled = false` key
  (already used by the `computer-use` entry on this machine). Disable = set that one key.
* **Claude** — user-scope servers live in `~/.claude.json` under `mcpServers`. The
  `disabledMcpServers` setting found in the binary is keyed **per project**
  (`~/.claude.json → projects[cwd]`), so it cannot express a global off.
  Global off is therefore done by **parking**: the server's JSON object is moved verbatim
  into `~/.skillswitch/mcp/parked/claude/<name>.json` and moved back on enable.

### JSON must be edited as text, not re-serialised

`~/.claude.json` is 55 KB of machine-written JSON. Parsing it to `[String: Any]`, changing one key
and re-serialising is *not* a minimal edit: Foundation reorders every key, and its number writer
does not round-trip doubles — this file contains `0.06962500000008731`, which comes back as
`0.069625000000087311`. An early build's round-trip guard caught exactly that and refused every
write, which was the right call for the wrong reason.

`JSONTextEditor` therefore splices the document as text: it locates the byte range of one top-level
key's value and replaces just that. Every other byte — ordering, indentation, float spelling — is
untouched by construction, and the result is re-parsed and diffed against the original before it is
written.

## 2. Central library## 2. Central library

```
~/.skillswitch/
├── skills/<name>/SKILL.md          # directories — exposed by symlink
├── agents/
│   ├── claude/<name>.md            # exposed by hard link
│   ├── codex/<name>.toml           # Codex agent role file
│   └── codex/parked/<name>.toml    # parked [agents.*] tables
├── mcp/parked/claude/<name>.json   # parked Claude server definitions
└── backups/<ISO8601>/…             # pre-write copies of every config touched
```

Deliberately *not* under `~/.agents`, `~/.claude` or `~/.codex`: no agent scans it, so a
capability that exists in the library but is exposed nowhere is genuinely OFF everywhere.

## 3. Exposure matrix

| kind | Claude Code | Codex |
|---|---|---|
| Skill | symlink `~/.claude/skills/<n>` → library; for **external** skills the non-destructive `skillOverrides[<n>] = "off"` | symlink `~/.codex/skills/<n>` → library |
| Subagent | **hard link** `~/.claude/agents/<n>.md` ↔ library | `[agents.<n>]` in `config.toml` → library role file |
| MCP | park / unpark in `~/.claude.json` `mcpServers` | `enabled` key in `[mcp_servers.<n>]` |

## 4. Status model

```
ON           discoverable by that agent right now
OFF          not discoverable
EXTERNAL     discoverable, but the on-disk entry is not managed by this app
BROKEN       entry exists but is unusable (dangling symlink, missing SKILL.md, unparseable)
UNSUPPORTED  the agent has no discovery mechanism for this kind (nothing reports this today)
```

Status is derived on every scan from `lstat`/`realpath`/config parse. Nothing is cached to disk.

### Forced-on detection

`~/.claude/skills` is a symlink to `~/.agents/skills` on this machine, and `~/.agents/skills` is a
Codex root. Any skill there is therefore **forced ON for Codex** and its Codex cell reports
`EXTERNAL` with an explanation rather than pretending a toggle would work. The app reports the
conflict; it does not silently re-point the user's real directories.

## 5. Safety rules (enforced in `SkillswitchCore`, not just the UI)

* Disabling **never** deletes a source. The library is only written by `Adopt`.
* An exposure entry is removed only if ownership is proven:
  * symlink → is a symlink **and** resolves inside `~/.skillswitch/skills`
  * hard link → `(st_dev, st_ino)` matches the library file
* A regular file/directory in a discovery path is never deleted. An unknown symlink is never deleted.
* Every config mutation: **backup → parse → minimal in-place edit → re-parse to validate → atomic
  rename**. If validation fails the original file is left untouched.
* `Adopt` copies into the library and then replaces the original with an exposure entry only after
  the copy is verified. It never moves user files behind their back and is always explicit.

## 6. Consolidation

`Consolidate` makes the library the only home for every skill and subagent:

1. Every real skill directory found in `~/.agents/skills`, `~/.claude/skills` or `~/.codex/skills`
   is **moved** into `~/.skillswitch/skills/`. Two copies of one name: the first wins, the
   other is parked under `backups/`, never deleted.
2. If `~/.claude/skills` is a symlink, it is replaced by a real directory — this is the step that
   makes the Claude and Codex columns independent, because the old target was a Codex root.
3. Each capability is linked back into exactly the agents that could see it a moment before, so
   the matrix reads identically before and after.
4. Every step is appended to `backups/consolidate-<stamp>/manifest.json`.

Real subagent `.md` files in `~/.claude/agents` move into `agents/claude/` and are hard-linked back,
so the file keeps its inode and Claude keeps loading it.

The operation is planned, previewed and confirmed before anything moves, and running it twice is a
no-op. `--consolidate` prints the plan; `--consolidate --yes` carries it out.

## 7. UI

Deployment target 26.0. Liquid Glass is left to the window and toolbar chrome, where the system
puts it anyway — an earlier pass applied `glassEffect` to every control in the content and the result
read as an effect rather than an instrument.

The identity comes from two rules instead, both derived from the subject rather than applied to it.
**Saturated colour means agency**: clay for Claude, blue for Codex, coloured only when that agent is
actually loading the capability, with amber and red reserved for attention. **Monospace means
machine**: capability names are literally slugs, so they and every count and status are set in
SF Mono, while descriptions stay in the system face — the split is the app's own subject, a bridge
between machine config and human intent.

The signature element is the switch, which shares the app icon's motif and encodes governance in its
border: a solid track means this app controls it, a dashed track means it does not and clicking will
never help. Knob position gives on/off, colour gives agency. That replaced a text pill, which needed
a legend the switch does not.

 `NavigationSplitView` with a sidebar for the three
capability kinds and a live per-agent ON count; `.searchable` in the toolbar; the matrix rows use
`glassEffect(_:in: .capsule)` tinted by agent, inside a `GlassEffectContainer`.

The window's agent column headings are a **pinned list section header** with an opaque `.bar`
background. Floating them above the list in a `VStack` looked identical at rest but let scrolled
rows draw over the labels, because a translucent strip does not clip what passes beneath it.

Each column heading carries a **master switch** (`MasterSwitch`) for everything beneath it. It took
the agent mark's place there, which is a trade worth stating: the heading gave up a tile that was
always coloured for a control that is coloured only when the column has something on. That obeys the
colour rule instead of decorating around it, and it makes the heading a gauge — but it does mean the
column's identity now rests on the word beside it, which is why the word stayed.

It is the only control in the app with a third knob position. `mixed` sits in the centre, where a row
switch would mean `BROKEN`; the two never collide because a master switch is always solid and a
`BROKEN` knob is always red on a dashed track. Clicking a mixed column fills it, never empties it —
the half-checked-checkbox rule, chosen so a single click cannot silently undo work. Rows the app does
not govern are excluded from the aggregate rather than counted as off: including them would make a
switch that can never read `allOn`, which is worse than not offering one.

The sidebar navigates both axes of the same data. Picking a capability kind gives the
capability × agent matrix; picking an agent gives `AgentInventoryView` — that agent's whole
inventory grouped by kind, with only its own switch plus a dimmed read-out of the other agent, so
flipping one side never hides what the other is doing. Both are views over one `Inventory`; there is
no second query path and nothing to keep in sync.

The menu bar popover is a third, condensed view of the same matrix, sharing one `InventoryModel`
with the panel. Its scroll area needs an explicit `.frame(maxHeight: .infinity)`: the outer
`.frame(minHeight:)` stretches the popover but never forces a flexible child to grow, so without it
the rows collapse to zero height inside an empty gap.

Claude and Codex each get a tinted glyph tile (`AgentMark`) in the sidebar, the column headings, the
batch bar and the consolidation preview. These are our own marks — a clay `sparkle` for Claude and a
blue `chevron.left.forwardslash.chevron.right` for Codex — not redrawings of Anthropic's or OpenAI's
trademarked logos.

## 8. Scope

In: scan, inventory, status, toggle, batch toggle, search, refresh, source path, Reveal in Finder,
Adopt. Out: marketplace, chat, API keys, usage dashboards, memory, cloud sync, accounts, daemons.
