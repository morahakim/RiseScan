//
//  ContentView.swift
//  RiseScan
//
//  Created by mora hakim on 14/11/26.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("scanID") private var scanIDString = ""

    var body: some View {
        ScanPreviewView { image in
            do {
                let url = try ScanPreviewService().savePreview(image)

                let size = try FileManager.default
                    .attributesOfItem(atPath: url.path)[.size] as? Int ?? 0

                print("Preview saved:", url.lastPathComponent)
                print("Preview size:", size, "bytes")
                
                let scanID = getScanID()
                print("Current scan ID:", scanID.uuidString)

                Task {
                    do {
                        
                        let uploadService = UploadService()

                        try await uploadService.uploadFile(
                            fileURL: url,
                            scanID: scanID,
                            kind: .preview
                        )

                        print("Preview upload completed")

                        let originalURL = try ScanArchiveService()
                            .createOriginalZip(scanID: scanID)

                        print("Original ZIP:", originalURL.lastPathComponent)
                        print("Current scan ID:", scanIDString)

                        try await uploadService.uploadFile(
                            fileURL: originalURL,
                            scanID: scanID,
                            kind: .original
                        )

                        print("Original upload completed")

                    } catch {
                        print("Upload failed:", error)
                    }
                }

            } catch {
                print("Preview save failed:", error)
            }
        }
        .ignoresSafeArea()
    }
    
    private func getScanID() -> UUID {
        if let existingID = UUID(uuidString: scanIDString) {
            return existingID
        }

        let newID = UUID()
        scanIDString = newID.uuidString
        return newID
    }
}

#Preview {
    ContentView()
}
