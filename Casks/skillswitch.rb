cask "skillswitch" do
  version "2.0.0"
  # Taken from the v2.0.0 release's checksums.txt, not from a local build: hdiutil output is
  # not reproducible, so the two differ. See docs/RELEASING.md.
  sha256 "8280f457d4393d4c88a069316435dd7e4ce03e2907fdfcace70219a79655fbb1"

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
