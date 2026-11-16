//
//  BackgroundUploadService.swift
//  RiseScan
//
//  Created by mora hakim on 16/11/26.
//

import Foundation

final class BackgroundUploadService: NSObject, URLSessionTaskDelegate {
    static let shared = BackgroundUploadService()
    private var backgroundCompletionHandler: (() -> Void)?

    private let lock = NSLock()
    private var completions: [
        Int: (CheckedContinuation<String, Error>, URL)
    ] = [:]

    private lazy var session: URLSession = {
        let identifier = (
            Bundle.main.bundleIdentifier ?? "RiseScan"
        ) + ".background-upload"

        let configuration = URLSessionConfiguration.background(
            withIdentifier: identifier
        )

        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true

        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
    }()

    private override init() {
        super.init()
    }

    func uploadPart(
        fileURL: URL,
        uploadURL: URL,
        partNumber: Int,
        partSize: Int
    ) async throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? fileHandle.close()
        }

        let offset = (partNumber - 1) * partSize
        try fileHandle.seek(toOffset: UInt64(offset))

        let attributes = try FileManager.default.attributesOfItem(
            atPath: fileURL.path
        )

        guard let fileSize = (attributes[.size] as? NSNumber)?.intValue else {
            throw CocoaError(.fileReadUnknown)
        }

        let currentSize = min(partSize, fileSize - offset)

        guard currentSize > 0,
              let data = try fileHandle.read(upToCount: currentSize),
              data.count == currentSize else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackgroundUploads")

        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        let partFile = folder.appendingPathComponent(
            UUID().uuidString
        )

        try data.write(to: partFile)

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.uploadTask(
                with: request,
                fromFile: partFile
            )

            lock.lock()
            completions[task.taskIdentifier] = (
                continuation,
                partFile
            )
            lock.unlock()

            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        let completion = completions.removeValue(
            forKey: task.taskIdentifier
        )
        lock.unlock()

        guard let completion else {
            return
        }

        let (continuation, partFile) = completion

        try? FileManager.default.removeItem(at: partFile)

        if let error {
            continuation.resume(throwing: error)
            return
        }

        guard let response = task.response as? HTTPURLResponse else {
            continuation.resume(
                throwing: APIError.invalidResponse
            )
            return
        }

        guard (200...299).contains(response.statusCode) else {
            continuation.resume(
                throwing: APIError.serverError(response.statusCode)
            )
            return
        }

        guard let etag = response.value(
            forHTTPHeaderField: "ETag"
        ) else {
            continuation.resume(
                throwing: APIError.missingETag
            )
            return
        }

        continuation.resume(returning: etag)
    }
    
    func setBackgroundCompletionHandler(
        _ handler: @escaping () -> Void
    ) {
        backgroundCompletionHandler = handler
    }

    func urlSessionDidFinishEvents(
        forBackgroundURLSession session: URLSession
    ) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
    
    func restoreBackgroundSession() {
        _ = session
    }
}

