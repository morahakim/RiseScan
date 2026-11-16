//
//  FileHashService.swift
//  RiseScan
//
//  Created by mora hakim on 16/11/26.
//

import Foundation
import CryptoKit

final class FileHashService {

    func sha256(of fileURL: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? fileHandle.close()
        }

        var hasher = SHA256()

        while let chunk = try fileHandle.read(upToCount: 1024 * 1024),
              !chunk.isEmpty {
            hasher.update(data: chunk)
        }

        let digest = hasher.finalize()

        return digest.map {
            String(format: "%02x", $0)
        }.joined()
    }
}

