//
//  SampleScanFiles.swift
//  RiseScan
//
//  Created by mora hakim on 14/11/26.
//

import Foundation

enum SampleScanFiles {
    static func getFiles() throws -> [URL] {
        let filenames = [
            "Engineering_iOS_Assessment.obj",
            "Engineering_iOS_Assessment.mtl",
            "Engineering_iOS_Assessment.jpg",
            "manifest.json"
        ]

        guard let resourceURL = Bundle.main.resourceURL else {
            throw CocoaError(.fileNoSuchFile)
        }

        return try filenames.map { filename in
            let url = resourceURL.appendingPathComponent(filename)

            guard FileManager.default.fileExists(atPath: url.path) else {
                throw CocoaError(.fileNoSuchFile)
            }

            return url
        }
    }
}
