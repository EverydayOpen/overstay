# Going live: from zero to the first public release

Overstay is free and open source: there are no payments, licences, accounts or updater to set up. Do the steps in order;
each one unblocks the next. `bash tools/doctor.sh` shows what's configured and what's still open. Signing and
notarization details live in [RELEASING.md](RELEASING.md); this file covers everything around them. Anything marked
**VERIFY** wasn't confirmed against the provider's docs, so check it there when you get to it.

The product decision, kill tests and launch plan are in the Whydunit repo's `docs/next/APP3.md` (sections 4 and 5);
the build contract is [BUILD_PLAN.md](BUILD_PLAN.md). Target: launch the week of 2026-11-02, **only if** T2 and T3 below
passed.

## 1. Name check (before anything goes public)

"Overstay" is a common dictionary word, so expect search noise (visa overstays) and check trademarks before any paid
marketing. A knockout search is a quick screen for obvious conflicts, not a legal clearance.

- Search "Overstay" and close variants for software in Nice classes **9** (downloadable software) and **42** (software
  services):
  - USPTO: https://tmsearch.uspto.gov/
  - EUIPO: https://euipo.europa.eu/eSearch/ (**VERIFY** the address)
  - WIPO Global Brand Database: https://branddb.wipo.int/
  - India, IP India public search: https://tmrsearch.ipindia.gov.in/tmrpublicsearch/ (**VERIFY** the address)
  - The Mac App Store and a web search for "Overstay app" and "Overstay Mac".
- If a live mark or a shipping app uses the same or a confusingly similar name for software, switch to a fallback
  (*Afterparty*, *Stragglers*). The name appears in `project.yml`, `Package.swift`, `App/`, `Sources/`, `site/site.json`,
  the workflows' `APP`, the README and the site pages.
- Titles and the first line always read "Overstay for Mac" plus what it does, to cut the visa-overstay noise.

## 2. GitHub: repo, Pages and the first CI runs

1. **Public repo.** On GitHub's free plan the repo must be public for the `release` environment, its secrets and its
   `v*` rule, for required reviewers, and for CodeQL. A public repo also runs standard GitHub-hosted runners, macOS
   included, for free (**VERIFY** current Actions pricing if you ever go private).
2. **Push.** From this folder, with `gh` logged in as EverydayOpen:
   `git init -b main` (already done), confirm `git config user.email` is
   `36332199+EverydayOpen@users.noreply.github.com` (`bash tools/doctor.sh` checks), then
   `git add -A && git status --ignored`. Every file staged becomes public, so check that no key material or secrets are
   among them. Commit messages carry no `Co-Authored-By` trailer and name no AI tool or product (ci.yml's `checks` job
   fails the push otherwise). Then `gh repo create EverydayOpen/overstay --public --source . --push`. Keep `-b main`:
   `ci.yml` and `site.yml` run only on `main`.
3. **First CI run is the first compile.** Nothing in `OverstayMac`, `OverstayFixture` or `App/` has ever been compiled.
   Expect the `macos` job to fail on the first push; fix the compile errors from its log, in small commits, until it is
   green. Until it is, every Mac and App file is "written, not compiled" (AGENTS.md).
4. **Pages.** The first push runs `site.yml`, which creates the `gh-pages` branch. Then open Settings › Pages › Build and
   deployment › Source: **Deploy from a branch**, branch `gh-pages`, folder `/ (root)`, and **Save**. The site is
   served at `https://everydayopen.github.io/overstay/`, which is `site/site.json`'s `baseURL` and `Links.website` in
   `App/Links.swift`; `bash tools/doctor.sh` checks that they agree. Leave **Issues** on: the site and the app's Help
   menu send people there. Create the label `false-positive` for the issue form.
