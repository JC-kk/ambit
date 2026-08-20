cask "ambit" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256_FROM_checksums.txt"

  url "https://github.com/OWNER/REPO/releases/download/v#{version}/Ambit-#{version}.dmg"
  name "Ambit"
  desc "Menu bar control panel for Claude Code and Codex skills, MCP servers and subagents"
  homepage "https://github.com/OWNER/REPO"

  # Ad-hoc signed rather than notarised: notarisation needs a paid Apple Developer account. Install
  # with `--no-quarantine`, or clear the flag afterwards with
  #   xattr -dr com.apple.quarantine /Applications/Ambit.app
  depends_on macos: ">= :tahoe"

  app "Ambit.app"

  # The library is the user's source of truth for every skill and subagent, so it is never removed
  # on uninstall. Delete ~/.agent-capabilities by hand if you really mean to.
  zap trash: [
    "~/Library/Saved Application State/dev.ambit.Ambit.savedState",
  ]
end
