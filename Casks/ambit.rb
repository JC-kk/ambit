cask "ambit" do
  version "1.0.0"
  sha256 "fa15ef253ce2769bcc5e376d3d55061172e699a9e507dd71d439ca24c422db4a"

  url "https://github.com/JC-kk/ambit/releases/download/v#{version}/Ambit-#{version}.dmg"
  name "Ambit"
  desc "Menu bar control panel for Claude Code and Codex skills, MCP servers and subagents"
  homepage "https://github.com/JC-kk/ambit"

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
