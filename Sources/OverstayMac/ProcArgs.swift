import Darwin
import Foundation

/// The only user of the process-arguments sysctl. argv and environment are secrets (BUILD_PLAN §3 rule 11): they are
/// parsed in memory, argv is handed to the caller (who scrubs it), and of the environment only the NAMES of allow-listed
/// keys survive. Values are never turned into Strings.
enum ProcArgs {
    /// `kern.argmax`, the size the kernel wants for the buffer. VERIFY on 13/15/26. Falls back to 1 MiB.
    private static let argMax: Int = {
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctl(&mib, 2, &value, &size, nil, 0) == 0 && value > 0 ? Int(value) : 1 << 20
    }()

    /// nil when the system refuses (other user, hardened or vanished process).
    static func read(pid: Int32, envKeys: [String]) -> (argv: [String], envMarkers: [String])? {
        guard pid > 0 else { return nil }
        // Uninitialised on purpose: only the bytes the kernel fills are ever touched.
        let raw = UnsafeMutableRawBufferPointer.allocate(byteCount: argMax, alignment: 16)
        defer { raw.deallocate() }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = argMax
        guard sysctl(&mib, 3, raw.baseAddress, &size, nil, 0) == 0, size > 4, size <= argMax else { return nil }
        return parse(Array(UnsafeRawBufferPointer(rebasing: raw[0..<size])), envKeys: envKeys)
    }

    /// Layout (VERIFY): Int32 argc, the exec path, its NUL and padding that rounds path + NUL up to a multiple of 8 bytes
    /// (xnu `exec_extract_strings` pads `ip_strspace` to the pointer size; the string area starts at the path), argc argv
    /// strings, then `KEY=value` strings, all NUL terminated. Pure and tolerant of truncation: whatever is complete is returned, nothing ever traps.
    static func parse(_ buf: [UInt8], envKeys: [String]) -> (argv: [String], envMarkers: [String])? {
        guard buf.count >= 4 else { return nil }
        // Little-endian on every Mac (arm64 and x86_64).
        let argc = Int(Int32(bitPattern: UInt32(buf[0]) | UInt32(buf[1]) << 8 | UInt32(buf[2]) << 16 | UInt32(buf[3]) << 24))
        guard argc >= 0 else { return nil }
        var i = 4
        let pathStart = i
        while i < buf.count, buf[i] != 0 { i += 1 }   // exec path
        if i < buf.count { i += 1 }                   // its NUL
        // Only the alignment padding is skipped, never a NUL beyond it: an empty argv[0] must stay an argv entry, or every
        // later string shifts by one and the first environment entry (a secret, maybe) would be read as an argument. If the
        // padding rule is ever wrong this errs towards extra empty arguments, never towards environment values in argv.
        while i < buf.count, buf[i] == 0, (i - pathStart) % 8 != 0 { i += 1 }
        var argv: [String] = []
        while argv.count < argc, i < buf.count {
            let start = i
            while i < buf.count, buf[i] != 0 { i += 1 }
            argv.append(String(decoding: buf[start..<i], as: UTF8.self))
            i += 1
        }
        var seen = Set<String>()
        while i < buf.count {
            let start = i
            while i < buf.count, buf[i] != 0 { i += 1 }
            // Only the key is decoded. An entry without '=' (or cut off before it) is ignored.
            if let eq = buf[start..<i].firstIndex(of: UInt8(ascii: "=")) {
                let key = String(decoding: buf[start..<eq], as: UTF8.self)
                if envKeys.contains(key) { seen.insert(key) }
            }
            i += 1
        }
        return (argv, envKeys.filter { seen.contains($0) })
    }
}
