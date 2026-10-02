// A sleeping stand-in for an orphaned tool server. The Mac tests start it with an MCP-style argument
// (e.g. ".../node_modules/.bin/mcp-server-fixture"), orphan it, then scan, classify and stop it for real.
// It ignores its arguments and exits by itself after 10 minutes so a failed test never leaks it.
// A SIGTERM-proof variant is made by the tests with a shell `trap '' TERM` wrapper: ignored signals survive exec.
import Darwin

// Daemonise like a real detached tool server: its own session, no controlling terminal (failure is harmless).
_ = setsid()
for _ in 0..<600 { sleep(1) }
