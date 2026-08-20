cask "ambit" do
  version "1.0.1"
  sha256 "7cef7f0438f3b52a9062c0c81661da1483e65b94026abb85835d25b28d035d23"

  url "https://github.com/JC-kk/ambit/releases/download/v#{version}/Ambit-#{version}.dmg"
  name "Ambit"
  desc "Switch panel for Claude Code and Codex skills, MCP servers and subagents"
  homepage "https://github.com/JC-kk/ambit"

  # Ad-hoc signed rather than notarised: notarisation needs a paid Apple Developer Program
  # membership. The artifact arrives quarantined regardless — the attribute comes from downloading
  # the dmg, and brew copies the app out of the mounted volume without stripping it — so after
  # installing, run:
  #   xattr -dr com.apple.quarantine /Applications/Ambit.app
  depends_on macos: :tahoe

  app "Ambit.app"

  # The library is the user's source of truth for every skill and subagent, so it is never removed
  # on uninstall. Delete ~/.agent-capabilities by hand if you really mean to.
  zap trash: "~/Library/Saved Application State/dev.ambit.Ambit.savedState"
end
