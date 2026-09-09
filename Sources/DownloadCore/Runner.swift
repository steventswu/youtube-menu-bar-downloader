import Foundation
import Darwin

/// Each invocation owns a process group; cancellation includes ffmpeg/JS children.
public final class Runner {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    public init() {}
    public func cancel() {
        lock.lock(); cancelled = true
        if let p = process, p.isRunning { kill(-p.processIdentifier, SIGKILL); kill(p.processIdentifier, SIGKILL) }
        lock.unlock()
    }
    public func run(_ executable: URL, _ arguments: [String], line: @escaping (String) -> Void = { _ in }) throws -> String {
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        let p = Process(), pipe = Pipe()
        // The bundled launcher establishes its process group before exec.
        let launcher = executable.deletingLastPathComponent().appendingPathComponent("process-launcher")
        p.executableURL = launcher; p.arguments = [executable.path] + arguments
        p.standardOutput = pipe; p.standardError = pipe
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = executable.deletingLastPathComponent().path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        env["LC_ALL"] = "en_US.UTF-8"; p.environment = env
        do { try p.run(); process = p; lock.unlock() } catch { lock.unlock(); throw error }
        pipe.fileHandleForWriting.closeFile()
        var pending = Data(), output = ""
        while true {
            let data = pipe.fileHandleForReading.availableData
            if data.isEmpty { break }
            pending.append(data)
            while let end = pending.firstIndex(of: 10) {
                let s = String(decoding: pending[..<end], as: UTF8.self)
                output += s + "\n"; line(s); pending.removeSubrange(...end)
            }
        }
        if !pending.isEmpty { let s = String(decoding: pending, as: UTF8.self); output += s; line(s) }
        p.waitUntilExit()
        lock.lock(); process = nil; let stopped = cancelled; lock.unlock()
        if stopped { throw CancellationError() }
        if p.terminationStatus != 0 { throw DownloadError.message(String(output.suffix(2000))) }
        return output
    }
}
