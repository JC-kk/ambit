<div align="center">

<img src="docs/icon.png" width="112" alt="">

# Agent Capabilities

**Which skills, MCP servers and subagents can Claude Code see? Which can Codex see?**
One matrix, one switch each, and nothing gets deleted.

</div>

![The panel](docs/panel.png)

Claude Code and Codex both load skills, MCP servers and subagents — from different directories, in
different formats, with different rules about what counts as "installed". There is no single place to
see what each one is actually loading, and no way to give something to one agent but not the other.

This is that place. It lives in the menu bar, it reads the truth off your filesystem every time, and
turning something off means the agent stops finding it — never that a file got removed.

```
Skills                     Claude     Codex
  seo                        ON        ON
  shopify                    ON        OFF
  audio-research             OFF       ON
  legacy-notes               EXTERNAL  OFF
```

## Install

```bash
brew install --cask <owner>/tap/agent-capabilities
```

Or grab the `.dmg` from [Releases](../../releases). Requires macOS 26.

To build it yourself — Xcode 26+, no other dependencies, no Rust, no Node:

```bash
./build.sh && open AgentCapabilityManager.app
```

## Start here: Consolidate

Out of the box your skills and subagents live inside Claude's and Codex's own folders, which is why
the two columns move together. **Consolidate** moves each source into `~/.agent-capabilities` and
links it straight back, so nothing changes about what either agent can see — the switches just start
working.

It shows you the whole plan first. Nothing is deleted: a duplicate that cannot become the canonical
copy is parked under `backups/`, and every move is written to a manifest.

```bash
AgentCapabilityManager --consolidate          # print the plan
AgentCapabilityManager --consolidate --yes    # carry it out
```

## Two ways to read the same thing

The sidebar switches between the two axes:

- **Skills / MCP / Subagents** — the capability × agent matrix. *Who can see this thing?*
- **Claude / Codex** — that agent's whole inventory across all three kinds, with just its own switch
  and a dimmed note of what the other agent is doing. *What is this agent loading right now?*

Saturated colour only ever means agency: clay is Claude, blue is Codex, and a switch is filled only
when that agent is really loading the thing. So the amount of clay on screen is the answer to "how
much is Claude loading" without reading a word.

## The five states

| | meaning |
|---|---|
| `ON` | that agent can discover it right now |
| `OFF` | it cannot |
| `EXTERNAL` | discoverable, but the on-disk entry was not created by this app |
| `BROKEN` | present but unusable — dangling link, missing `SKILL.md`, unparseable config |
| `N/A` | that agent has no discovery mechanism for this kind |

Nothing is cached. Every status is re-derived from `lstat`, `realpath` and the agents' own config
files on each scan, so the app cannot drift out of sync with reality. When a switch is disabled, the
tooltip says exactly why.

## How exposure actually works

| kind | Claude Code | Codex |
|---|---|---|
| Skill | symlink in `~/.claude/skills` | symlink in `~/.codex/skills` |
| Subagent | **hard link** in `~/.claude/agents` | `[agents.<name>]` in `config.toml` |
| MCP | parked in / restored to `~/.claude.json` | native `enabled` key in `config.toml` |

Every one of those was pinned down against a specific CLI version rather than assumed. Three that
are easy to get wrong:

- **Codex scans `~/.agents/skills` as well as `~/.codex/skills`.** Anything there is on for Codex
  unconditionally, which is why the library lives somewhere neither agent scans.
- **Claude Code's subagent scanner skips symlinked `.md` files** (`if (entry.isSymbolicLink())
  continue`). Hard links are regular files to every reader, share the library file's inode, and
  unlinking one cannot destroy the library copy.
- **Codex subagents are real**, declared as `[agents.<name>]` pointing at a role file with `name`,
  `description` and `developer_instructions`. Claude's `.md` format is not compatible, so switching
  Codex on converts it. `codex doctor` validates the result.

`DESIGN.md` has the full findings and the probe used for each.

## Safety

This app edits files you cannot afford to lose, so the rules are narrow and enforced in the core
rather than the UI:

- **Disabling never deletes a source.**
- Removal requires proof of ownership: a symlink must resolve inside the library; a hard link must
  share the library file's inode *and* not be the last link to its data.
- A regular file or directory in a discovery path is never deleted, and neither is a symlink this app
  did not create. Where that leaves no safe way to switch something off, the switch is disabled and
  says so instead of guessing.
- JSON configs are edited as **text** — one top-level key spliced in place. Key order, indentation
  and float formatting survive byte for byte. (Re-serialising `~/.claude.json` would silently rewrite
  thousands of unrelated bytes; Foundation does not round-trip doubles.)
- TOML edits touch a single key or table and leave comments, ordering and unknown keys alone.
- Every config write is **backup → parse → minimal edit → validate → atomic rename**. If the result
  would disturb anything outside the intended change, nothing is written.
- If a library source is deleted by something else, the app tells you rather than quietly dropping it
  from the list.

52 tests cover these, all against throwaway fixture trees — the suite never touches a real
`~/.claude` or `~/.codex`.

## Command line

```bash
AgentCapabilityManager --print                 # the matrix, as text; read-only
AgentCapabilityManager --consolidate [--yes]   # plan, or carry it out
AgentCapabilityManager --panel                 # open the desktop panel directly
ACM_HOME=/tmp/fake AgentCapabilityManager      # point everything at a throwaway tree
```

## If your Codex column looks stuck

`~/.claude/skills` is often a symlink to `~/.agents/skills`, which Codex also scans — so every skill
exposed to Claude is on for Codex too, and the app correctly shows that column as `EXTERNAL` and
disabled. **Consolidate** fixes it by turning `~/.claude/skills` back into a real directory. It will
not happen on its own.

Afterwards, if you have a standing instruction telling agents to install skills into
`~/.agents/skills` (`~/.codex/AGENTS.md`, `CLAUDE.md`), point it at the library instead or new skills
will land outside it.

## What this deliberately is not

No marketplace, no chat, no API keys, no usage dashboards, no cloud sync, no accounts, no background
daemon. It is a local control panel for inventory and exposure. Anything that is not that belongs in
a different app.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The short version: mechanisms need evidence, not guesses —
if you change how a capability is discovered, include the probe that proves it.

MIT licensed.
