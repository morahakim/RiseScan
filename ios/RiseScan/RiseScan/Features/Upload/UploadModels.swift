//
//  UploadModels.swift
//  RiseScan
//
//  Created by mora hakim on 14/11/26.
//

import Foundation

enum UploadKind: String, Codable {
    case preview
    case original
}

struct CreateUploadRequest: Encodable {
    let scanID: UUID
    let kind: UploadKind
    let filename: String
    let sizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case scanID = "scan_id"
        case kind
        case filename
        case sizeBytes = "size_bytes"
    }
}

struct CreateUploadResponse: Decodable {
    let uploadID: String
    let partSize: Int
    let parts: [UploadPart]

    enum CodingKeys: String, CodingKey {
        case uploadID = "upload_id"
        case partSize = "part_size"
        case parts
    }
}

struct UploadPart: Decodable, Identifiable {
    let partNumber: Int
    let url: URL

    var id: Int { partNumber }

    enum CodingKeys: String, CodingKey {
        case partNumber = "part_number"
        case url
    }
}

