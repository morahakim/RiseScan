//
//  DownloadService.swift
//  RiseScan
//
//  Created by Mora Hakim on 17/11/26.
//

import Foundation
import ZIPFoundation

final class DownloadService {
    private let apiClient = APIClient.shared

    func downloadOriginal(uploadID: String, expectedSHA256: String) async throws -> URL {
        let response: DownloadResponse = try await apiClient.get(
            "uploads/\(uploadID)/download"
        )

        let (temporaryURL, urlResponse) = try await URLSession.shared.download(
            from: response.url
        )

        guard let httpResponse = urlResponse as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        let folder = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        let destinationURL = folder.appendingPathComponent(
            "\(uploadID)-download.zip"
        )

        let downloadedSHA256 = try FileHashService()
            .sha256(of: destinationURL)

        guard downloadedSHA256 == expectedSHA256 else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw DownloadError.checksumMismatch
        }
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.moveItem(
            at: temporaryURL,
            to: destinationURL
        )

        return destinationURL
    }
    
    func extractOriginal(from zipURL: URL, uploadID: String) throws -> URL {
        let folder = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        let destinationURL = folder.appendingPathComponent(
            "Downloaded-\(uploadID)",
            isDirectory: true
        )

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: true
        )

        guard let archive = Archive(url: zipURL, accessMode: .read) else {
            throw DownloadError.invalidArchive
        }

        for entry in archive {
            let filename = URL(fileURLWithPath: entry.path).lastPathComponent

            guard !filename.isEmpty,
                  filename != ".",
                  filename != "..",
                  entry.path == filename else {
                throw DownloadError.invalidArchive
            }

            let fileURL = destinationURL.appendingPathComponent(filename)
            try archive.extract(entry, to: fileURL)
        }

        return destinationURL
    }
}

enum DownloadError: Error {
    case checksumMismatch
    case invalidArchive
}
