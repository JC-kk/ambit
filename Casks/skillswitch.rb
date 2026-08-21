# NOT PUBLISHABLE YET. The version and checksum below still describe the last release cut under the
# old name (Ambit-1.1.0.dmg), so this URL 404s. Cut a release whose asset is Skillswitch-<version>.dmg,
# then replace both lines.
cask "skillswitch" do
  version "1.1.0"
  sha256 "d0a71a44526c13f881b239af69ec59362c36b32e5d8fcc6a5e23d6e51316d2fe"

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
