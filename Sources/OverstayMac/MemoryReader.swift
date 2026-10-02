import Darwin

enum MemoryReader {
    /// `ri_phys_footprint`: the number Activity Monitor labels "Memory". nil when the system refuses.
    static func footprint(pid: Int32) -> UInt64? {
        var usage = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return rc == 0 ? usage.ri_phys_footprint : nil
    }
}
