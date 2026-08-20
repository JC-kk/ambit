cask "agent-capabilities" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256_FROM_checksums.txt"

  url "https://github.com/OWNER/REPO/releases/download/v#{version}/AgentCapabilities-#{version}.dmg"
  name "Agent Capabilities"
  desc "Menu bar control panel for Claude Code and Codex skills, MCP servers and subagents"
  homepage "https://github.com/OWNER/REPO"

  depends_on macos: ">= :tahoe"

  app "AgentCapabilityManager.app"

  # The library is the user's source of truth for every skill and subagent, so it is never removed
  # on uninstall. Delete ~/.agent-capabilities by hand if you really mean to.
  zap trash: [
    "~/Library/Saved Application State/local.agentcapabilities.manager.savedState",
  ]
end