5. **Repository settings** listed in RELEASING.md step 4 (branch ruleset, immutable releases, private vulnerability
   reporting). **Leave the CodeQL default setup off**: `codeql.yml` is the setup. Its Swift build mode has never run
   (**VERIFY** the first run traces the build; the file's header says what to check).
6. **Real process output (R3, R11).** Open Actions › **fixtures** › Run workflow. It runs the real-system tests on the
   arm64 and Intel runners and uploads `diagnostics.txt` (how many processes had readable arguments, working folders and
   memory). Read the "readable" counts: if arguments or working folders are unreadable for ordinary same-user
   processes, attribution is dead and the plan changes (APP3 R3). Also note whether the orphaned fixture was
   reparented to `launchd` (otherwise that test skips, R11).

## 3. Kill tests and testers (APP3 section 5)

- **T0 (before launch week):** read the latest Claude Code and Codex release notes and open issues for orphan or zombie
  fixes; count new reports in the last 30 days. If upstream fixed it, stop.
- **T1:** the owner (not an agent) posts a short, non-promotional "how many leftover agent processes do you have?" with
  a snippet that only counts. Fewer than about 10 real numbers: reconsider.
- **T2:** a tester runs a beta on a real Mac and sends **Help › Copy Diagnostics**. Argument or working-folder readability
  for Node and Chrome children decides whether attribution works. Also answers the open question in BUILD_PLAN section
  12 about a leftover inside a still-open terminal (protected vs Maybe), and checks the menu bar badge VERIFY item on
  macOS 13, 15 and 26.
- **T3:** a 5 to 7 day dry run on two or more real Macs with stopping disabled; the tester marks each Ghost right or
  wrong. More than 1 wrong in 20: do not ship Stop.

## 4. Optional: a custom domain

Skip this unless you want your own domain; `everydayopen.github.io/overstay` works as is.

1. Verify the domain for the EverydayOpen organization first (organization Settings › Pages › **Add a domain**; GitHub
   shows a TXT record to add). This stops anyone else from taking the domain over on GitHub Pages.
2. Add these records at your DNS host:

   | Type | Name | Value |
   |---|---|---|
   | A | `@` | `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153` (four records) |
   | AAAA | `@` | `2606:50c0:8000::153`, `2606:50c0:8001::153`, `2606:50c0:8002::153`, `2606:50c0:8003::153` |
   | CNAME | `www` | `everydayopen.github.io` |

3. In the repo, open Settings › Pages › Custom domain, enter the domain and save. GitHub commits a `CNAME` file to
   `gh-pages`, which `site.yml` never overwrites. Tick **Enforce HTTPS** when it becomes available.
4. Change `site/site.json` `baseURL` and `Links.website` to `https://<domain>` (no path) and run
   `bash tools/doctor.sh`. The app has no update feed, so older copies only lose their Help link's address; GitHub
   redirects the old one.

## 5. Apple Developer Program and signing

Public betas can ship unsigned (`beta.yml`, with the Gatekeeper steps in the release notes and a SHA-256). A first
**public** launch is much better signed and notarized: follow RELEASING.md steps 1 to 4 (enrollment, the Developer ID
Application certificate, the App Store Connect Team API key, and the `release` environment with its seven secrets). With
`gh` logged in, `bash tools/doctor.sh` lists any secret that's still missing. Overstay is a process-signalling app from a
new developer, so the trust cost of an unsigned build is real: decide before launch week, not on it.

## 6. Website and privacy review

1. `site/site.json` names the owner (EverydayOpen), shown in the site footer. Run
   `python tools/build_site.py --check` and push `main`: `site.yml` publishes the site. `/download/` shows the
   no-release-yet status line and the Releases button until `CHANGELOG.md` on `main` has a released section (step 8).
2. **Privacy review.** The site has no separate terms or privacy pages; the safety page's Privacy section is the
   privacy text. Have a lawyer check it
   against: free, open-source software under the MIT License, provided as is; an app that **signals processes**, where
   stopping the wrong one can lose unsaved work ("findings, not guarantees", and the no-undo wording in the confirm
   sheet); what the app actually does (no network, no telemetry, no account, one local activity log and one preferences
   blob; reads process names, memory and, for matching processes, scrubbed argument lists on screen only); GitHub as
   host of the site and the downloads (it sees visitors' IP addresses; **VERIFY** what it logs for Pages and release
   downloads); and the contact route for privacy requests.
3. The site and README use real tester numbers once they exist, with permission. Until then every number is labelled
   "Sample data".

## 7. Go / no-go

Publish only when all of these hold (APP3 R4, R7, R8):

- CI is green on the exact commit being tagged, including the real-system tests on arm64 and Intel.
- T2 passed (arguments and working folders readable for the processes that matter) and T3 passed (at most 1 wrong Ghost
  in 20), or Stop ships disabled and the beta says so.
- The first-run screen, the confirm sheet ("This cannot be undone. Anything unsaved inside these processes is lost.") and
  the result sheet were read by a person on a real Mac.
- The release notes state what was tested ("tested by N testers on macOS X"), nothing more.
- `bash tools/doctor.sh` has no `ERROR` and no `todo` you have not decided to accept; `tools/safety_greps.sh` and
  `tools/repo_checks.sh` are green.

## 8. First release

1. **Rehearse** as RELEASING.md describes under "Before the first public release".
2. On release day, rename `## Unreleased` in `CHANGELOG.md` to `## 1.0.0 — <that day>` and commit it, then tag and push
   only `v1.0.0`. Push `main` once the release is published (RELEASING.md "Cutting a release"): that push deploys the
   site, and `/download/` stops showing the no-release-yet status line.
3. **Homebrew** (optional, **VERIFY**): an own tap `EverydayOpen/homebrew-tap` with a cask pointing at
   `releases/download/v1.0.0/Overstay-1.0.0.dmg` and its SHA-256. Homebrew's stance on casks in its official tap is
   unverified; an own tap avoids the question.

## 9. Launch and after

APP3 section 4 has the order: testers first, Reddit (r/ClaudeAI, r/ClaudeCode, then r/mac or r/macapps if their rules
allow it), Show HN with the demo GIF and a write-up of the heuristics and safety rules, at most one disclosed comment on
each upstream issue, newsletters, Product Hunt a week or two later. Post Tuesday to Thursday, about 8 to 10 am US Eastern,
and avoid Black Friday week. Post nothing automatically; the owner posts.

Post-release checks:

- The stable link downloads the new DMG
  (`https://github.com/EverydayOpen/overstay/releases/latest/download/Overstay.dmg`; `<baseURL>/download/` does not use it
  yet, so check the page's own link too). It opens and the app launches
  without a Gatekeeper warning. The release workflow already launched it on Apple silicon and Intel.
- `/changelog/` and `/feed.xml` show the release.
- In the app, the Help menu opens the website and the false-positive form, and everything works with Wi-Fi off.
- Watch Issues (every false positive becomes a Core fixture and a test) and the Actions runs. The weekly **ci** and
  **fixtures** runs show whether the current macOS image still behaves as the tests assume.
- Kill criteria (APP3 section 4): fewer than about 150 stars and 200 release downloads by day 14, or fewer than about 500
  stars by day 45, or upstream ships reliable reaping: stop feature work and keep the repo maintained but quiet.
