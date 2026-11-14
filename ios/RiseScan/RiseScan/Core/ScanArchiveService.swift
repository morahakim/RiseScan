//
//  ScanArchiveService.swift
//  RiseScan
//
//  Created by mora hakim on 14/11/26.
//

import Foundation
import ZIPFoundation

final class ScanArchiveService {

    func createOriginalZip(scanID: UUID) throws -> URL {
        let folder = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        let zipURL = folder.appendingPathComponent(
            "\(scanID.uuidString).zip"
        )

        // Reuse the existing ZIP for this scan.
        if FileManager.default.fileExists(atPath: zipURL.path) {
            return zipURL
        }

        let files = try SampleScanFiles.getFiles()

        guard let archive = Archive(
            url: zipURL,
            accessMode: .create
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        for file in files {
            try archive.addEntry(
                with: file.lastPathComponent,
                fileURL: file,
                compressionMethod: .none
            )
        }

        return zipURL
    }
}

