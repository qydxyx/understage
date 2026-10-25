import AppKit
import Foundation
import os

enum CommandRunner {
    enum Outcome: Equatable {
        case success(String)
        case failure(String)
        case cancelled
    }

    final class Session: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false

        func cancel() {
            lock.lock()
            cancelled = true
            let running = process
            lock.unlock()
            running?.terminate()
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func attach(_ process: Process) {
            lock.lock()
            self.process = process
            lock.unlock()
        }
    }

    static func run(_ plan: CommandPlan, session: Session) async -> Outcome {
        await runWithUndo(plan, session: session).outcome
    }

    static func runWithUndo(_ plan: CommandPlan, session: Session) async -> (outcome: Outcome, undos: [UndoAction]) {
        if let ready = plan.readyResult, plan.steps.isEmpty {
            return (.success(ready), [])
        }
        var logs: [String] = []
        var undos: [UndoAction] = []
        for step in plan.steps {
            if session.isCancelled { return (.cancelled, undos) }
            do {
                let result = try await perform(step, cwd: plan.workingDirectory, session: session)
                if let line = result.log { logs.append(line) }
                undos.append(contentsOf: result.undos)
            } catch {
                return (.failure(error.localizedDescription), undos)
            }
        }
        if session.isCancelled { return (.cancelled, undos) }
        for created in plan.creates where FileManager.default.fileExists(atPath: created.path) {
            if !undos.contains(where: {
                if case .trashCreated(let path) = $0 { return path == created.path }
                return false
            }) {
                undos.append(.trashCreated(created.path))
            }
        }
        if !plan.reveal.isEmpty {
            FinderScripting.select(plan.reveal)
        }
        if let ready = plan.readyResult, logs.isEmpty { return (.success(ready), undos) }
        if logs.isEmpty { return (.success(plan.summary), undos) }
        return (.success(logs.joined(separator: "\n")), undos)
    }

    private static func perform(_ step: PlanStep, cwd: URL?, session: Session) async throws -> (log: String?, undos: [UndoAction]) {
        switch step {
        case .process(let executable, let arguments):
            for arg in arguments {
                await ensureDownloadedIfNeeded(arg)
            }
            let log = try await runProcess(executable, arguments, cwd: cwd, session: session)
            return (log, [])
        case .trash(let url):
            var resulting: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            var undos: [UndoAction] = []
            if let trashURL = resulting as? URL {
                undos = [.restoreFromTrash(original: url.path, trash: trashURL.path)]
            }
            return ("Trashed \(url.lastPathComponent)", undos)
        case .copyFile(let from, let to):
            try FileManager.default.copyItem(at: from, to: to)
            return ("Copied \(to.lastPathComponent)", [.trashCreated(to.path)])
        case .move(let from, let to):
            try FileManager.default.moveItem(at: from, to: to)
            return ("Moved \(from.lastPathComponent)", [.moveBack(from: to.path, to: from.path)])
        case .copyPasteboard(let text):
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            return ("Copied to clipboard", [])
        case .select(let urls):
            FinderScripting.select(urls)
            return ("Selected \(urls.count) item(s)", [])
        case .openTerminal(let folder):
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", "Terminal", folder.path]
            try task.run()
            task.waitUntilExit()
            return ("Opened Terminal", [])
        }
    }

    private static func runProcess(
        _ executable: String,
        _ arguments: [String],
        cwd: URL?,
        session: Session
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = cwd
            var env = ProcessInfo.processInfo.environment
            let extras = ToolDetector.searchRoots.joined(separator: ":")
            env["PATH"] = extras + ":" + (env["PATH"] ?? "")
            process.environment = env
            let stderr = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = stderr
            let errData = OSAllocatedUnfairLock(initialState: Data())
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty {
                    errData.withLock { $0.append(chunk) }
                }
            }
            session.attach(process)
            process.terminationHandler = { proc in
                stderr.fileHandleForReading.readabilityHandler = nil
                let extra = stderr.fileHandleForReading.readDataToEndOfFile()
                let out = errData.withLock { collected in
                    collected.append(extra)
                    return String(data: collected, encoding: .utf8) ?? ""
                }
                if session.isCancelled {
                    continuation.resume(returning: "Cancelled")
                    return
                }
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: out.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    var message = out.trimmingCharacters(in: .whitespacesAndNewlines)
                    if message.contains("Cannot extract image from file") || proc.terminationStatus == 13 {
                        message += "\n(Tip: If this file is stored in Google Drive / iCloud, please right-click it in Finder and choose 'Always keep on this device' or ensure it is downloaded.)"
                    }
                    continuation.resume(
                        throwing: NSError(
                            domain: "Understage",
                            code: Int(proc.terminationStatus),
                            userInfo: [
                                NSLocalizedDescriptionKey: message.isEmpty
                                    ? "Command failed (\(proc.terminationStatus))"
                                    : message,
                            ]
                        )
                    )
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func ensureDownloadedIfNeeded(_ path: String) async {
        guard path.starts(with: "/") else { return }
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return
        }
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              values.isUbiquitousItem == true else {
            return
        }
        if values.ubiquitousItemDownloadingStatus == .current {
            return
        }
        NSLog("[Understage] Requesting download for cloud file: %@", url.lastPathComponent)
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        let start = Date()
        while Date().timeIntervalSince(start) < 5.0 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let updated = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
               updated.ubiquitousItemDownloadingStatus == .current {
                NSLog("[Understage] Cloud file downloaded: %@", url.lastPathComponent)
                return
            }
        }
    }
}
