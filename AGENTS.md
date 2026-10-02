# Overstay: notes for coding agents

Overstay is a free, open-source (MIT), offline macOS app (Swift/SwiftUI, macOS 13+, Swift 5 language mode, not
sandboxed, no permissions) that finds the processes AI coding agents left running with nothing attached to them and stops
them safely. It touches processes, never files.

Read [docs/BUILD_PLAN.md](docs/BUILD_PLAN.md) first. It is the contract: public API names (§4, §5, §7), safety rules (§3),
UI rules and copy (§8), demo mode (§9), file ownership (§10). Product background: the Whydunit repo's `docs/next/APP3.md`. Going live: [docs/GO_LIVE.md](docs/GO_LIVE.md), [docs/RELEASING.md](docs/RELEASING.md).

## Be honest about what has run

- Only `OverstayCore` is compiled and tested locally (Linux, in Docker). `OverstayMac`, `App/` and the workflows have
  never been compiled or run until a CI run on macOS says so. **Never claim Mac or App code builds or works unless a CI
  run shows it.** Say "written, not compiled". Nothing has run on a real Mac: never claim runtime behaviour
  (argv/cwd readability, orphan reparenting, signalling) until a tester has tried it.
- Don't invent APIs, flags or behaviour. Check Apple's headers/docs; mark anything you couldn't verify with `VERIFY`.
  If you're unsure an API exists on macOS 13, don't use it, or put it in `App/DesignSystem/Compat.swift` behind
  `if #available`.
- macOS 13 means `ObservableObject`, `@Published` and `@StateObject`; never `@Observable` or `@Bindable`.

## Test

```sh
bash tools/test_core_docker.sh          # Core build + tests in Docker (Windows Git Bash too); must pass with no warnings
bash tools/safety_greps.sh              # the safety rules as greps; must print "safety greps: ok"
bash tools/repo_checks.sh              # home paths, empty Buttons, Edit menu, commit identity and credit lines
swift test                              # on a Mac: Core, Mac and real-system tests
python tools/changelog.py --self-test   # changelog parser and markdown renderer
python tools/build_site.py --check      # website build: links, meta tags, contrast, placeholders
bash tools/doctor.sh                    # what's configured and what's left before go-live
```

## Safety rules (BUILD_PLAN §3; CI greps enforce the mechanical ones)

This app signals processes; a bug can stop the wrong thing. In short:

- `kill(` and every `SIG*` name live only in `Sources/OverstayMac/Signal.swift`. Positive pid greater than 1 only; never
  a process group or negative pid. No `Process`, shell, `ps`, `pkill`, `lsof` anywhere in `Sources/` or `App/`.
- Only same-uid processes. Never pid <= 1, our own pid, any ancestor of ours, a zombie, or a protected process.
- Re-verify (same pid, start time, executable path, uid, signature, still Ghost/Maybe) immediately before every signal,
  with no `await` in between. SIGTERM first, leaf-first, grace wait; SIGKILL only on an explicit per-group Force stop.
- Default selection is Ghosts only; Maybes are never in a bulk action.
- Never delete, move or write any file except the activity log, a save-panel PNG and the preferences blob in UserDefaults. Never read file contents (stat only).
- argv is scrubbed before it enters any model; environment values are never stored or logged; nothing prints or logs
  argv/env. The activity log holds signature id, executable basename, pid, project folder name, result: no argv, no env.
- No network, no telemetry, no Sparkle, no third-party dependencies in v1.
- No "undo" and no "freed memory" claims. "started 3 days ago", never "session ended".
- No `Button` with an empty action (a dialog's `role: .cancel` is the exception).

## Repo rules

- **Naming and attribution (owner decision 2026-10-02).** Docs, README, site and signature data may name Claude Code,
  Codex, Cursor, Zed, Windsurf and similar tools descriptively, as things Overstay detects, always with "not affiliated
  with or endorsed by". Those names never appear in commit messages, author fields, PR text, `Co-Authored-By` trailers or
  any "built with" / credit line. CI checks commit identity and messages on pushes to `main` only, not on pull requests (a
  signature PR names its tool); maintainers squash-merge (GitHub records the PR author as author and GitHub as committer, which the author check allows), so a PR title must be clean too, and the `Co-authored-by` trailer GitHub adds to a squash message must be deleted because the message check greps for it. No `Co-Authored-By` trailers, ever. Git identity:
  `EverydayOpen <36332199+EverydayOpen@users.noreply.github.com>`.
- No personal home paths in committed files (Windows user folders, or `/Users/` followed by a real name). CI fails on
  them. Use `~`, `<scratchpad>`, a repo-relative path, or the example user `jane`. `/Users/Shared` is allowed.
- Every release needs a `## X.Y.Z — YYYY-MM-DD` section in `CHANGELOG.md`, written for users. Upcoming notes go under
  `## Unreleased` (never published).
- One base URL, `https://everydayopen.github.io/overstay`: `site/site.json` `baseURL` == `App/Links.swift` `Links.website`.
  `tools/doctor.sh --ci` fails when they disagree.
- Python tools use the standard library only. Never commit key material (`.p12`, `.p8`) or real secrets.
- Code style is ponytail (BUILD_PLAN §1): the shortest correct code, no protocols with one implementation, no view model
  per screen, comments only where the why isn't obvious.

## Ownership

When several agents work in parallel, each edits only its own files (BUILD_PLAN §10). `Model/*`, `Package.swift` and
`docs/BUILD_PLAN.md` are frozen: add extensions in your own files, and propose any other change in your report.
