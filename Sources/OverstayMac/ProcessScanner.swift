import Darwin
import Foundation
import OverstayCore

/// Reads the process table through libproc and sysctl. Never throws, never signals, never reads file contents.
/// Other users' processes keep only identity and parentage; the user's own add argv (scrubbed), cwd, project root
/// and memory footprint. Every call here is VERIFY on macOS 13, 15 and 26 (BUILD_PLAN §2).
public enum ProcessScanner {
    public static func scan(now: Date = Date()) -> RawScan {
        let me = getuid()
        let home = NSHomeDirectory()
        var cache: [String: String?] = [:]
        var processes: [ProcessSnapshot] = []
        var unreadable = 0
        for pid in allPids() {
            guard let r = build(pid, me: me, home: home, cache: &cache) else { continue }
            processes.append(r.snapshot)
            if !r.complete { unreadable += 1 }
        }
        return RawScan(processes: processes, selfPid: getpid(), uid: me, home: home, scannedAt: now, unreadableCount: unreadable)
    }

    /// One pid, read the same way as in a scan (used right before a signal). nil = gone, zombie, or unreadable basics.
    public static func snapshot(pid: Int32) -> ProcessSnapshot? {
        guard pid > 0 else { return nil }
        var cache: [String: String?] = [:]
        return build(pid, me: getuid(), home: NSHomeDirectory(), cache: &cache)?.snapshot
    }

    /// Parent pid from the basic info alone (cheap), for walking our own ancestry. nil when unreadable.
    static func ppid(of pid: Int32) -> Int32? { basic(pid)?.ppid }

    // MARK: - reads

    private static func allPids() -> [pid_t] {
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return [] }
        // Headroom: processes can appear between the two calls.
        let capacity = Int(bytes) / MemoryLayout<pid_t>.size + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let got = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(capacity * MemoryLayout<pid_t>.size))
        guard got > 0 else { return [] }
        return pids.prefix(Int(got) / MemoryLayout<pid_t>.size).filter { $0 > 0 }
    }

    private struct Basic {
        var ppid: Int32, pgid: Int32, status: Int32, uid: UInt32, startSeconds: Int64, startMicroseconds: Int32, tdev: UInt32, comm: String
    }

    /// Identity, parentage and owner of any process, ours or not. sysctl(KERN_PROC_PID) is what ps uses and needs no
    /// privilege; proc_pidinfo(PROC_PIDTBSDINFO) was refused for launchd on the macos-26 runner (CI run 37054575257). VERIFY
    private static func basic(_ pid: pid_t) -> Basic? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var k = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &k, &size, nil, 0) == 0, size == MemoryLayout<kinfo_proc>.stride, k.kp_proc.p_pid == pid else { return nil }
        return Basic(ppid: k.kp_eproc.e_ppid, pgid: k.kp_eproc.e_pgid, status: Int32(k.kp_proc.p_stat),
                     uid: k.kp_eproc.e_ucred.cr_uid, startSeconds: Int64(k.kp_proc.p_starttime.tv_sec),
                     startMicroseconds: Int32(truncatingIfNeeded: k.kp_proc.p_starttime.tv_usec),
                     tdev: UInt32(bitPattern: k.kp_eproc.e_tdev), comm: cString(&k.kp_proc.p_comm))
    }

    private static func pidPath(_ pid: pid_t) -> String {
        var buf = [UInt8](repeating: 0, count: 4096)   // PROC_PIDPATHINFO_MAXSIZE is a computed macro: spelled out
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(decoding: buf.prefix(Int(n)), as: UTF8.self) : ""
    }

    private static func cwd(_ pid: pid_t) -> String? {
        var vnode = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, size) == size else { return nil }
        let path = cString(&vnode.pvi_cdir.vip_path)
        return path.isEmpty ? nil : path
    }

    /// A fixed C char array (imported as a tuple) up to its first NUL.
    private static func cString<T>(_ field: inout T) -> String {
        withUnsafeBytes(of: &field) { raw in String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self) }
    }

    /// `complete` is false for a same-user process whose argv, cwd or footprint the system refused.
    private static func build(_ pid: pid_t, me: uid_t, home: String, cache: inout [String: String?])
        -> (snapshot: ProcessSnapshot, complete: Bool)? {
        guard let info = basic(pid) else { return nil }
        if info.status == 5 { return nil }   // SZOMB (sys/proc.h). VERIFY
        let path = pidPath(pid)
        let name = path.isEmpty && !info.comm.isEmpty ? info.comm : nil
        let uid = info.uid
        let sid = getsid(pid)
        let tdev = info.tdev

        var argv: [String] = []
        var markers: [String] = []
        var dir: String?
        var root: String?
        var footprint: UInt64 = 0
        var complete = true
        if uid == me {
            if let a = ProcArgs.read(pid: pid, envKeys: EnvMarkers.allowed) {
                argv = Scrub.argv(a.argv)
                markers = a.envMarkers
            } else { complete = false }
            if let c = cwd(pid) {
                dir = c
                root = GitRootFinder.root(forCwd: c, home: home, cache: &cache)
            } else { complete = false }
            if let f = MemoryReader.footprint(pid: pid) { footprint = f } else { complete = false }
        }
        let snapshot = ProcessSnapshot(
            pid: pid, ppid: info.ppid, pgid: info.pgid,
            sid: sid < 0 ? nil : sid, uid: uid,
            startSeconds: info.startSeconds, startMicroseconds: info.startMicroseconds,
            path: path, name: name, argv: argv, cwd: dir, projectRoot: root, footprintBytes: footprint,
            // No controlling tty is NODEV (all ones); 0 is treated the same. VERIFY
            ttyDevice: tdev == 0 || tdev == UInt32.max ? nil : tdev,
            isSessionLeader: sid == pid, stdin: .unknown, envMarkers: markers)
        return (snapshot, complete)
    }
}
