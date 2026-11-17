//
//  ContentView.swift
//  RiseScan
//
//  Created by mora hakim on 14/11/26.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("scanID") private var scanIDString = ""
    @AppStorage("originalUploadID") private var originalUploadID = ""
    @AppStorage("originalSHA256") private var originalSHA256 = ""
    
    @State private var downloadedFolderURL: URL?
    @State private var downloadMessage = ""
    @State private var isDownloading = false

    var body: some View {
        VStack(spacing: 12) {
            ScanPreviewView(modelFolderURL: downloadedFolderURL) { image in
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

                            let originalURL = try ScanArchiveService()
                                .createOriginalZip(scanID: scanID)

                            let uploadID = try await uploadService.uploadFile(
                                fileURL: originalURL,
                                scanID: scanID,
                                kind: .original
                            )

                            originalUploadID = uploadID
                            originalSHA256 = try FileHashService()
                                .sha256(of: originalURL)

                            print("Original upload completed:", uploadID)

                        } catch {
                            print("Upload failed:", error)
                        }
                    }
                } catch {
                    print("Preview save failed:", error)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(isDownloading ? "Downloading..." : "Download Original") {
                print("Download button tapped")
                Task {
                    await downloadOriginal()
                }
            }
            .disabled(originalUploadID.isEmpty || isDownloading)

            Text(downloadMessage)
                .font(.caption)
        }
    }
    
    private func getScanID() -> UUID {
        if let existingID = UUID(uuidString: scanIDString) {
            return existingID
        }

        let newID = UUID()
        scanIDString = newID.uuidString
        return newID
    }
    
    private func downloadOriginal() async {
        isDownloading = true
        downloadMessage = "Downloading..."

        defer {
            isDownloading = false
        }

        do {
            let service = DownloadService()

            let zipURL = try await service.downloadOriginal(
                uploadID: originalUploadID,
                expectedSHA256: originalSHA256
            )

            let folderURL = try service.extractOriginal(
                from: zipURL,
                uploadID: originalUploadID
            )

            downloadedFolderURL = folderURL
            downloadMessage = "Download verified successfully"

            print("Downloaded folder:", folderURL.path)

        } catch {
            downloadMessage = "Download failed: \(error.localizedDescription)"
            print("Download failed:", error)
        }
    }
}

#Preview {
    ContentView()
}
