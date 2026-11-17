//
//  UploadService.swift
//  RiseScan
//
//  Created by mora hakim on 16/11/26.
//

import Foundation

final class UploadService {
    private let apiClient = APIClient.shared

    func createUploadSession(
        scanID: UUID,
        kind: UploadKind,
        filename: String,
        sizeBytes: Int
    ) async throws -> CreateUploadResponse {
        let request = CreateUploadRequest(
            scanID: scanID,
            kind: kind,
            filename: filename,
            sizeBytes: sizeBytes
        )

        return try await apiClient.post(
            "uploads",
            body: request
        )
    }

    func completeUpload(
        uploadID: String,
        parts: [CompletedUploadPart],
        sha256: String
    ) async throws -> CompleteUploadResponse {
        let request = CompleteUploadRequest(
            parts: parts,
            sha256: sha256
        )

        return try await apiClient.post(
            "uploads/\(uploadID)/complete",
            body: request
        )
    }
    
    
    func uploadPart(
        fileURL: URL,
        part: UploadPart,
        partSize: Int
    ) async throws -> CompletedUploadPart {
        let etag = try await BackgroundUploadService.shared.uploadPart(
            fileURL: fileURL,
            uploadURL: part.url,
            partNumber: part.partNumber,
            partSize: partSize
        )

        return CompletedUploadPart(
            partNumber: part.partNumber,
            etag: etag
        )
    }

    
    
    enum UploadServiceError: Error {
        case invalidFileSize
        case invalidPartSize
        case verificationFailed(String)
    }

}

extension UploadService {


    func uploadFile(
        fileURL: URL,
        scanID: UUID,
        kind: UploadKind
    ) async throws -> String {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: fileURL.path
        )

        guard let fileSize = (attributes[.size] as? NSNumber)?.intValue,
              fileSize > 0 else {
            throw UploadServiceError.invalidFileSize
        }

        let uploadSession = try await createUploadSession(
            scanID: scanID,
            kind: kind,
            filename: fileURL.lastPathComponent,
            sizeBytes: fileSize
        )

        guard uploadSession.partSize > 0 else {
            throw UploadServiceError.invalidPartSize
        }

        // Check parts already uploaded to the server.
        let status = try await getUploadStatus(
            uploadID: uploadSession.uploadID
        )

        if status.status == "verified" {
            print("Upload already verified:", kind.rawValue)
            return uploadSession.uploadID
        }

        var completedParts = status.parts.map {
            CompletedUploadPart(
                partNumber: $0.partNumber,
                etag: $0.etag
            )
        }

        let uploadedPartNumbers = Set(
            status.parts.map { $0.partNumber }
        )

        // Upload only parts that are not on the server yet.
        for part in uploadSession.parts
            where !uploadedPartNumbers.contains(part.partNumber) {

            let completedPart = try await uploadPart(
                fileURL: fileURL,
                part: part,
                partSize: uploadSession.partSize
            )

            completedParts.append(completedPart)
            print("Uploaded part:", part.partNumber)
        }

        // Keep parts in ascending order.
        completedParts.sort {
            $0.partNumber < $1.partNumber
        }

        let sha256 = try FileHashService().sha256(of: fileURL)

        let result = try await completeUpload(
            uploadID: uploadSession.uploadID,
            parts: completedParts,
            sha256: sha256
        )

        guard result.status == "verified" else {
            throw UploadServiceError.verificationFailed(
                result.reason ?? "Unknown error"
            )
        }

        print("Upload verified:", kind.rawValue)
        return uploadSession.uploadID
    }

    
    func getUploadStatus(
        uploadID: String
    ) async throws -> UploadStatusResponse {
        return try await apiClient.get(
            "uploads/\(uploadID)"
        )
    }

}
