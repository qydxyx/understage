import AppKit
import Foundation
import os
import PDFKit
import Vision

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
            } catch is RunCancelled {
                return (.cancelled, undos)
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
                try await ensureDownloadedIfNeeded(arg)
            }
            let log = try await runProcess(ToolDetector.resolve(executable), arguments, cwd: cwd, session: session)
            return (log, [])
        case .trash(let url):
            try await ensureDownloadedIfNeeded(url)
            var resulting: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            var undos: [UndoAction] = []
            if let trashURL = resulting as? URL {
                undos = [.restoreFromTrash(original: url.path, trash: trashURL.path)]
            }
            return (L10n.format("Trashed %@", url.lastPathComponent), undos)
        case .copyFile(let from, let to):
            try await ensureDownloadedIfNeeded(from)
            try FileManager.default.copyItem(at: from, to: to)
            return (L10n.format("Copied %@", to.lastPathComponent), [.trashCreated(to.path)])
        case .move(let from, let to):
            try await ensureDownloadedIfNeeded(from)
            let destination = try Self.destinationForMove(from: from, to: to)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileMoves.move(from, to: destination)
            return (L10n.format("Moved %@", from.lastPathComponent), [.moveBack(from: destination.path, to: from.path)])
        case .fileInfo(let field, let items, let folder):
            let text = await FileInfo.reportLoaded(field: field, items: items, folder: folder)
            return (text, [])
        case .copyPasteboard(let text):
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            return (L10n.tr("Copied to clipboard"), [])
        case .select(let urls):
            FinderScripting.select(urls)
            return (L10n.format("Selected %ld item(s)", urls.count), [])
        case .openTerminal(let folder):
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", "Terminal", folder.path]
            try task.run()
            task.waitUntilExit()
            return (L10n.tr("Opened Terminal"), [])
        case .mergePDF(let sources, let dest):
            return try await mergePDF(sources: sources, dest: dest)
        case .splitPDF(let source, let destFolder):
            return try await splitPDF(source: source, destFolder: destFolder)
        case .ocr(let sources, let destTxt, let copyToPasteboard):
            return try await ocr(sources: sources, destTxt: destTxt, copyToPasteboard: copyToPasteboard)
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
                    continuation.resume(throwing: RunCancelled())
                    return
                }
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: out.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    var message = out.trimmingCharacters(in: .whitespacesAndNewlines)
                    if message.contains("Cannot extract image from file") || proc.terminationStatus == 13 {
                        message += "\n" + L10n.tr("If this file is in iCloud or another cloud drive, keep it on this device and try again.")
                    }
                    continuation.resume(
                        throwing: NSError(
                            domain: "Understage",
                            code: Int(proc.terminationStatus),
                            userInfo: [
                                NSLocalizedDescriptionKey: message.isEmpty
                                    ? L10n.format("Command failed (%ld)", Int(proc.terminationStatus))
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

    /// `mv` into an existing directory. `FileManager.moveItem` does not, so append the filename.
    private static func destinationForMove(from: URL, to: URL) throws -> URL {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: to.path, isDirectory: &isDir), isDir.boolValue {
            return to.appendingPathComponent(from.lastPathComponent)
        }
        return to
    }

    private struct RunCancelled: Error {}

    private static func ensureDownloadedIfNeeded(_ path: String) async throws {
        guard path.starts(with: "/") else { return }
        try await ensureDownloadedIfNeeded(URL(fileURLWithPath: path))
    }

    private static func ensureDownloadedIfNeeded(_ url: URL) async throws {
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
        throw NSError(
            domain: "Understage",
            code: -2,
            userInfo: [
                NSLocalizedDescriptionKey:
                    L10n.format("Cloud file is not downloaded yet: %@. Keep it on this device and try again.", url.lastPathComponent),
            ]
        )
    }

    private static func mergePDF(sources: [URL], dest: URL) async throws -> (log: String?, undos: [UndoAction]) {
        for source in sources {
            try await ensureDownloadedIfNeeded(source)
        }
        let outputDoc = PDFDocument()
        var pageCount = 0
        for source in sources {
            let ext = source.pathExtension.lowercased()
            if ext == "pdf" {
                if let doc = PDFDocument(url: source) {
                    for i in 0 ..< doc.pageCount {
                        if let page = doc.page(at: i) {
                            outputDoc.insert(page, at: pageCount)
                            pageCount += 1
                        }
                    }
                }
            } else if let image = NSImage(contentsOf: source),
                      image.representations.isEmpty == false,
                      let page = PDFPage(image: image) {
                outputDoc.insert(page, at: pageCount)
                pageCount += 1
            }
        }
        guard pageCount > 0 else {
            throw NSError(
                domain: "Understage",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: L10n.tr("No valid pages to merge.")]
            )
        }
        guard outputDoc.write(to: dest) else {
            throw NSError(
                domain: "Understage",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: L10n.format("Failed to write merged PDF to %@", dest.lastPathComponent)]
            )
        }
        FinderScripting.select([dest])
        return (L10n.format("Merged %ld files (%ld pages) to %@", sources.count, pageCount, dest.lastPathComponent), [.trashCreated(dest.path)])
    }

    private static func splitPDF(source: URL, destFolder: URL) async throws -> (log: String?, undos: [UndoAction]) {
        try await ensureDownloadedIfNeeded(source)
        guard let doc = PDFDocument(url: source) else {
            throw NSError(
                domain: "Understage",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: L10n.format("Cannot open PDF: %@", source.lastPathComponent)]
            )
        }
        let total = doc.pageCount
        guard total > 1 else {
            throw NSError(
                domain: "Understage",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: L10n.tr("PDF has only 1 page, no split needed.")]
            )
        }
        let baseName = source.deletingPathExtension().lastPathComponent
        let digits = String(total).count
        var createdURLs: [URL] = []
        var undos: [UndoAction] = []
        for i in 0 ..< total {
            guard let page = doc.page(at: i) else { continue }
            let singleDoc = PDFDocument()
            singleDoc.insert(page, at: 0)
            let pageNum = String(format: "%0\(digits)d", i + 1)
            let pageName = "\(baseName)_page_\(pageNum).pdf"
            let dest = UniqueURL.next(
                in: destFolder,
                name: pageName,
                exists: { FileManager.default.fileExists(atPath: $0.path) }
            )
            if singleDoc.write(to: dest) {
                createdURLs.append(dest)
                undos.append(.trashCreated(dest.path))
            }
        }
        FinderScripting.select(createdURLs)
        return (L10n.format("Split %@ into %ld pages", source.lastPathComponent, createdURLs.count), undos)
    }

    private static func ocr(sources: [URL], destTxt: URL?, copyToPasteboard: Bool) async throws -> (log: String?, undos: [UndoAction]) {
        var allText: [String] = []
        for source in sources {
            try await ensureDownloadedIfNeeded(source)
            let ext = source.pathExtension.lowercased()
            if ext == "pdf" {
                guard let doc = PDFDocument(url: source) else { continue }
                var docText = ""
                for i in 0 ..< doc.pageCount {
                    guard let page = doc.page(at: i) else { continue }
                    if let str = page.string?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                        docText += str + "\n"
                    } else {
                        let bounds = page.bounds(for: .mediaBox)
                        let size = CGSize(width: max(bounds.width * 2, 1), height: max(bounds.height * 2, 1))
                        let image = page.thumbnail(of: size, for: .mediaBox)
                        let recognized = try await recognizeImage(image)
                        if !recognized.isEmpty {
                            docText += recognized + "\n"
                        }
                    }
                }
                if !docText.isEmpty {
                    allText.append(docText.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } else {
                let recognized = try await recognizeImageText(url: source)
                if !recognized.isEmpty {
                    allText.append(recognized)
                }
            }
        }
        let combined = allText.joined(separator: "\n\n---\n\n")
        guard !combined.isEmpty else {
            throw NSError(
                domain: "Understage",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: L10n.tr("No text recognized in selected file(s).")]
            )
        }
        var undos: [UndoAction] = []
        if let dest = destTxt {
            try combined.write(to: dest, atomically: true, encoding: .utf8)
            undos.append(.trashCreated(dest.path))
        }
        if copyToPasteboard {
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(combined, forType: .string)
            }
        }
        let preview = combined.prefix(80).replacingOccurrences(of: "\n", with: " ")
        return (L10n.format("OCR copied to clipboard (%ld chars): \"%@…\"", combined.count, String(preview)), undos)
    }

    private static func recognizeImageText(url: URL) async throws -> String {
        guard let image = NSImage(contentsOf: url) else { return "" }
        return try await recognizeImage(image)
    }

    private static func recognizeImage(_ image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }
        return try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let finish: (Result<String, Error>) -> Void = { result in
                let first = resumed.withLock { flag -> Bool in
                    if flag { return false }
                    flag = true
                    return true
                }
                guard first else { return }
                continuation.resume(with: result)
            }
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    finish(.failure(error))
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let strings = observations.compactMap { $0.topCandidates(1).first?.string }
                finish(.success(strings.joined(separator: "\n")))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                finish(.failure(error))
            }
        }
    }
}
