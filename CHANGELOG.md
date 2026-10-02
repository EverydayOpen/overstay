# Changelog

Newest first. `tools/changelog.py` turns each section into the GitHub release notes and the website changelog, so
write for users. Headings must be `## X.Y.Z — YYYY-MM-DD` (em dash); the release workflow refuses a tag without one.
Write upcoming notes under `## Unreleased`, which is never published (the website deploys on every push to main). On
release day, rename it to `## X.Y.Z — <that day>`, commit, push only the tag, and push main once the release is
published (docs/RELEASING.md "Cutting a release"). Links must be full `https://` URLs: the GitHub release can't
resolve site-relative ones.

## Unreleased

First release. Overstay finds the processes your AI coding agents left running with nothing attached to them, shows how much
memory they hold and which project started them, and stops them safely.

- **Finds leftovers**: tool servers and automation browsers whose parent is gone and that no live session is using.
  Each one says why it was listed, in plain words. Anything it is not sure about is shown as "Maybe" and is never
  stopped in bulk.
- **Grouped by project**: one row per tool and project, with how many processes, how much memory they hold and how long
  ago they started. A weight bar shows which group is the heaviest.
- **Stops politely**: a stop sends the gentle signal to children before parents, waits, and tells you what is still
  running. A stronger signal is a separate click, per group. Overstay checks every process again right before it acts.
- **Cannot touch the wrong thing**: only your own processes; never the system, your terminal, your editor or a live
  session. A "never touch this" list in Preferences can only add to what is protected.
- **Menu bar and window**: the menu bar shows a badge only when something was left behind. "Copy my number" makes a
  share card with no project names unless you choose to include them.
- **Activity log**: every stop is written to a local log with no arguments and no environment.
- Needs no permissions, runs offline, sends nothing, reads no file contents and changes none of your files. A stopped process
  cannot be brought back, and Overstay says so before you confirm.
- Requires macOS 13 or later, on Apple silicon or Intel. Free and open source under the MIT License. Overstay is not
  affiliated with or endorsed by any of the tools it detects.
