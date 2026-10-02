#!/usr/bin/env bash
# The safety rules of docs/BUILD_PLAN.md §3 as greps. CI runs this (ci.yml `checks` job); run it locally before pushing.
# GNU grep (Git Bash and Linux): the regexes use \b. Only Sources/ and App/ are searched, so tests and tools are exempt.
# Each check prints its hits and fails the script. Owner: infra. Rule text lives in BUILD_PLAN §3; this file is exact.
set -u
cd "$(dirname "$0")/.."
fail=0
check() { if [ -n "$2" ]; then echo "$2"; echo "::error::$1"; fail=1; fi; }
S='--include=*.swift'
# Whole-line // comments are exempt everywhere (a comment can't run); a trailing comment after code is not.
C='^[^:]+:[0-9]+:[[:space:]]*//'
# hits REGEX [EXEMPT] [DIRS]: matching lines "file:line:text", minus comment lines, minus lines matching EXEMPT
# (a grep -E pattern, normally a "file:" prefix such as '^Sources/OverstayMac/Signal\.swift:').
hits() { grep -rnsE $S "$1" ${3:-Sources App} | grep -vE "$C" | grep -vE "${2:-^$}" || true; }

K='(^|[^[:alnum:]_])(kill|killpg|pthread_kill|raise)[[:space:]]*\(|\bSIG(TERM|KILL|STOP|CONT|HUP|INT|QUIT|USR1|USR2|ABRT)\b'
# Mutation self-tests: a regex that does not trip on its own bad example proves nothing. selftest NAME REGEX 'bad line'.
selftest() { local T; T=$(mktemp -d); printf '%s\n' "$3" > "$T/x.swift"; [ -n "$(hits "$2" "" "$T")" ] || check "safety_greps self-test: $1 missed: $3" "self-test failed"; rm -rf "$T"; }
selftest kill "$K" 'kill (1, 9)'
selftest kill "$K" 'killpg(g, 15)'
selftest kill "$K" 'raise(9)'

