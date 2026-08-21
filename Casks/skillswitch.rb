cask "skillswitch" do
  version "2.0.0"
  sha256 "890557b660aa54aa22cd1010cd0138a04afcb6564beb98fafa87ec1ab2d1a5e1"

  url "https://github.com/JC-kk/skillswitch/releases/download/v#{version}/Skillswitch-#{version}.dmg"
  name "Skillswitch"
  desc "Switch panel for Claude Code and Codex skills, MCP servers and subagents"
  homepage "https://github.com/JC-kk/skillswitch"

  # Ad-hoc signed rather than notarised: notarisation needs a paid Apple Developer Program
  # membership. The artifact arrives quarantined regardless — the attribute comes from downloading
  # the dmg, and brew copies the app out of the mounted volume without stripping it — so after
  # installing, run:
  #   xattr -dr com.apple.quarantine /Applications/Skillswitch.app
  depends_on macos: :tahoe

  app "Skillswitch.app"

  # The library is the user's source of truth for every skill and subagent, so it is never removed
  # on uninstall. Delete ~/.skillswitch by hand if you really mean to.
  zap trash: "~/Library/Saved Application State/dev.skillswitch.Skillswitch.savedState"
end
