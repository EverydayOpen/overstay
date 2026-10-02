import Foundation

/// Project detection. stat only: `.git` is looked up, never opened, and nothing inside it is read.
enum GitRootFinder {
    /// Nearest directory at or above `cwd` that has a `.git` entry (a directory, or a file in a worktree). At most 16
    /// levels, never `home` itself (a dotfiles repo is not a project) and never "/". `cache` maps every directory
    /// visited to its answer, so a scan with hundreds of processes in a few projects does a few dozen stats.
    static func root(forCwd cwd: String, home: String, cache: inout [String: String?]) -> String? {
        var dir = cwd
        var visited: [String] = []
        var found: String?
        for _ in 0..<16 {
            if dir.isEmpty || dir == "/" || dir == home { break }
            if let hit = cache[dir] { found = hit; break }
            visited.append(dir)
            if FileManager.default.fileExists(atPath: dir + "/.git") { found = dir; break }
            guard let slash = dir.lastIndex(of: "/") else { break }
            dir = slash == dir.startIndex ? "/" : String(dir[..<slash])
        }
        for v in visited { cache[v] = .some(found) }
        return found
    }
}