# Signal.swift is exempt from check 1 below, so it gets its own: exactly one Darwin.kill, spelled `Darwin.kill(pid, number)`
# (never pid 0 or a negative pid, never a literal signal), no killpg, pthread_kill, raise or other signal names, and send()
# keeps its `guard pid > 1, pid != getpid()`. It also pins the mapping and the guards a mutation would hollow out: SIGTERM only
# for .term, SIGKILL only for .kill, kind is .kill only for a force plan, run()'s pid/ancestor guard, the StopPlanner.verify call,
# and the write-ahead `.signalled` log line before send(kind. sigprobs prints the problems, one per line.
sigprobs() {
  local c n s a b; c=$(grep -nvE '^[[:space:]]*//' "$1")
  printf '%s\n' "$c" | grep -E '(^|[^[:alnum:]_.])kill[[:space:]]*\(|\b(killpg|pthread_kill|raise)\b|\bSIG(STOP|CONT|HUP|INT|QUIT|USR1|USR2|ABRT)\b' || true
  n=$(printf '%s\n' "$c" | grep -oE '\b(Darwin|Glibc)\.kill\b' | wc -l)
  [ "$n" -eq 1 ] || echo "$1: expected exactly one Darwin.kill, found $n"
  printf '%s\n' "$c" | grep -E '\b(Darwin|Glibc)\.kill\b' | grep -vE 'Darwin\.kill\(pid, number\)' || true
  grep -qE 'guard pid > 1, pid != getpid\(\)' "$1" || echo "$1: send() lost its guard pid > 1, pid != getpid()"
  for s in 'case .term: number = SIGTERM' 'case .kill: number = SIGKILL' 'let kind: Kind = plan.mode == .force ? .kill : .term' \
           'guard pid > 1, pid != me, pid != parent, !ancestors.contains(pid), !world.ancestors.contains(pid)' 'StopPlanner.verify(' 'status: .signalled'; do
    printf '%s\n' "$c" | grep -qF -- "$s" || echo "$1: lost the line: $s"
  done
  for s in SIGTERM SIGKILL; do
    n=$(printf '%s\n' "$c" | grep -oE "\b$s\b" | wc -l)
    [ "$n" -eq 1 ] || echo "$1: expected exactly one $s outside comments, found $n"
  done
  a=$(printf '%s\n' "$c" | grep -F -m1 'status: .signalled' | cut -d: -f1)
  b=$(printf '%s\n' "$c" | grep -F -m1 'send(kind' | cut -d: -f1)
  { [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; } || echo "$1: the .signalled log line must come before send(kind"
}
SIGF=Sources/OverstayMac/Signal.swift
if [ -f "$SIGF" ]; then
  check "$SIGF must hold exactly one Darwin.kill(pid, number), guarded by pid > 1, and no killpg, pthread_kill, raise or other signals" "$(sigprobs "$SIGF")"
  # Each mutation of the real file must be flagged.
  T=$(mktemp -d)
  for m in 's/Darwin\.kill(pid, number)/Darwin.kill(0, number)/' 's/Darwin\.kill(pid, number)/Darwin.kill(-1, number)/' \
           's/Darwin\.kill(pid, number)/Darwin.kill(pid, 9)/' 's/guard pid > 1, pid != getpid()/guard pid != 0/' \
           '$a let x = Darwin.kill(pid, number)' '$a killpg(1, 9)' '$a let y = Darwin.kill' '$a pthread_kill(t, 9)' '$a kill(pid, SIGHUP)' \
           's/case \.term: number = SIGTERM/case .term: number = SIGKILL/' 's/case \.kill: number = SIGKILL/case .kill: number = SIGTERM/' \
           's/let kind: Kind = plan.mode == .force ? .kill : .term/let kind: Kind = .kill/' \
           's/guard pid > 1, pid != me, pid != parent, !ancestors.contains(pid), !world.ancestors.contains(pid),/guard true,/' \
           's/StopPlanner\.verify(/StopPlanner.skip(/' 's/status: \.signalled/status: .stopped/' \
           '$a let t = SIGTERM' '$a let k = SIGKILL' '1i let early = send(kind, to: pid)'; do
    sed "$m" "$SIGF" > "$T/Signal.swift"
    [ -n "$(sigprobs "$T/Signal.swift")" ] || check "safety_greps self-test: the Signal.swift check missed the mutation $m" "self-test failed"
  done
  rm -rf "$T"
fi
# 1. The whole signal path lives in one file. Positive pids only: kill(0, ...) and kill(-1, ...) never exist.
check "kill(), killpg(), pthread_kill(), raise() and SIG* names appear only in Sources/OverstayMac/Signal.swift" \
  "$(hits "$K" '^Sources/OverstayMac/Signal\.swift:')"

# 1b. Every other way to end a process, or to reach kill(2) indirectly: forbidden everywhere, Signal.swift included.
check "proc_terminate*(), task_terminate, task_for_pid, syscall(), dlsym and @_silgen_name appear nowhere" \
  "$(hits '(^|[^[:alnum:]_])(proc_terminate[[:alnum:]_]*|task_terminate|task_for_pid|syscall|dlsym|dlopen)[[:space:]]*\(|@_silgen_name|@_cdecl')"
# 1d. Only Swift is compiled: a C/ObjC file or a build-phase script would escape every grep above.
check "Sources/ and App/ hold no non-Swift source files and project.yml has no build scripts" \
  "$(find Sources App -type f \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.m' -o -name '*.mm' -o -name '*.h' -o -name '*.hpp' -o -name '*.s' -o -name '*.S' -o -name '*.sh' -o -name '*.py' -o -name '*.js' -o -name '*.pl' -o -name '*.rb' \) 2>/dev/null; grep -nE 'preBuildScripts|postBuildScripts|postCompileScripts|buildToolPlugins|runOnlyWhenInstalling|^[[:space:]]*-?[[:space:]]*script:' project.yml || true; grep -nE '\.plugin\(|plugins:|unsafeFlags|linkerSettings|cSettings' Package.swift || true)"
# 1c. A force plan (SIGKILL) is built only by StopPlanner.forcePlan (from .terminate survivors), never constructed or
#     assigned elsewhere. (StopPlan.mode should also be a `let` in Core, which closes the mutation hole at compile time.)
F='\.mode[[:space:]]*=[[:space:]]*\.force|mode:[[:space:]]*\.?force\b|StopMode[[:space:]]*\.force'
selftest force "$F" 'plan.mode = .force'
selftest force "$F" 'StopPlan(batchID: b, mode: .force, groupIDs: [])'
selftest force "$F" 'let m = StopMode.force'
check "A .force plan is built only in Sources/OverstayCore/Plan/StopPlanner.swift: no StopPlan(mode: .force), no .mode = .force" \
  "$(hits "$F" '^Sources/OverstayCore/Plan/StopPlanner\.swift:')"
# Outside Signal.swift even a bare reference to kill(2) (let f = Darwin.kill) is forbidden.
check "Darwin.kill, killpg, pthread_kill and raise are not even referenced outside Sources/OverstayMac/Signal.swift" \
  "$(hits '\b(Darwin|Glibc)\.(kill|killpg|pthread_kill|raise)\b' '^Sources/OverstayMac/Signal\.swift:')"

# 2. No shell, no child processes, no other way to end an app.
check "No Process, NSTask, shell, exec*, spawn, system(), popen(), fork(), AppleScript, pkill, killall, lsof, ps, launchctl or NSRunningApplication" \
  "$(hits '\bProcess\b|NSTask|\bposix_spawn|\bexec[lv]p?e?[[:space:]]*\(|(^|[^.[:alnum:]_])(system|popen|fork|vfork)[[:space:]]*\(|"/bin/(ba|z)?sh"|"/usr/bin/env"|NSAppleScript|NSUserAppleScriptTask|pkill|killall|\blsof\b|"/(usr/)?bin/ps"|launchctl|NSRunningApplication|forceTerminate')"
check "terminate() only as NSApp.terminate(nil) to quit" \
  "$(hits '\.terminate[[:space:]]*\(' '(NSApp|NSApplication\.shared)\.terminate[[:space:]]*\(')"

# 3. Processes only: no deleting, moving, copying or linking of files.
check "Never delete, trash, move, copy, link or rename files" \
  "$(hits 'removeItem[[:space:]]*\(|trashItem[[:space:]]*\(|recycle[[:space:]]*\(|unlink(at)?[[:space:]]*\(|rmdir[[:space:]]*\(|moveItem[[:space:]]*\(|replaceItem[[:space:]]*\(|copyItem[[:space:]]*\(|linkItem[[:space:]]*\(|createSymbolicLink[[:space:]]*\(|\brename(at)?[[:space:]]*\(')"

# 4. Writes: only our own log (ActivityStore) and a file the user chose in a save panel (Export).
check "Writes only in Sources/OverstayMac/ActivityStore.swift and App/Export.swift" \
  "$(hits 'createFile[[:space:]]*\(|FileHandle[[:space:]]*\(forWriting|FileHandle[[:space:]]*\(forUpdating|createDirectory[[:space:]]*\(|\.write[[:space:]]*\(to:|write[[:space:]]*\(toFile:|setAttributes[[:space:]]*\(|\bO_(WRONLY|RDWR|CREAT|APPEND|TRUNC)\b|\b(chmod|fchmod|chown|fchown|chflags|setxattr|removexattr)[[:space:]]*\(' '^(Sources/OverstayMac/ActivityStore|App/Export)\.swift:')"
check "UserDefaults, @AppStorage, @SceneStorage and iCloud key-value storage only in App/AppModel.swift" \
  "$(hits 'UserDefaults|@AppStorage|@SceneStorage|NSUbiquitousKeyValueStore' '^App/AppModel\.swift:')"

# 5. Never read file contents (stat only for .git discovery). ActivityStore reads our own log.
check "No reading of file contents outside Sources/OverstayMac/ActivityStore.swift" \
  "$(hits '(NS)?(Data|String)[[:space:]]*\(contentsOf(File)?:|NSData[[:space:]]*\(|NSString[[:space:]]*\(contentsOf|NS(Dictionary|Array)[[:space:]]*\(contentsOf|contentsOfFile|\.contents[[:space:]]*\(atPath|(^|[^[:alnum:]_.])(fopen|freopen|open|openat)[[:space:]]*\(|FileHandle[[:space:]]*\(forReading|InputStream[[:space:]]*\(|\bfread[[:space:]]*\(|\bpread[[:space:]]*\(|\bmmap[[:space:]]*\(|NSImage[[:space:]]*\(contentsOf' '^Sources/OverstayMac/ActivityStore\.swift:')"
check "File metadata calls (fileExists, attributesOfItem, stat, directory listings) only in GitRootFinder.swift and ActivityStore.swift" \
  "$(hits 'fileExists[[:space:]]*\(|attributesOfItem[[:space:]]*\(|(^|[^[:alnum:]_])l?stat[[:space:]]*\(|contentsOfDirectory|subpathsOfDirectory|enumerator[[:space:]]*\(|getxattr|listxattr' '^Sources/OverstayMac/(GitRootFinder|ActivityStore)\.swift:')"

# 6. Layering: Core is Foundation-only; libproc, sysctl and Darwin live in OverstayMac; the app never calls them.
check "Sources/OverstayCore imports only Foundation" \
  "$(hits '^[[:space:]]*(@testable )?import ' 'import Foundation[[:space:]]*$' Sources/OverstayCore)"
check "libproc, sysctl, Darwin, getsid, getuid, getpid, rusage only in Sources/OverstayMac (Core and App never touch them)" \
  "$(hits 'import (Darwin|Glibc|MachO|IOKit|Security)|proc_(pid|list|name|regionfilename|set)|libproc|sysctl|KERN_PROC|getsid[[:space:]]*\(|getpgid[[:space:]]*\(|getuid[[:space:]]*\(|geteuid[[:space:]]*\(|getpid[[:space:]]*\(|getppid[[:space:]]*\(|rusage' '' 'Sources/OverstayCore App')"
check "KERN_PROCARGS2 only in Sources/OverstayMac/ProcArgs.swift" \
  "$(hits 'KERN_PROCARGS2' '^Sources/OverstayMac/ProcArgs\.swift:')"

# 7. argv and environment never reach a log, a console or the system log.
check "No print, debugPrint, dump, NSLog, os_log, Logger or OSLog" \
  "$(hits '(^|[^[:alnum:]_.])(print|debugPrint|dump|NSLog)[[:space:]]*\(|\bos_log\b|\bLogger[[:space:]]*\(|OSLog')"
check "Our own environment is read only in App/Demo.swift (OVERSTAY_DEMO)" \
  "$(hits 'ProcessInfo\.processInfo\.environment|getenv[[:space:]]*\(|\benviron\b|setenv[[:space:]]*\(' '^App/Demo\.swift:')"

# 8. No network.
check "No network: no URLSession, Network framework, CFNetwork, sockets, web views, AsyncImage or CloudKit" \
  "$(hits 'URLSession|NSURLSession|NWConnection|NWPathMonitor|NWBrowser|NWListener|import Network|CFNetwork|CFStream|CFSocket|NSURLConnection|URLProtocol|WKWebView|WebKit|SFSafariView|AsyncImage|MultipeerConnectivity|NetService|CloudKit|(^|[^[:alnum:]_.])socket[[:space:]]*\(|\b(Darwin|Glibc)\.(socket|connect|bind|listen|accept|sendto|getaddrinfo)\b|getaddrinfo|gethostbyname')"
check "Opening apps and URLs (NSWorkspace, openURL, Link) only in App/AppModel.swift and App/OverstayApp.swift" \
  "$(hits 'NSWorkspace|LSOpen|openURL|\bLink[[:space:]]*\(' '^App/(AppModel|OverstayApp)\.swift:')"

# 8b. Data exits: the pasteboard, share sheets and notifications are the only ways data leaves the app besides a save panel.
check "Pasteboard (NSPasteboard, setString, setData) only in App/AppModel.swift and App/Export.swift" \
  "$(hits 'NSPasteboard|\.setString[[:space:]]*\(|\.setData[[:space:]]*\(' '^App/(AppModel|Export)\.swift:')"
check "Share services (NSSharingService, NSSharingServicePicker, ShareLink) nowhere" \
  "$(hits 'NSSharingService|ShareLink')"
check "No notifications in v1 (the site says it sends none): no UserNotifications, UNUserNotificationCenter or NSUserNotification" \
  "$(hits 'UserNotifications|UNUserNotificationCenter|UNMutableNotificationContent|NSUserNotification')"
check "No interpolation into fatalError, precondition or assert messages (a crash report must not carry names or argv)" \
  "$(hits '\b(fatalError|preconditionFailure|assertionFailure|precondition|assert)[[:space:]]*\(.*\\\(' '^App/Demo\.swift:')"

# 9. macOS 13 deployment target: newer APIs only in App/DesignSystem/Compat.swift, behind if #available.
check "macOS 14+ APIs only in App/DesignSystem/Compat.swift" \
  "$(hits 'ContentUnavailableView|\.onKeyPress|\.symbolEffect|Animation\.smooth|\.smooth[[:space:]]*\(|@Observable|@Bindable|\.inspector[[:space:]]*\(|\.contentMargins|Button[[:space:]]*\([^)]*systemImage:|initial:|AccessibilityNotification|backgroundProminence|SettingsLink|containerRelativeFrame|\.scrollPosition[[:space:]]*\(|\.phaseAnimator|\.keyframeAnimator|\.scrollTargetBehavior|\.sensoryFeedback|\.containerBackground|\.presentationBackground|\.focusEffectDisabled|\.defaultScrollAnchor|\.windowResizeBehavior|\.windowToolbarStyle|\.activate[[:space:]]*\(\)|buttonBorderShape[[:space:]]*\(\.capsule\)|onChange[[:space:]]*\(of:[^{]*\)[[:space:]]*\{[[:space:]]*[A-Za-z_]+[[:space:]]*,[[:space:]]*[A-Za-z_]+[[:space:]]+in' '^App/DesignSystem/Compat\.swift:')"

# 10. v1 has no updater and no third-party code.
check "No Sparkle and no other dependency: the app never goes online" \
  "$(grep -rnsE 'Sparkle|SUFeedURL|SUPublicEDKey|\.package[[:space:]]*\(' App Sources project.yml Package.swift | grep -vE "$C" || true)"

[ "$fail" -eq 0 ] && echo "safety greps: ok"
exit $fail
